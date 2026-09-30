using Microsoft.EntityFrameworkCore;
using Philmart.Application.Admin;
using Philmart.Application.Common;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Persistence.Entities;

namespace Philmart.Infrastructure.Services;

public class AdminOversightService(
    IDbContextFactory<PhilmartContext> contextFactory,
    IServerClock clock) : IAdminOversightService
{
    // Superseded invoices are replaced by the invoice that superseded them, so
    // counting both would double the arrears.
    private const string FeeStandingSql =
        @"SELECT v.ShopID,
                 CAST(SUM(CASE WHEN v.OutstandingMinor > 0 THEN v.OutstandingMinor ELSE 0 END) AS BIGINT) AS OutstandingMinor,
                 CAST(SUM(CASE WHEN v.IsOverdue = 1 THEN v.OutstandingMinor ELSE 0 END) AS BIGINT) AS OverdueMinor
          FROM philmart.VW_FeeInvoiceSettlement AS v
          JOIN philmart.Fee_Invoice AS f ON f.ID = v.FeeInvoiceID
          WHERE f.SupersededByID IS NULL
          GROUP BY v.ShopID";

    public async Task<AdminDashboardDTO> GetDashboard(CancellationToken cancellationToken = default)
    {
        var now = await clock.Now();
        var escalationCutoff = now.AddDays(-PhilmartConstants.Thresholds.ReadyToListEscalationDays);

        using (var context = contextFactory.CreateDbContext())
        {
            var dashboard = new AdminDashboardDTO();
            dashboard.AsAt = now;

            var statusCounts = await context.ShopShops
                .GroupBy(x => x.Status)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync(cancellationToken);

            foreach (var row in statusCounts)
            {
                switch (row.Status)
                {
                    case PhilmartConstants.ShopStatus.ApplicationSubmitted:
                        dashboard.ApplicationsAwaitingReview = row.Count;
                        break;

                    case PhilmartConstants.ShopStatus.SetupAccessGranted:
                        dashboard.ShopsInSetup = row.Count;
                        break;

                    case PhilmartConstants.ShopStatus.Active:
                        dashboard.ActiveShops = row.Count;
                        break;

                    case PhilmartConstants.ShopStatus.Deactivated:
                        dashboard.DeactivatedShops = row.Count;
                        break;
                }
            }

            var live = context.ListListings.Where(x => x.State == PhilmartConstants.ListingState.Live);

            dashboard.LiveFixedPriceListings = await live
                .CountAsync(x => x.ListingType == PhilmartConstants.ListingType.FixedPrice, cancellationToken);

            dashboard.LiveAuctions = await live
                .CountAsync(x => x.ListingType == PhilmartConstants.ListingType.Auction, cancellationToken);

            dashboard.LiveAuctionsWithBids = await live
                .CountAsync(x => x.ListingType == PhilmartConstants.ListingType.Auction && x.ListBids.Any(), cancellationToken);

            var readyToList = context.ItemItems.Where(x => x.State == PhilmartConstants.ItemState.ReadyToList);

            dashboard.ItemsReadyToList = await readyToList.CountAsync(cancellationToken);

            dashboard.ItemsPastReadyToListEscalation = await readyToList
                .CountAsync(x => x.ReadyToListSince != null && x.ReadyToListSince <= escalationCutoff, cancellationToken);

            var fees = await LoadFeeStanding(context, cancellationToken);

            foreach (var fee in fees.Values)
            {
                dashboard.FeesOutstandingMinor += fee.OutstandingMinor;
                dashboard.FeesOverdueMinor += fee.OverdueMinor;

                if (fee.OverdueMinor > 0)
                {
                    dashboard.ShopsWithOverdueFees++;
                }
            }

            return dashboard;
        }
    }

    public async Task<PagedResult<AdminShopDTO>> SearchShops(AdminShopFilter filter, PageRequest page, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var fees = await LoadFeeStanding(context, cancellationToken);

            IQueryable<ShopShop> query = context.ShopShops;

            if (!string.IsNullOrWhiteSpace(filter.Query))
            {
                string term = filter.Query.Trim();
                query = query.Where(x => x.TradingName.Contains(term)
                    || x.Reference.Contains(term)
                    || (x.LegalEntityName != null && x.LegalEntityName.Contains(term)));
            }

            if (!string.IsNullOrWhiteSpace(filter.Status))
            {
                query = query.Where(x => x.Status == filter.Status);
            }

            if (filter.OverdueOnly)
            {
                var overdueShopIds = new List<Guid>();

                foreach (var fee in fees.Values)
                {
                    if (fee.OverdueMinor > 0)
                    {
                        overdueShopIds.Add(fee.ShopID);
                    }
                }

                query = query.Where(x => overdueShopIds.Contains(x.ID));
            }

            int total = await query.CountAsync(cancellationToken);

            var rows = await Project(query.OrderBy(x => x.TradingName))
                .Skip(page.Skip)
                .Take(page.SafePageSize)
                .ToListAsync(cancellationToken);

            foreach (var row in rows)
            {
                ApplyFees(row, fees);
            }

            return PagedResult<AdminShopDTO>.Create(rows, page.SafePage, page.SafePageSize, total);
        }
    }

    public async Task<AdminShopDTO?> GetShop(Guid shopId, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var shop = await Project(context.ShopShops.Where(x => x.ID == shopId))
                .FirstOrDefaultAsync(cancellationToken);

            if (shop == null)
            {
                return null;
            }

            var fees = await LoadFeeStanding(context, cancellationToken);

            ApplyFees(shop, fees);

            return shop;
        }
    }

    private static IQueryable<AdminShopDTO> Project(IQueryable<ShopShop> query)
    {
        return query.Select(x => new AdminShopDTO
        {
            ID = x.ID,
            Reference = x.Reference,
            TradingName = x.TradingName,
            LegalEntityName = x.LegalEntityName,
            Status = x.Status,
            CreatedAt = x.CreatedAt,
            SetupAccessGrantedAt = x.SetupAccessGrantedAt,
            ActivatedAt = x.ActivatedAt,
            DeactivatedAt = x.DeactivatedAt,
            DeactivationReason = x.DeactivationReason,
            ReactivatedAt = x.ReactivatedAt,
            LiveListingCount = x.ListListings.Count(l => l.State == PhilmartConstants.ListingState.Live)
        });
    }

    private static void ApplyFees(AdminShopDTO shop, Dictionary<Guid, FeeStandingRow> fees)
    {
        FeeStandingRow? fee;

        if (fees.TryGetValue(shop.ID, out fee))
        {
            shop.FeesOutstandingMinor = fee.OutstandingMinor;
            shop.FeesOverdueMinor = fee.OverdueMinor;
            shop.HasOverdueFees = fee.OverdueMinor > 0;
        }
    }

    private static async Task<Dictionary<Guid, FeeStandingRow>> LoadFeeStanding(PhilmartContext context, CancellationToken cancellationToken)
    {
        var rows = await context.Database
            .SqlQueryRaw<FeeStandingRow>(FeeStandingSql)
            .ToListAsync(cancellationToken);

        var byShop = new Dictionary<Guid, FeeStandingRow>();

        foreach (var row in rows)
        {
            byShop[row.ShopID] = row;
        }

        return byShop;
    }

    // public so EF can materialise it from SqlQueryRaw
    public class FeeStandingRow
    {
        public Guid ShopID { get; set; }

        public long OutstandingMinor { get; set; }

        public long OverdueMinor { get; set; }
    }
}
