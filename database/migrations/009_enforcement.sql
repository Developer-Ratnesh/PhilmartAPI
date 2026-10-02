/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 9 of 9 : security, Row Level Security, immutability triggers,
                 state machine guard, auction and money procedures

   Agreement clause 9.1: a failure of Shop isolation is a CRITICAL Severity
   Defect. RLS here is defence in depth — the API must ALSO authorise every
   operation server-side. Neither layer alone is sufficient.

   EVERY trigger below is SET-BASED. SQL Server fires triggers once per
   STATEMENT, not once per row. A row-at-a-time guard silently passes
   multi-row writes, which is the single most dangerous difference from the
   PostgreSQL original.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------- application security ---- */
IF DATABASE_PRINCIPAL_ID('philmart_app') IS NULL
    CREATE ROLE philmart_app;
GO
IF DATABASE_PRINCIPAL_ID('philmart_migrator') IS NULL
    CREATE ROLE philmart_migrator;
GO

GRANT SELECT, INSERT, UPDATE ON SCHEMA::philmart TO philmart_app;
GRANT EXECUTE ON SCHEMA::philmart TO philmart_app;
/* Deliberately NOT granted: DELETE. Nothing in this system is hard-deleted. */
DENY DELETE ON SCHEMA::philmart TO philmart_app;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'The runtime role. DELETE is explicitly DENIED across the schema: corrections are linked reversals, adjustments or superseding records (Agreement clause 8). It must NOT be granted db_owner, sysadmin, or any membership that bypasses Row Level Security — RLS does not apply to members of db_owner.',
 @level0type=N'USER',@level0name=N'philmart_app';
GO

/* --------------------------------------------------- Row Level Security ----
   SQL Server RLS is an inline table-valued predicate function plus a security
   policy. The predicate is evaluated for every row, so it must be cheap and
   must be schemabound.

   IMPORTANT: RLS does NOT apply to members of db_owner or to sysadmin. The
   application must connect as a principal in philmart_app and nothing more.  */
CREATE FUNCTION philmart.FN_ShopTenantPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

CREATE FUNCTION philmart.FN_BuyerSelfPredicate (@buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* Rows whose ShopID is NULL are PLATFORM-scoped and legitimately visible to
   every Shop: a PHILMART-run auction event, and a platform-wide Buy_Buyer
   restriction which takes precedence over a Shop's own (D045). Using the strict
   predicate here would hide exactly the rows a Shop must obey.               */
CREATE FUNCTION philmart.FN_ShopOrPlatformPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @shopId IS NULL
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* Rows a Shop reads by tenancy AND a Buy_Buyer reads about themselves: a legal
   acceptance, an outbound email. SQL Server permits only one filter predicate
   per table, so the two audiences are combined into one function rather than
   two policies.                                                              */
CREATE FUNCTION philmart.FN_ShopOrBuyerPredicate
    (@shopId AS UNIQUEIDENTIFIER, @buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR (@shopId IS NOT NULL
           AND @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER))
       OR (@buyerId IS NOT NULL
           AND CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'Buy_Buyer'
           AND @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER))
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* One policy over every Shop-owned table. FILTER hides rows on read; BLOCK
   refuses writes that would place a row outside the caller's tenant.         */
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
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_DeliveryMethod,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_DeliveryMethod,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Item,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Item,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Image,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Image,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Listing,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Listing,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Bid,
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
    /* Strict: a NULL ShopID on these tables is platform-scoped and stays
       admin-only, because "ShopID = current" is UNKNOWN against NULL and the
       row is filtered out. That is the intended behaviour here.              */
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

/* PHILMART-run auction events (ShopID NULL) must be visible to participating
   Shops; a platform-wide Buy_Buyer restriction (ShopID NULL) must be visible to
   every Shop because it takes precedence over their own (D045).             */
CREATE SECURITY POLICY philmart.PlatformVisiblePolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent
WITH (STATE = ON);
GO

/* Read by a Shop for its own rows, and by a Buy_Buyer for their own. */
CREATE SECURITY POLICY philmart.ShopOrBuyerPolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction
WITH (STATE = ON);
GO

