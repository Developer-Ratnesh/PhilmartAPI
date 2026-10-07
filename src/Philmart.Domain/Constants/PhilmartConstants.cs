namespace Philmart.Domain.Constants;

// Values from the decision register, stored as text with a CHECK constraint.
// If you add one here, add it to the CHECK and to Sys_EnumValue too.
public static class PhilmartConstants
{
    public static class ItemState
    {
        public const string ReadyToList = "ready_to_list";
        public const string Listed = "listed";
        public const string SoldFulfilmentPending = "sold_fulfilment_pending";
        public const string Complete = "complete";
        public const string RemovedFromStock = "removed_from_stock";
        public const string MissingDamaged = "missing_damaged";   // D016, a state not a flag
        public const string ReturnedToSeller = "returned_to_seller";
        public const string WrittenOff = "written_off";
    }

    public static class ListingState
    {
        public const string Draft = "draft";
        public const string Scheduled = "scheduled";
        public const string Live = "live";
        public const string Sold = "sold";
        public const string Unsold = "unsold";
        public const string Withdrawn = "withdrawn";
        public const string Expired = "expired";
        public const string Cancelled = "cancelled";

        // once here the listing is finished and can never be reopened
        public static readonly string[] Historical = new[]
        {
            Sold, Unsold, Withdrawn, Expired, Cancelled
        };

        // an item can only have one listing in these states at a time
        public static readonly string[] Active = new[]
        {
            Draft, Scheduled, Live
        };
    }

    public static class ListingType
    {
        public const string FixedPrice = "fixed_price";
        public const string Auction = "auction";
    }

    public static class FulfilmentMethod
    {
        public const string Shipping = "shipping";
        public const string Collection = "collection";
    }

    public static class FulfilmentState
    {
        public const string Pending = "pending";
        public const string Dispatched = "dispatched";
        public const string ReadyForCollection = "ready_for_collection";

        // happens after the money is already earned, don't use it as a trigger
        public const string Collected = "collected";
    }

    public static class QueryStatus
    {
        public const string AwaitingShop = "awaiting_shop";
        public const string AwaitingBuyer = "awaiting_buyer";
        public const string Closed = "closed";
    }

    public static class ShopStatus
    {
        public const string ApplicationSubmitted = "application_submitted";
        public const string ApplicationRejected = "application_rejected";
        public const string SetupAccessGranted = "setup_access_granted";
        public const string Active = "active";
        public const string Deactivated = "deactivated";
    }

    public static class SettlementStatus
    {
        public const string Unpaid = "unpaid";
        public const string PartPaid = "part_paid";
        public const string Paid = "paid";
    }

    // The schema spells these Buy_Buyer and Shop_User, and the CHECK
    // constraints and RLS predicates compare against exactly that. Don't tidy them.
    public static class ActorKind
    {
        public const string Anonymous = "anonymous";
        public const string Buyer = "Buy_Buyer";
        public const string ShopUser = "Shop_User";
        public const string PlatformAdmin = "platform_admin";
        public const string System = "system";
    }

    public static class RestrictionScope
    {
        public const string Shop = "Shop_Shop";   // CK_br_scope
        public const string Platform = "platform";
    }

    public static class RemovalReason
    {
        public const string Damaged = "damaged";
        public const string Lost = "lost";
        public const string SellerRequest = "seller_request";
        public const string Pricing = "pricing";
        public const string Other = "other";    // needs a note, D066
    }

    public static class Thresholds
    {
        public const int FixedPriceMaxLiveDays = 90;        // D063
        public const int QueryAutoCloseDays = 14;           // D069, awaiting buyer only
        public const int ReadyToListAttentionDays = 60;     // D061
        public const int ReadyToListEscalationDays = 75;    // D061
        public const int OutbidAlertCooldownHours = 4;      // D068
        public const int OutbidAlertMaxPer24Hours = 3;      // D068
    }

    public static class Email
    {
        public const string InvoiceIssued = "EML-001";
        public const string PaymentReceivedBalanceOutstanding = "EML-002";
        public const string PaymentReminder = "EML-003";
        public const string ItemDispatched = "EML-004";
        public const string ReadyForCollection = "EML-005";
        public const string BuyerQueryReply = "EML-007";
        public const string SellerStatement = "EML-008";
        public const string SellerPaymentReversed = "EML-010";
        public const string AuctionWon = "EML-012";
        public const string OutbidAlert = "EML-013";
        public const string ExceptionalCancellation = "EML-015";
        public const string CombinedShippingReminder = "EML-016";
        public const string PhilmartFeesDue = "EML-017";
        public const string PhilmartFeesOverdue = "EML-018";
        public const string BuyerEmailVerification = "EML-019";
        public const string BuyerWelcome = "EML-020";
        public const string ShopApplicationReceived = "EML-021";
        public const string ShopActivated = "EML-022";

        // retired or not approved, don't build these
        public static readonly string[] DoNotImplement = new[]
        {
            "EML-006", "EML-009", "EML-011", "EML-014", "EML-023", "EML-024"
        };
    }

    // spelled to match CK_audit_reason_required, or the reason check won't fire
    public static class AuditAction
    {
        public const string AuctionCancelledWithBids = "auction.cancelled_with_bids";
        public const string ItemRemovedFromStockOther = "Item_Item.removed_from_stock.other";
        public const string BuyerRestricted = "Buy_Buyer.restricted";
        public const string ShopDeactivated = "Shop_Shop.deactivated";
        public const string ShopReactivated = "Shop_Shop.reactivated";
        public const string SellerPaymentReversed = "Sell_Payment.reversed";
        public const string SellerProceedsAdjusted = "seller_proceeds.adjusted";
        public const string InvoiceCancelled = "Sale_Invoice.cancelled";
        public const string FeeWaived = "fee.waived";

        // these always need a reason written with them
        public static readonly string[] RequireReason = new[]
        {
            AuctionCancelledWithBids,
            ItemRemovedFromStockOther,
            BuyerRestricted,
            ShopDeactivated,
            ShopReactivated,
            SellerPaymentReversed,
            SellerProceedsAdjusted,
            InvoiceCancelled,
            FeeWaived
        };
    }

    public static class Permission
    {
        public const string ShopSettingsView = "shop.settings.view";
        public const string ShopSettingsManage = "shop.settings.manage";
        public const string ShopUsersView = "shop.users.view";
        public const string ShopUsersManage = "shop.users.manage";
        public const string ItemView = "item.view";
        public const string ItemManage = "item.manage";
        public const string ItemRemove = "item.remove";
        public const string ItemBulkUpload = "item.bulk_upload";
        public const string ListingView = "listing.view";
        public const string ListingManage = "listing.manage";
        public const string AuctionManage = "auction.manage";
        public const string AuctionCancelWithBids = "auction.cancel_with_bids";
        public const string InvoiceView = "invoice.view";
        public const string InvoiceManage = "invoice.manage";
        public const string PaymentRecord = "payment.record";
        public const string PaymentReverse = "payment.reverse";
        public const string FulfilmentManage = "fulfilment.manage";
        public const string SellerView = "seller.view";
        public const string SellerManage = "seller.manage";
        public const string SellerPay = "seller.pay";
        public const string SellerReverse = "seller.reverse";
        public const string QueryView = "query.view";
        public const string QueryRespond = "query.respond";
        public const string BuyerRestrict = "buyer.restrict";
        public const string FeesView = "fees.view";
        public const string ReportView = "report.view";
    }

    public static class SessionContext
    {
        public const string ActorId = "philmart.actor_id";
        public const string ShopId = "philmart.shop_id";
        public const string ActorKind = "philmart.actor_kind";
    }
}
