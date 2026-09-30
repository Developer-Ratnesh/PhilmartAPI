namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ListBid
{
    public Guid ID { get; set; }

    public Guid ListingID { get; set; }

    public Guid ShopID { get; set; }

    public Guid BuyerID { get; set; }

    public long AmountMinor { get; set; }

    public DateTimeOffset PlacedAt { get; set; }

    public long SequenceNo { get; set; }   // order bids by this, timestamps tie

    public string IdempotencyKey { get; set; } = null!;

    public bool IsWinning { get; set; }

    public bool TriggeredExtension { get; set; }

    public string? IpAddress { get; set; }

    public virtual ListListing Listing { get; set; } = null!;
}