/* Note on Buy_Query: the Shop tenant predicate above governs Shop access.
   The Buy_Buyer's own view of the SAME case row (D046 — one case, two lawful
   readers) is served through a dedicated API path that runs with
   actor_kind = 'Buy_Buyer'; because SQL Server applies one predicate per table,
   that path reads through philmart.v_buyer_query_self below rather than a
   second policy.                                                            */
CREATE VIEW philmart.VW_BuyerQuerySelf
WITH SCHEMABINDING
AS
SELECT q.ID, q.ShopID, q.BuyerID, q.Reference, q.Subject, q.Status,
       q.OpenedAt, q.LastMessageAt, q.ClosedAt, q.ReopenedCount
FROM philmart.Buy_Query AS q
WHERE q.BuyerID = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER)
  AND CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'Buy_Buyer';
GO

/* --------------------------------------------- immutability enforcement ---
   D019 / BR-15-R02: an ISSUED Sale_Invoice is immutable. Only the supersede link and
   a cancellation may be set, and only once. Set-based.                       */
CREATE TRIGGER philmart.TR_invoice_immutable_when_issued
ON philmart.Sale_Invoice
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    IF EXISTS (
        SELECT 1
        FROM deleted  AS d
        JOIN inserted AS i ON i.ID = d.ID
        WHERE d.State = 'issued'
          /* permitted: a single cancellation */
          AND NOT (i.State = 'cancelled' AND d.State <> 'cancelled')
          /* permitted: linking a superseding Sale_Invoice, once */
          AND NOT (d.SupersededByID IS NULL AND i.SupersededByID IS NOT NULL
                   AND i.State = d.State
                   AND i.TotalMinor = d.TotalMinor
                   AND i.SubtotalMinor = d.SubtotalMinor
                   AND i.ShippingMinor = d.ShippingMinor
                   AND i.AdjustmentMinor = d.AdjustmentMinor))
    BEGIN
        THROW 50021, 'An issued Sale_Invoice is immutable (D019). Correct it with a linked credit, adjustment or superseding Sale_Invoice — never by editing. Only a cancellation or a one-time supersede link is permitted.', 1;
    END
END;
GO

CREATE TRIGGER philmart.TR_invoice_no_delete
ON philmart.Sale_Invoice
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50022, 'philmart.invoice is never deleted (D019).', 1;
END;
GO

/* Invoice lines follow the Sale_Invoice: mutable only while the Sale_Invoice is draft. */
CREATE TRIGGER philmart.TR_invoice_line_immutable
ON philmart.Sale_InvoiceLine
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1 FROM deleted AS d
        JOIN philmart.Sale_Invoice AS inv ON inv.ID = d.InvoiceID
        WHERE inv.State <> 'draft')
    BEGIN
        THROW 50023, 'Invoice lines are immutable once the Sale_Invoice is issued (D019).', 1;
    END
END;
GO

/* D012/D013: a historical Listing is read-only and is NEVER reopened. */
CREATE TRIGGER philmart.TR_listing_historical_readonly
ON philmart.List_Listing
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1 FROM deleted AS d
        WHERE d.State IN ('sold','unsold','withdrawn','expired','cancelled'))
    BEGIN
        THROW 50024, 'A historical Listing (sold, unsold, withdrawn, expired or cancelled) is read-only. It is never reopened — a further offer of the Item uses a NEW Listing (D012, D013).', 1;
    END
END;
GO

CREATE TRIGGER philmart.TR_listing_no_delete
ON philmart.List_Listing
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50025, 'philmart.listing is never deleted.', 1;
END;
GO

/* D039: identity fields are read-only after registration completes. */
CREATE TRIGGER philmart.TR_buyer_identity_readonly
ON philmart.Buy_Buyer
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1
        FROM deleted AS d JOIN inserted AS i ON i.ID = d.ID
        WHERE d.RegistrationCompletedAt IS NOT NULL
          AND (ISNULL(i.IdentificationType,'')   <> ISNULL(d.IdentificationType,'')
            OR ISNULL(i.IdentificationNumber,'') <> ISNULL(d.IdentificationNumber,'')
            OR ISNULL(i.DateOfBirth,'1900-01-01') <> ISNULL(d.DateOfBirth,'1900-01-01')))
    BEGIN
        THROW 50026, 'Identification type, identification number and date of birth are read-only account and audit information after registration (D039).', 1;
    END
