namespace Philmart.Application.Marketplace;

public class MarketplaceItemDTO
{
    public Guid ListingID { get; set; }

    public Guid ItemID { get; set; }

    public string Title { get; set; } = string.Empty;

    public string ListingType { get; set; } = string.Empty;

    public Guid ShopID { get; set; }

    public string ShopName { get; set; } = string.Empty;

    public string? AreaCountry { get; set; }

    public string? Type { get; set; }

    public string? Theme { get; set; }

    public long? PriceMinor { get; set; }

    // auctions only
    public long? CurrentBidMinor { get; set; }

    public DateTimeOffset? EndsAt { get; set; }

    public int BidCount { get; set; }

    public string? PrimaryImageUrl { get; set; }

    public int ImageCount { get; set; }

    public DateTimeOffset ListedAt { get; set; }
}

public class MarketplaceFilter
{
    public string? Query { get; set; }

    public string? SellingMethod { get; set; }

    public Guid? AreaCountryID { get; set; }

    public Guid? TypeID { get; set; }

    public Guid? SubtypeID { get; set; }

    public Guid? FormatID { get; set; }

    public Guid? StampStateID { get; set; }

    public Guid? ThemeID { get; set; }

    public Guid? ShopID { get; set; }

    public string Sort { get; set; } = "newest";
}

public class ClassificationOptionDTO
{
    public Guid ID { get; set; }

    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public int SortOrder { get; set; }
}

// Item detail, SCR-PUB-003A (Buy Now) and SCR-PUB-003B (auction)
public class ListingDetailDTO
{
    public Guid ListingID { get; set; }

    public Guid ItemID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string? Description { get; set; }

    public string ListingType { get; set; } = string.Empty;

    public string State { get; set; } = string.Empty;

    public string? AreaCountry { get; set; }

    public string? Type { get; set; }

    public string? Subtype { get; set; }

    public string? Theme { get; set; }

    public string? Condition { get; set; }

    public string? CatalogueReference { get; set; }

    public List<string> Images { get; set; } = new List<string>();

    public Guid ShopID { get; set; }

    public string ShopName { get; set; } = string.Empty;

    public string ShopReference { get; set; } = string.Empty;

    // D032: a deactivated Shop's listings don't offer Buy Now or bidding
    public bool ShopActive { get; set; }

    public long? PriceMinor { get; set; }

    public long? StartingPriceMinor { get; set; }

    public long? BidIncrementMinor { get; set; }

    public long? CurrentBidMinor { get; set; }

    // same sum P_List_Bid_Place checks, so the page and the database agree
    public long? NextMinimumBidMinor { get; set; }

    public bool ReserveMet { get; set; }

    public DateTimeOffset? StartsAt { get; set; }

    public DateTimeOffset? EndsAt { get; set; }

    public int? SoftCloseSeconds { get; set; }

    public int ExtensionCount { get; set; }

    // server time when this was read, so the countdown doesn't trust the device clock
    public DateTimeOffset ServerNow { get; set; }

    public List<BidHistoryDTO> Bids { get; set; } = new List<BidHistoryDTO>();

    public List<Philmart.Application.Registration.DeliveryOptionDTO> DeliveryOptions { get; set; } = new List<Philmart.Application.Registration.DeliveryOptionDTO>();

    // BR-03-R02: Buy Now Commitment or Auction Bid Commitment, as published now
    public Philmart.Application.Registration.LegalDocumentDTO? Commitment { get; set; }
}

// no buyer identity, ever
public class BidHistoryDTO
{
    public long SequenceNo { get; set; }

    public long AmountMinor { get; set; }

    public DateTimeOffset PlacedAt { get; set; }
}

public class ShopProfileDTO
{
    public Guid ShopID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string? Blurb { get; set; }

    public bool Active { get; set; }
}
