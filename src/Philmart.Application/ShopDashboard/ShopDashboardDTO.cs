namespace Philmart.Application.ShopDashboard;

// SCR-SHP-002, the first screen after a Shop user signs in. Only the parts
// that are built so far. A figure the user has no permission for is null and
// the screen leaves its card out.
public class ShopDashboardDTO
{
    public DateTimeOffset AsAt { get; set; }

    public string ShopName { get; set; } = string.Empty;

    // item.view
    public int? ReadyToList { get; set; }

    // listing.view or auction.manage
    public int? ActiveFixedPrice { get; set; }

    public int? ActiveAuctions { get; set; }

    public int? ScheduledAuctions { get; set; }

    // report.view, calendar year in SA time
    public int? ItemsSoldThisYear { get; set; }

    public long? SalesValueThisYearMinor { get; set; }

    // shop.users.view
    public int? ActiveUsers { get; set; }

    public int? PendingInvitations { get; set; }

    // live and scheduled auctions, soonest first (listing.view or auction.manage)
    public List<DashboardAuctionDTO>? Auctions { get; set; }
}

public class DashboardAuctionDTO
{
    public Guid ListingID { get; set; }

    public string Reference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    // live or scheduled
    public string State { get; set; } = string.Empty;

    public DateTimeOffset? StartsAt { get; set; }

    public DateTimeOffset? EndsAt { get; set; }

    public int BidCount { get; set; }

    public long? CurrentBidMinor { get; set; }
}