END;
GO

/* --------------------------------------------- Item_Item state machine guard ---
   Set-based. Validates every transition in the statement against
   Item_TransitionRule, then writes one history row per changed Item_Item.        */
CREATE TRIGGER philmart.TR_item_transition_guard
ON philmart.Item_Item
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF NOT UPDATE(State) RETURN;

    /* 1. Refuse any transition absent from the state machine. */
    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN inserted AS i ON i.ID = d.ID
        LEFT JOIN philmart.Item_TransitionRule AS r
               ON r.FromState = d.State AND r.ToState = i.State
        WHERE i.State <> d.State AND r.FromState IS NULL)
    BEGIN
        THROW 50027, 'Illegal Item state transition. The move is not present in philmart.item_transition_rule, which is the authoritative state machine. Note there is no exit from returned_to_seller or written_off (both terminal) and no Pending Return state (D065).', 1;
    END

    /* 2. Refuse a transition that requires a reason without one. */
    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN inserted AS i ON i.ID = d.ID
        JOIN philmart.Item_TransitionRule AS r
          ON r.FromState = d.State AND r.ToState = i.State
        WHERE i.State <> d.State
          AND r.RequiresReason = 1
          AND (i.RemovalNote IS NULL OR LEN(LTRIM(RTRIM(i.RemovalNote))) = 0))
    BEGIN
        THROW 50028, 'This Item state transition requires a recorded reason (see Item_TransitionRule.decision_ref). D066: Remove from Stock with reason Other requires a mandatory internal note.', 1;
    END

    /* 3. Maintain the D061 ageing clock and the state timestamp. */
    UPDATE it
       SET ReadyToListSince = CASE WHEN i.State = 'ready_to_list'
                                      THEN philmart.ServerNow() ELSE NULL END,
           StateChangedAt    = philmart.ServerNow()
    FROM philmart.Item_Item AS it
    JOIN inserted AS i ON i.ID = it.ID
    JOIN deleted  AS d ON d.ID = it.ID
    WHERE i.State <> d.State;

    /* 4. One history row per changed Item_Item (BR-10-R12). */
    INSERT INTO philmart.Item_StateHistory
        (ItemID, ShopID, FromState, ToState, Reason, ChangedBy, ActorKind)
    SELECT i.ID, i.ShopID, d.State, i.State,
           NULLIF(LTRIM(RTRIM(ISNULL(i.RemovalNote,''))), ''),
           philmart.CurrentActorID(),
           philmart.CurrentActorKind()
    FROM inserted AS i
    JOIN deleted  AS d ON d.ID = i.ID
    WHERE i.State <> d.State;
END;
GO

CREATE TRIGGER philmart.TR_item_no_delete
ON philmart.Item_Item
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50029, 'philmart.item is never deleted. Item history survives every terminal state.', 1;
END;
GO

/* D062: no List_Listing may permit sale below the Seller Minimum Price. Set-based. */
CREATE TRIGGER philmart.TR_listing_seller_minimum_price
ON philmart.List_Listing
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN philmart.Item_Item AS it ON it.ID = i.ItemID
        WHERE it.SellerMinimumPriceMinor IS NOT NULL
          AND ((i.ListingType = 'fixed_price'
                AND i.PriceMinor IS NOT NULL
                AND i.PriceMinor < it.SellerMinimumPriceMinor)
            OR (i.ListingType = 'auction'
                AND ISNULL(i.ReservePriceMinor, i.StartingPriceMinor)
                    < it.SellerMinimumPriceMinor)))
    BEGIN
        THROW 50030, 'Price or effective auction minimum is below the Seller Minimum Price for this Item_Item (D062). Seller Minimum Price is the minimum GROSS selling price before Shop commission.', 1;
    END
