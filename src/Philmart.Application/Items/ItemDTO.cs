namespace Philmart.Application.Items;

public class ItemDTO
{
    public Guid ID
    {
        get; set;
    }
    public Guid ShopID
    {
        get; set;
    }
    public string Reference
    {
        get; set;
    } = string.Empty;
    public string Title
    {
        get; set;
    } = string.Empty;
    public string? Description
    {
        get; set;
    }
    public string State
    {
        get; set;
    } = string.Empty;

    public DateTimeOffset? ReadyToListSince
    {
        get; set;
    }

    public int? DaysReadyToList
    {
        get; set;
    }

    public bool IsConsigned
    {
        get; set;
    }
    public Guid? SellerID
    {
        get; set;
    }

    // gross, before shop commission. never sell below this
    public long? SellerMinimumPriceMinor
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
    public DateTimeOffset CreatedAt
    {
        get; set;
    }
}

public class ItemTransitionRequest
{
    public string ToState
    {
        get; set;
    } = string.Empty;

    public string? Reason
    {
        get; set;
    }

    public string? RemovalReason
    {
        get; set;
    }
}

public class ItemTransitionOption
{
    public string ToState
    {
        get; set;
    } = string.Empty;

    public string Label
    {
        get; set;
    } = string.Empty;

    public bool RequiresReason
    {
        get; set;
    }

    public string DecisionRef
    {
        get; set;
    } = string.Empty;
}

public class ItemSearchRequest
{
    public string? Query
    {
        get; set;
    }
    public string? State
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
    public Guid? ThemeID
    {
        get; set;
    }
    public Guid? SellerID
    {
        get; set;
    }
    public Common.PageRequest? Page
    {
        get; set;
    }
}
