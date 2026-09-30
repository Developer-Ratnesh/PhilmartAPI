namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ListListing
{
    public Guid ID { get; set; }

    public Guid ShopID { get; set; }

    public Guid ItemID { get; set; }

    public string ListingType { get; set; } = null!;

    public string State { get; set; } = null!;

    public string Reference { get; set; } = null!;

    public long? PriceMinor { get; set; }

    public DateTimeOffset? ListedAt { get; set; }

    public DateTimeOffset? ExpiresAt { get; set; }   // 90 days max, D063

    public Guid? AuctionEventID { get; set; }

    public long? StartingPriceMinor { get; set; }

    public long? ReservePriceMinor { get; set; }

    public long? BidIncrementMinor { get; set; }

    public DateTimeOffset? StartsAt { get; set; }

    public DateTimeOffset? EndsAt { get; set; }   // moves when a soft close extends it

    public DateTimeOffset? OriginalEndsAt { get; set; }

    public int? SoftCloseSeconds { get; set; }

    public int? SoftCloseExtensionSeconds { get; set; }

    public int ExtensionCount { get; set; }

    public DateTimeOffset? ClosedAt { get; set; }

    public Guid? WinningBidID { get; set; }

    public long? SoldPriceMinor { get; set; }

    public string? CancellationReason { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public virtual ItemItem Item { get; set; } = null!;

    public virtual ShopShop Shop { get; set; } = null!;

    public virtual ICollection<ListBid> ListBids { get; set; } = new List<ListBid>();
}
