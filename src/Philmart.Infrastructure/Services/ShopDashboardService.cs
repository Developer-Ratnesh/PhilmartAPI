using Microsoft.EntityFrameworkCore;
using Philmart.Application.ShopDashboard;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class ShopDashboardService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IServerClock clock) : IShopDashboardService
{
    private static readonly TimeSpan SouthAfrica = TimeSpan.FromHours(2);

    public async Task<ShopDashboardDTO> Get(CancellationToken cancellationToken = default)
    {
        if (!tenant.IsShopUser || tenant.ShopId == null)
        {
            throw new NotAuthorisedException("Sign in as a Shop user to do this.");
        }

        Guid shopId = tenant.ShopId.Value;
        var now = await clock.Now();
        var local = now.ToOffset(SouthAfrica);
        var yearStart = new DateTimeOffset(local.Year, 1, 1, 0, 0, 0, SouthAfrica);

        bool seesListings = tenant.Has(PhilmartConstants.Permission.ListingView) || tenant.Has(PhilmartConstants.Permission.AuctionManage);

        using (var context = contextFactory.CreateDbContext())
        {
            var dashboard = new ShopDashboardDTO();
            dashboard.AsAt = now;

            // RLS keeps this to the user's own Shop. The ShopID filters say so too.
            dashboard.ShopName = await context.ShopShops
                .Where(x => x.ID == shopId)
                .Select(x => x.TradingName)
                .FirstOrDefaultAsync(cancellationToken) ?? string.Empty;

            var listings = context.ListListings.AsNoTracking().Where(x => x.ShopID == shopId);

            if (tenant.Has(PhilmartConstants.Permission.ItemView))
            {
                dashboard.ReadyToList = await context.ItemItems
                    .CountAsync(x => x.ShopID == shopId && x.State == PhilmartConstants.ItemState.ReadyToList, cancellationToken);
            }

            if (seesListings)
            {
                var live = listings.Where(x => x.State == PhilmartConstants.ListingState.Live);

                dashboard.ActiveFixedPrice = await live.CountAsync(x => x.ListingType == PhilmartConstants.ListingType.FixedPrice, cancellationToken);
                dashboard.ActiveAuctions = await live.CountAsync(x => x.ListingType == PhilmartConstants.ListingType.Auction, cancellationToken);
                dashboard.ScheduledAuctions = await listings.CountAsync(
                    x => x.ListingType == PhilmartConstants.ListingType.Auction && x.State == PhilmartConstants.ListingState.Scheduled, cancellationToken);

                var auctions = await listings
                    .Where(x => x.ListingType == PhilmartConstants.ListingType.Auction
                             && (x.State == PhilmartConstants.ListingState.Live || x.State == PhilmartConstants.ListingState.Scheduled))
                    .OrderBy(x => x.State == PhilmartConstants.ListingState.Live ? 0 : 1)
                    .ThenBy(x => x.EndsAt)
                    .Take(5)
                    .Select(x => new DashboardAuctionDTO
                    {
                        ListingID = x.ID,
                        Reference = x.Reference,
                        Title = x.Item.Title,
                        State = x.State,
                        StartsAt = x.StartsAt,
                        EndsAt = x.EndsAt,
                        BidCount = x.ListBids.Count,
                        CurrentBidMinor = x.ListBids.Max(b => (long?)b.AmountMinor),
                    })
                    .ToListAsync(cancellationToken);

                dashboard.Auctions = auctions;
            }

            if (tenant.Has(PhilmartConstants.Permission.ReportView))
            {
                var sold = listings.Where(x => x.State == PhilmartConstants.ListingState.Sold && (x.ClosedAt ?? x.UpdatedAt) >= yearStart);

                dashboard.ItemsSoldThisYear = await sold.CountAsync(cancellationToken);
                dashboard.SalesValueThisYearMinor = await sold.SumAsync(x => x.SoldPriceMinor ?? x.PriceMinor ?? 0, cancellationToken);
            }

            if (tenant.Has(PhilmartConstants.Permission.ShopUsersView))
            {
                var users = context.Database
                    .SqlQuery<UserRow>($"SELECT PasswordHash, DisabledAt FROM philmart.Shop_User WHERE ShopID = {shopId}");

                var all = await users.ToListAsync(cancellationToken);
                dashboard.ActiveUsers = all.Count(x => x.DisabledAt == null && x.PasswordHash != null);
                dashboard.PendingInvitations = all.Count(x => x.DisabledAt == null && x.PasswordHash == null);
            }

            return dashboard;
        }
    }

    private class UserRow
    {
        public string? PasswordHash { get; set; }

        public DateTimeOffset? DisabledAt { get; set; }
    }
}
