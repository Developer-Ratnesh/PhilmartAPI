/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 11 : catalogue read access and the system actor

   Two gaps in 009 stopped the M2 flows from working at all:

   1. Every Shop-owned table is filtered to the caller's own Shop, including
      List_Listing, Item_Item, Item_Image, List_Bid and Shop_DeliveryMethod.
      A visitor or a buyer saw no listings, so the public marketplace (BR-02)
      and item detail (BR-03) came back empty.
   2. Nothing admitted actor kind 'system', which Sys_AuditEvent already allows
      and which the background jobs use (Development Guide section 6). Auction
      close and the recovery sweep could not see the listings they close.
      P_List_Bid_Place writes an audit row carrying the listing's Shop, so it
      could not succeed under a buyer's session either. The API runs the
      commitment procedures as 'system' after it has authorised the buyer.

   Reads are opened only for rows that are public anyway: live and closed
   listings, the items and images behind them, their bids, and the delivery
   methods a Shop offers. Writes are unchanged. Every block predicate is still
   strict tenancy, so one Shop can't write another Shop's rows (clause 9.1).

   Raised with the Client as a query against 009. 001 to 010 are not edited.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- a function bound to a policy can't be altered, so the policies go first
DROP SECURITY POLICY philmart.ShopTenantPolicy;
DROP SECURITY POLICY philmart.BuyerSelfPolicy;
DROP SECURITY POLICY philmart.PlatformVisiblePolicy;
DROP SECURITY POLICY philmart.ShopOrBuyerPolicy;
GO

ALTER FUNCTION philmart.FN_ShopTenantPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

ALTER FUNCTION philmart.FN_BuyerSelfPredicate (@buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

ALTER FUNCTION philmart.FN_ShopOrPlatformPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId IS NULL
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

ALTER FUNCTION philmart.FN_ShopOrBuyerPredicate
    (@shopId AS UNIQUEIDENTIFIER, @buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR (@shopId IS NOT NULL
           AND @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER))
       OR (@buyerId IS NOT NULL
           AND CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'Buy_Buyer'
           AND @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER))
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

-- Live and closed listings are public. Draft, scheduled, withdrawn, expired
-- and cancelled stay with the Shop.
CREATE FUNCTION philmart.FN_CatalogueListingPredicate (@shopId AS UNIQUEIDENTIFIER, @state AS VARCHAR(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE @state IN ('live', 'sold', 'unsold')
       OR CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER);
GO

-- Ready to List, removed, missing and the rest are Shop stock, not catalogue.
CREATE FUNCTION philmart.FN_CatalogueItemPredicate (@shopId AS UNIQUEIDENTIFIER, @state AS VARCHAR(30))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE @state IN ('listed', 'sold_fulfilment_pending', 'complete')
       OR CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER);
GO

CREATE FUNCTION philmart.FN_CatalogueImagePredicate (@shopId AS UNIQUEIDENTIFIER, @itemId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR EXISTS (SELECT 1 FROM philmart.Item_Item AS i
                  WHERE i.ID = @itemId AND i.State IN ('listed', 'sold_fulfilment_pending', 'complete'));
GO

-- Bidders need the whole bid history of an auction to see what they have to
-- beat. The API picks which columns go out, buyer identities never do.
CREATE FUNCTION philmart.FN_CatalogueBidPredicate (@shopId AS UNIQUEIDENTIFIER, @listingId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR EXISTS (SELECT 1 FROM philmart.List_Listing AS l
                  WHERE l.ID = @listingId AND l.State IN ('live', 'sold', 'unsold'));
GO

-- D009: buyers choose from the methods a Shop offers, so enabled ones are public
CREATE FUNCTION philmart.FN_ShopOfferPredicate (@shopId AS UNIQUEIDENTIFIER, @enabled AS BIT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE @enabled = 1
       OR CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) IN ('platform_admin', 'system')
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER);
GO

-- Same four policies as 009. Only the five catalogue FILTER predicates differ.
CREATE SECURITY POLICY philmart.ShopTenantPolicy
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_User,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_User,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_UserPermission,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_UserPermission,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Settings,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Settings,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_CommercialTerms,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_CommercialTerms,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Location,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Location,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_StockLocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_StockLocation,
    ADD FILTER PREDICATE philmart.FN_ShopOfferPredicate(ShopID, Enabled) ON philmart.Shop_DeliveryMethod,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_DeliveryMethod,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD FILTER PREDICATE philmart.FN_CatalogueItemPredicate(ShopID, State) ON philmart.Item_Item,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Item,
    ADD FILTER PREDICATE philmart.FN_CatalogueImagePredicate(ShopID, ItemID) ON philmart.Item_Image,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Image,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD FILTER PREDICATE philmart.FN_CatalogueListingPredicate(ShopID, State) ON philmart.List_Listing,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Listing,
    ADD FILTER PREDICATE philmart.FN_CatalogueBidPredicate(ShopID, ListingID) ON philmart.List_Bid,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Bid,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Transaction,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Transaction,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_FulfilmentSnapshot,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_FulfilmentSnapshot,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Fulfilment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Fulfilment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaidItemAttention,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaidItemAttention,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_CombinedShippingGroup,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_CombinedShippingGroup,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Invoice,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Invoice,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_InvoiceLine,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_InvoiceLine,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Payment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Payment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaymentAllocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaymentAllocation,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Account,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Account,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_AccountEntry,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_AccountEntry,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_ProceedsEntry,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_ProceedsEntry,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Payment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Payment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopConfig,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopConfig,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Accrual,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Accrual,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Invoice,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Invoice,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_InvoiceLine,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_InvoiceLine,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopPayment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopPayment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopAllocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopAllocation,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Query,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Query,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_QueryMessage,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_QueryMessage,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Notification,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Notification,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_SettingValidationFlag,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_SettingValidationFlag,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_AuditEvent,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_AuditEvent,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_GovernanceException,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_GovernanceException,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_Run,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_Run,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Application,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Application,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_AuctionEventShop,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_AuctionEventShop,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_OutbidAlertLog,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_OutbidAlertLog
WITH (STATE = ON);
GO

CREATE SECURITY POLICY philmart.BuyerSelfPolicy
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_Address,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_Address,
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_ShippingPreference,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_ShippingPreference,
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_CommunicationPreference,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_CommunicationPreference
WITH (STATE = ON);
GO

CREATE SECURITY POLICY philmart.PlatformVisiblePolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent
WITH (STATE = ON);
GO

CREATE SECURITY POLICY philmart.ShopOrBuyerPolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction
WITH (STATE = ON);
GO
