namespace Philmart.Application.Account;

// one row on Saved Items (SCR-PUB-009) or Recently Viewed (SCR-PUB-008)
public class BuyerListItemDTO
{
    public Guid ListingID { get; set; }

    public string? ItemNumber { get; set; }

    public string? Title { get; set; }

    public string? ListingType { get; set; }

    public Guid? ShopID { get; set; }

    public string? ShopName { get; set; }

    public long? PriceMinor { get; set; }

    public long? CurrentBidMinor { get; set; }

    public string? PrimaryImageUrl { get; set; }

    // available, auction_open, auction_closed, sold or unavailable
    public string Status { get; set; } = string.Empty;

    // saved date on Saved Items, last viewed on Recently Viewed
    public DateTimeOffset At { get; set; }
}

public class SavedStateDTO
{
    public bool Saved { get; set; }
}
