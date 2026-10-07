namespace Philmart.Application.Auctions;

public class CreateAuctionRequest
{
    public Guid ItemID { get; set; }

    public long StartingPriceMinor { get; set; }

    public long? ReservePriceMinor { get; set; }

    public long BidIncrementMinor { get; set; }

    public DateTimeOffset StartsAt { get; set; }

    public DateTimeOffset EndsAt { get; set; }

    // optional. Without it there's no soft close.
    public int? SoftCloseSeconds { get; set; }

    public int? SoftCloseExtensionSeconds { get; set; }
}

public class CancelAuctionRequest
{
    public string Reason { get; set; } = string.Empty;

    // D016: the usual exceptional case. Moves the Item to Missing/Damaged
    // instead of back to Ready to List.
    public bool ItemMissingOrDamaged { get; set; }
}

public class ShopAuctionDTO
{
    public Guid ListingID { get; set; }

    public Guid ItemID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string State { get; set; } = string.Empty;

    public long StartingPriceMinor { get; set; }

    public long? ReservePriceMinor { get; set; }

    public long? CurrentBidMinor { get; set; }

    public int BidCount { get; set; }

    public DateTimeOffset StartsAt { get; set; }

    public DateTimeOffset EndsAt { get; set; }

    public int ExtensionCount { get; set; }

    public long? SoldPriceMinor { get; set; }

    public string? CancellationReason { get; set; }
}

public class ReadyItemDTO
{
    public Guid ItemID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public long? SellerMinimumPriceMinor { get; set; }
}

public class AuctionSweepResult
{
    public int Opened { get; set; }

    public int Sold { get; set; }

    public int Unsold { get; set; }
}