END;
GO

/* --------------------------------------- automatic Shop_Shop activation --------
   D005: when every mandatory setup section is complete and valid, the Shop
   activates AUTOMATICALLY. There is no second PHILMART approval step.        */
CREATE TRIGGER philmart.TR_shop_setup_auto_activation
ON philmart.Shop_SetupProgress
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ready TABLE (ShopID UNIQUEIDENTIFIER PRIMARY KEY);

    INSERT INTO @ready (ShopID)
    SELECT DISTINCT s.ID
    FROM philmart.Shop_Shop AS s
    JOIN inserted AS i ON i.ShopID = s.ID
    WHERE s.Status = 'setup_access_granted'
      AND NOT EXISTS (
          SELECT 1
          FROM philmart.Shop_SetupSection AS sec
          LEFT JOIN philmart.Shop_SetupProgress AS p
                 ON p.SectionCode = sec.Code AND p.ShopID = s.ID
          WHERE sec.Mandatory = 1 AND ISNULL(p.IsValid, 0) = 0);

    IF NOT EXISTS (SELECT 1 FROM @ready) RETURN;

    UPDATE s
       SET Status = 'active',
           ActivatedAt = philmart.ServerNow(),
           UpdatedAt = philmart.ServerNow()
    FROM philmart.Shop_Shop AS s JOIN @ready AS r ON r.ShopID = s.ID;

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    SELECT philmart.CurrentActorID(), 'system', r.ShopID, 'Shop_Shop',
           CAST(r.ShopID AS VARCHAR(80)), 'Shop_Shop.activated_automatically',
           N'{"trigger":"valid_setup_completion","decision":"D005"}'
    FROM @ready AS r;
    /* EML-022 Shop Activated is queued by the application on this audit event. */
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D003/D005. Activation is automatic on valid setup completion, and EML-022 Shop Activated triggers HERE — not on application approval (D001, D003). EML-023 is retired and must not be sent (D004).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_SetupProgress',
 @level2type=N'TRIGGER',@level2name=N'TR_shop_setup_auto_activation';
GO

/* ----------------------------------------------- auction List_Bid placement ----
   Must be called inside a SERIALIZABLE transaction. Agreement clause 9.2:
   concurrent requests must not silently overwrite or invalidate one another.
   The caller retries on error 1205 (deadlock victim).                        */
