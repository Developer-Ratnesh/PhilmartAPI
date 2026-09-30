namespace Philmart.Application.Admin;

public class AdminDashboardDTO
{
    // server time the figures were read at, not the browser's
    public DateTimeOffset AsAt
    {
        get; set;
    }

    public int ApplicationsAwaitingReview
    {
        get; set;
    }
    public int ShopsInSetup
    {
        get; set;
    }
    public int ActiveShops
    {
        get; set;
    }
    public int DeactivatedShops
    {
        get; set;
    }

    public int LiveFixedPriceListings
    {
        get; set;
    }
    public int LiveAuctions
    {
        get; set;
    }

    // these run to their scheduled end even if the Shop is deactivated, D033
    public int LiveAuctionsWithBids
    {
        get; set;
    }

    public int ItemsReadyToList
    {
        get; set;
    }

    // past the 75 day escalation point, D061
    public int ItemsPastReadyToListEscalation
    {
        get; set;
    }

    public long FeesOutstandingMinor
    {
        get; set;
    }
    public long FeesOverdueMinor
    {
        get; set;
    }

    // arrears never deactivate a Shop by themselves, D031
    public int ShopsWithOverdueFees
    {
        get; set;
    }
}

public class AdminShopDTO
{
    public Guid ID
    {
        get; set;
    }
    public string Reference
    {
        get; set;
    } = string.Empty;
    public string TradingName
    {
        get; set;
    } = string.Empty;
    public string? LegalEntityName
    {
        get; set;
    }
    public string Status
    {
        get; set;
    } = string.Empty;

    // activation history
    public DateTimeOffset CreatedAt
    {
        get; set;
    }
    public DateTimeOffset? SetupAccessGrantedAt
    {
        get; set;
    }
    public DateTimeOffset? ActivatedAt
    {
        get; set;
    }
    public DateTimeOffset? DeactivatedAt
    {
        get; set;
    }
    public string? DeactivationReason
    {
        get; set;
    }
    public DateTimeOffset? ReactivatedAt
    {
        get; set;
    }

    public int LiveListingCount
    {
        get; set;
    }

    // fee standing
    public long FeesOutstandingMinor
    {
        get; set;
    }
    public long FeesOverdueMinor
    {
        get; set;
    }
    public bool HasOverdueFees
    {
        get; set;
    }
}

public class AdminShopFilter
{
    // trading name, legal name or reference
    public string? Query
    {
        get; set;
    }

    public string? Status
    {
        get; set;
    }

    // only Shops with an overdue fee invoice
    public bool OverdueOnly
    {
        get; set;
    }
}
