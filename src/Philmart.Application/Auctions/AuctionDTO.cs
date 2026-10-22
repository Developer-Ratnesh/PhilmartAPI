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

    // the bid count on the confirmation the user saw. If a bid came in since,
    // the cancellation is refused (409) instead of quietly becoming the
    // exceptional with-bids route they never confirmed.
    public int? ExpectedBidCount { get; set; }
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

// SCR-SHP-006.1 Auction Management: one auction with its bids and activity.
// The figures come from the same rows as the list and the public item page,
// so every view agrees (V49-AUC-08).
public class AuctionManagementDTO
{
    public Guid ListingID { get; set; }

    public Guid ItemID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string ItemReference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string ItemState { get; set; } = string.Empty;

    public string? SellerName { get; set; }

    public string State { get; set; } = string.Empty;

    public long StartingPriceMinor { get; set; }

    public long? ReservePriceMinor { get; set; }

    public long BidIncrementMinor { get; set; }

    public long? CurrentBidMinor { get; set; }

    public int BidCount { get; set; }

    public DateTimeOffset StartsAt { get; set; }

    public DateTimeOffset EndsAt { get; set; }

    public int ExtensionCount { get; set; }

    public long? SoldPriceMinor { get; set; }

    public string? CancellationReason { get; set; }

    public DateTimeOffset? ClosedAt { get; set; }

    public DateTimeOffset ServerNow { get; set; }

    public List<AuctionBidDTO> Bids { get; set; } = new List<AuctionBidDTO>();

    public List<AuctionActivityDTO> Activity { get; set; } = new List<AuctionActivityDTO>();
}

// Bidders are numbered in the order they first bid. Who they are isn't shown
// here; the Shop sees the winner when it invoices (BR-15).
public class AuctionBidDTO
{
    public long SequenceNo { get; set; }

    public int Rank { get; set; }

    public string Bidder { get; set; } = string.Empty;

    public long AmountMinor { get; set; }

    public DateTimeOffset PlacedAt { get; set; }

    public bool Leading { get; set; }

    public bool Winning { get; set; }

    public bool ExtendedClose { get; set; }
}

public class AuctionActivityDTO
{
    public DateTimeOffset At { get; set; }

    public string Action { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public string? Reason { get; set; }
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
