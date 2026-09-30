namespace Philmart.Application.Marketplace;

public class MarketplaceItemDTO
{
    public Guid ListingID
    {
        get; set;
    }
    public Guid ItemID
    {
        get; set;
    }
    public string Title
    {
        get; set;
    } = string.Empty;

    public string ListingType
    {
        get; set;
    } = string.Empty;

    public Guid ShopID
    {
        get; set;
    }
    public string ShopName
    {
        get; set;
    } = string.Empty;

    public string? AreaCountry
    {
        get; set;
    }
    public string? Type
    {
        get; set;
    }
    public string? Theme
    {
        get; set;
    }

    public long? PriceMinor
    {
        get; set;
    }

    // auctions only
    public long? CurrentBidMinor
    {
        get; set;
    }
    public DateTimeOffset? EndsAt
    {
        get; set;
    }
    public int BidCount
    {
        get; set;
    }

    public string? PrimaryImageUrl
    {
        get; set;
    }
    public int ImageCount
    {
        get; set;
    }
    public DateTimeOffset ListedAt
    {
        get; set;
    }
}

public class MarketplaceFilter
{
    public string? Query
    {
        get; set;
    }

    public string? SellingMethod
    {
        get; set;
    }

    public Guid? AreaCountryID
    {
        get; set;
    }
    public Guid? TypeID
    {
        get; set;
    }
    public Guid? SubtypeID
    {
        get; set;
    }
    public Guid? FormatID
    {
        get; set;
    }
    public Guid? StampStateID
    {
        get; set;
    }
    public Guid? ThemeID
    {
        get; set;
    }
    public Guid? ShopID
    {
        get; set;
    }

    public string Sort
    {
        get; set;
    } = "newest";
}

public class ClassificationOptionDTO
{
    public Guid ID
    {
        get; set;
    }
    public string Code
    {
        get; set;
    } = string.Empty;
    public string Name
    {
        get; set;
    } = string.Empty;
    public int SortOrder
    {
        get; set;
    }
}