CREATE PROCEDURE philmart.P_List_Bid_Place
    @listingId      UNIQUEIDENTIFIER,
    @buyerId        UNIQUEIDENTIFIER,
    @amountMinor    BIGINT,
    @idempotencyKey VARCHAR(80),
    @bidId          UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();
    DECLARE @shopId UNIQUEIDENTIFIER, @type VARCHAR(20), @state VARCHAR(20),
            @startsAt DATETIMEOFFSET(7), @endsAt DATETIMEOFFSET(7),
            @startPrice BIGINT, @increment BIGINT,
            @soft INT, @softExt INT, @reference VARCHAR(40);

    /* Lock the List_Listing row for the duration of the decision. */
    SELECT @shopId = ShopID, @type = ListingType, @state = State,
           @startsAt = StartsAt, @endsAt = EndsAt,
           @startPrice = StartingPriceMinor, @increment = BidIncrementMinor,
           @soft = SoftCloseSeconds, @softExt = SoftCloseExtensionSeconds,
           @reference = Reference
    FROM philmart.List_Listing WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @listingId;

    IF @shopId IS NULL THROW 50031, 'Listing not found.', 1;

    /* Idempotent replay returns the original List_Bid rather than creating a second. */
    SELECT @bidId = ID FROM philmart.List_Bid
    WHERE ListingID = @listingId AND IdempotencyKey = @idempotencyKey;
    IF @bidId IS NOT NULL RETURN 0;

    IF @type <> 'auction' THROW 50032, 'Listing is not an auction.', 1;
    IF @state <> 'live' OR @now < @startsAt
        THROW 50033, 'Auction is not open for bidding.', 1;
    IF @now >= @endsAt THROW 50034, 'Auction has closed.', 1;

    /* D044/D045: restriction is enforced HERE, server-side, at the commitment
       point. A hidden button is not enforcement.                            */
    IF philmart.BuyerIsRestricted(@buyerId, @shopId) = 1
        THROW 50035, 'Buyer is restricted from bidding with this Shop (D044).', 1;

    DECLARE @currentHigh BIGINT, @nextSeq BIGINT;
    SELECT @currentHigh = ISNULL(MAX(AmountMinor), 0),
           @nextSeq     = ISNULL(MAX(SequenceNo), 0)
    FROM philmart.List_Bid WHERE ListingID = @listingId;

    IF @amountMinor < CASE WHEN @startPrice > @currentHigh + ISNULL(@increment, 1)
                            THEN @startPrice ELSE @currentHigh + ISNULL(@increment, 1) END
        THROW 50036, 'Bid does not meet the minimum next List_Bid.', 1;

    SET @nextSeq = @nextSeq + 1;
    SET @bidId = NEWID();

    INSERT INTO philmart.List_Bid
        (ID, ListingID, ShopID, BuyerID, AmountMinor, PlacedAt, SequenceNo, IdempotencyKey)
    VALUES (@bidId, @listingId, @shopId, @buyerId, @amountMinor, @now, @nextSeq, @idempotencyKey);

    /* D064 soft close: a qualifying late List_Bid extends the close, computed
       server-side against authoritative time.                              */
    DECLARE @extended BIT = 0;
    IF @soft IS NOT NULL AND DATEDIFF(SECOND, @now, @endsAt) <= @soft
    BEGIN
        UPDATE philmart.List_Listing
           SET EndsAt = DATEADD(SECOND, ISNULL(@softExt, @soft), @now),
               ExtensionCount = ExtensionCount + 1,
               OriginalEndsAt = ISNULL(OriginalEndsAt, @endsAt)
        WHERE ID = @listingId;

        UPDATE philmart.List_Bid SET TriggeredExtension = 1 WHERE ID = @bidId;
        SET @extended = 1;
    END

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    VALUES (@buyerId, 'Buy_Buyer', @shopId, 'List_Bid', CAST(@bidId AS VARCHAR(80)), 'List_Bid.placed',
            (SELECT @amountMinor AS AmountMinor, @nextSeq AS SequenceNo,
                    @extended AS extended_close FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Agreement clause 9.2. MUST be called in a SERIALIZABLE transaction; the caller retries on error 1205 (deadlock victim). Covers simultaneous bids (UPDLOCK/HOLDLOCK plus SequenceNo), duplicate submission (idempotency_key), authoritative ordering, last-second bids and soft-close extension. Never trust a client timestamp.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_List_Bid_Place';
GO

/* --------------------------------------------------- auction close --------
   Idempotent: safe to re-run after an outage (clause 9.2 recovery). */
CREATE PROCEDURE philmart.P_List_Auction_Close
    @listingId UNIQUEIDENTIFIER,
    @outcome    VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();
    DECLARE @state VARCHAR(20), @endsAt DATETIMEOFFSET(7),
            @reserve BIGINT, @itemId UNIQUEIDENTIFIER;

    SELECT @state = State, @endsAt = EndsAt,
           @reserve = ReservePriceMinor, @itemId = ItemID
    FROM philmart.List_Listing WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @listingId;

    IF @state IS NULL THROW 50037, 'Listing not found.', 1;

    IF @state <> 'live' BEGIN SET @outcome = 'already_closed'; RETURN 0; END
    IF @now < @endsAt  BEGIN SET @outcome = 'not_due';        RETURN 0; END

    DECLARE @winId UNIQUEIDENTIFIER, @winAmount BIGINT;
    SELECT TOP (1) @winId = ID, @winAmount = AmountMinor
    FROM philmart.List_Bid
    WHERE ListingID = @listingId
      AND (@reserve IS NULL OR AmountMinor >= @reserve)
    ORDER BY AmountMinor DESC, SequenceNo ASC;   -- SequenceNo breaks the tie

    IF @winId IS NOT NULL
    BEGIN
        UPDATE philmart.List_Bid SET IsWinning = 1 WHERE ID = @winId;
        UPDATE philmart.List_Listing
           SET State = 'sold', ClosedAt = @now,
               WinningBidID = @winId, SoldPriceMinor = @winAmount
        WHERE ID = @listingId;
        /* D017: sold/Sale_Fulfilment-pending, not complete. EML-012 Auction Won (D056). */
        UPDATE philmart.Item_Item SET State = 'sold_fulfilment_pending' WHERE ID = @itemId;
        SET @outcome = 'sold';
    END
    ELSE
    BEGIN
        /* D012: unsold Listing stays historical and read-only; the underlying
           Item AUTOMATICALLY returns to Ready to List. No reopen, no reoffer. */
        UPDATE philmart.List_Listing SET State = 'unsold', ClosedAt = @now WHERE ID = @listingId;
        UPDATE philmart.Item_Item SET State = 'ready_to_list' WHERE ID = @itemId;
        SET @outcome = 'unsold';
    END
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D012/D064. Idempotent by design: returns already_closed rather than raising, so multiple simultaneous closings and post-outage recovery converge on one outcome. EML-014 Seller Auction Result is RETIRED and must not be sent (D056).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_List_Auction_Close';
GO

/* ------------------------------------------- financial trigger firing -----
   D023. The single place proceeds and fees are created. Both Sale_Fulfilment paths
   call this one procedure (NF-06) so they cannot drift apart.               */
CREATE PROCEDURE philmart.P_Sale_Fulfilment_FireFinancialTrigger
    @fulfilmentId UNIQUEIDENTIFIER,
    @fired         BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @fired = 0;

    DECLARE @shopId UNIQUEIDENTIFIER, @saleId UNIQUEIDENTIFIER,
            @kind VARCHAR(20), @triggerAt DATETIMEOFFSET(7),
            @dispatched DATETIMEOFFSET(7), @ready DATETIMEOFFSET(7);

    SELECT @shopId = ShopID, @saleId = SaleTransactionID, @kind = MethodKind,
           @triggerAt = FinancialTriggerAt,
           @dispatched = DispatchedAt, @ready = ReadyForCollectionAt
    FROM philmart.Sale_Fulfilment WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @fulfilmentId;

    IF @shopId IS NULL THROW 50038, 'Fulfilment not found.', 1;
    IF @triggerAt IS NOT NULL RETURN 0;          -- already fired; idempotent

    DECLARE @invoiceId UNIQUEIDENTIFIER =
        (SELECT TOP (1) InvoiceID FROM philmart.Sale_InvoiceLine WHERE SaleTransactionID = @saleId);

    /* D020: full Sale_Payment of the relevant Sale_Invoice is required. */
    IF @invoiceId IS NULL OR philmart.InvoiceIsFullyPaid(@invoiceId) = 0
        THROW 50039, 'Financial trigger refused: the relevant Sale_Invoice is not fully paid (D020). Dispatch and Ready for Collection require full Sale_Payment.', 1;

    /* D023: the Sale_Fulfilment event must have happened on the matching path. */
    IF NOT ((@kind = 'shipping'   AND @dispatched IS NOT NULL)
         OR (@kind = 'collection' AND @ready IS NOT NULL))
        THROW 50040, 'Financial trigger refused: shipping requires Dispatch, collection requires Ready for Collection (D023). Actual collection does not count.', 1;

    UPDATE philmart.Sale_Fulfilment
       SET FinancialTriggerAt = philmart.ServerNow(),
           FinancialTriggerEvent = CASE WHEN @kind = 'shipping'
                                          THEN 'dispatch' ELSE 'ready_for_collection' END
    WHERE ID = @fulfilmentId;

    DECLARE @itemId UNIQUEIDENTIFIER, @price BIGINT, @consigned BIT, @sellerId UNIQUEIDENTIFIER;
    SELECT @itemId = st.ItemID, @price = st.SalePriceMinor,
           @consigned = it.IsConsigned, @sellerId = it.SellerID
    FROM philmart.Sale_Transaction AS st
    JOIN philmart.Item_Item AS it ON it.ID = st.ItemID
    WHERE st.ID = @saleId;

    /* D025: Seller proceeds post here (consigned stock only). */
    IF @consigned = 1
    BEGIN
        DECLARE @pct DECIMAL(9,6) =
            ISNULL((SELECT DefaultCommissionPct FROM philmart.Shop_Settings WHERE ShopID = @shopId), 0);
        DECLARE @commission BIGINT = CAST(ROUND(@price * @pct / 100.0, 0) AS BIGINT);

        INSERT INTO philmart.Sell_ProceedsEntry
            (SellerID, ShopID, ItemID, SaleTransactionID, FulfilmentID,
             EntryKind, Direction, GrossAmountMinor, CommissionMinor,
             NetAmountMinor, CommissionPct)
        VALUES (@sellerId, @shopId, @itemId, @saleId, @fulfilmentId,
                'proceeds', 'credit', @price, @commission, @price - @commission, @pct);
    END

    /* D028: PHILMART transaction fee accrues on the same trigger. */
    DECLARE @feePct DECIMAL(9,6) =
        (SELECT TransactionFeePct FROM philmart.Fee_ShopConfig
         WHERE ShopID = @shopId AND EffectiveTo IS NULL);

    IF @feePct IS NOT NULL
    BEGIN
        DECLARE @today DATE = CAST(philmart.ServerNow() AS DATE);
        INSERT INTO philmart.Fee_Accrual
            (ShopID, SaleTransactionID, FulfilmentID, BaseAmountMinor,
             FeePct, FeeAmountMinor, AccrualPeriod)
        VALUES (@shopId, @saleId, @fulfilmentId, @price, @feePct,
                CAST(ROUND(@price * @feePct / 100.0, 0) AS BIGINT),
                DATEFROMPARTS(YEAR(@today), MONTH(@today), 1));
    END

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    VALUES (philmart.CurrentActorID(), philmart.CurrentActorKind(), @shopId,
            'Sale_Fulfilment', CAST(@fulfilmentId AS VARCHAR(80)),
            'Sale_Fulfilment.financial_trigger_fired',
            N'{"path":"' + @kind + N'","decision":"D023"}');

    SET @fired = 1;
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D020/D023/D025/D028. THE single implementation of the financial trigger. Both Sale_Fulfilment paths call it, so they cannot diverge (NF-06, RK-08). It is idempotent — a second call returns fired = 0 rather than double-posting — and the filtered unique indexes on Sell_ProceedsEntry(FulfilmentID) and Fee_Accrual(FulfilmentID) make double-posting impossible even under a race.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_Sale_Fulfilment_FireFinancialTrigger';
GO

/* ------------------------------------------------ Sale_Payment allocation ------
   D021: specific reference first; otherwise oldest outstanding first.       */
CREATE PROCEDURE philmart.P_Sale_Payment_Allocate
    @paymentId UNIQUEIDENTIFIER,
    @residual   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @shopId UNIQUEIDENTIFIER, @accountId UNIQUEIDENTIFIER,
            @amount BIGINT, @specific UNIQUEIDENTIFIER;

    SELECT @shopId = ShopID, @accountId = BuyerAccountID,
           @amount = AmountMinor, @specific = SpecificInvoiceID
    FROM philmart.Sale_Payment WHERE ID = @paymentId;

    IF @shopId IS NULL THROW 50041, 'Payment not found.', 1;

    SET @residual = @amount - ISNULL(
        (SELECT SUM(AmountMinor) FROM philmart.Sale_PaymentAllocation WHERE PaymentID = @paymentId), 0);
    IF @residual <= 0 RETURN 0;

    DECLARE @take BIGINT, @outstanding BIGINT;

    /* Specific reference wins outright (D021). */
    IF @specific IS NOT NULL
    BEGIN
        SET @outstanding = (SELECT TotalMinor - philmart.InvoicePaidMinor(ID)
                            FROM philmart.Sale_Invoice WHERE ID = @specific);
        SET @take = CASE WHEN @residual < @outstanding THEN @residual ELSE @outstanding END;
        IF @take > 0
        BEGIN
            INSERT INTO philmart.Sale_PaymentAllocation
                (PaymentID, InvoiceID, ShopID, BuyerAccountID, AmountMinor, AllocationRule)
            VALUES (@paymentId, @specific, @shopId, @accountId, @take, 'specific_reference');
            SET @residual = @residual - @take;
        END
    END

    /* Then oldest outstanding first, then next-oldest, until exhausted (D021).
       Deterministic tie-break on id so equal issue times cannot reorder.     */
    DECLARE @invId UNIQUEIDENTIFIER;
    DECLARE inv_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.ID, i.TotalMinor - philmart.InvoicePaidMinor(i.ID)
        FROM philmart.Sale_Invoice AS i
        WHERE i.BuyerAccountID = @accountId
          AND i.State = 'issued'
          AND i.TotalMinor > philmart.InvoicePaidMinor(i.ID)
        ORDER BY i.IssuedAt ASC, i.ID ASC;

    OPEN inv_cur;
    FETCH NEXT FROM inv_cur INTO @invId, @outstanding;
    WHILE @@FETCH_STATUS = 0 AND @residual > 0
    BEGIN
        SET @take = CASE WHEN @residual < @outstanding THEN @residual ELSE @outstanding END;
        INSERT INTO philmart.Sale_PaymentAllocation
            (PaymentID, InvoiceID, ShopID, BuyerAccountID, AmountMinor, AllocationRule)
        VALUES (@paymentId, @invId, @shopId, @accountId, @take, 'oldest_outstanding');
        SET @residual = @residual - @take;
        FETCH NEXT FROM inv_cur INTO @invId, @outstanding;
    END
    CLOSE inv_cur; DEALLOCATE inv_cur;

    /* D021: residual credit exists ONLY after all outstanding invoices settle. */
    IF @residual > 0
    BEGIN
        INSERT INTO philmart.Buy_AccountEntry
            (BuyerAccountID, ShopID, EntryKind, Direction, AmountMinor, PaymentID, Description)
        VALUES (@accountId, @shopId, 'credit_note', 'credit', @residual, @paymentId,
                N'Residual credit after all outstanding invoices settled');
    END
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D021/D022. Ordering: specific reference, then oldest outstanding first, then next-oldest until exhausted. Residual credit only after ALL outstanding invoices are settled. Credit is written to the Shop-scoped Buy_Buyer account and can never cross Shops (clause 9.3).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_Sale_Payment_Allocate';
GO

/* ------------------------------------------------------- catalogue search --
   SQL Server Full-Text Search replaces the Postgres tsvector/trigram pair.
   Requires the Full-Text Search feature to be installed on the instance; on
   Azure SQL Database it is available by default.

   Guarded, with the DDL deferred through EXEC, because CREATE FULLTEXT CATALOG
   and CREATE FULLTEXT INDEX raise error 7609 on an instance without the
   feature at the point the batch is normalised - even inside an IF branch that
   is never taken. Unguarded, that error aborts everything after it, which on
   the single-file deploy takes the reference seed down with it. Catalogue
   search is then unavailable until the feature is installed and this block is
   re-run; nothing else in the schema depends on it.                         */
IF SERVERPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'philmart_ft')
        EXEC(N'CREATE FULLTEXT CATALOG philmart_ft AS DEFAULT;');

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes
                    WHERE object_id = OBJECT_ID('philmart.Item_Item'))
        EXEC(N'CREATE FULLTEXT INDEX ON philmart.Item_Item
                   (Title LANGUAGE 1033, Description LANGUAGE 1033)
               KEY INDEX PK_item ON philmart_ft
               WITH CHANGE_TRACKING AUTO;');
END
ELSE
    PRINT 'WARNING: Full-Text Search is not installed on this instance. The philmart_ft catalogue and the Item_Item full-text index were SKIPPED. Item catalogue search will not work until the feature is installed and this block is re-run.';
GO
