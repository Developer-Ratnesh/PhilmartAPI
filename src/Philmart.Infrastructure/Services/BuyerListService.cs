using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Philmart.Application.Account;
using Philmart.Application.Common;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class BuyerListService(IDbContextFactory<PhilmartContext> contextFactory, ITenantContext tenant) : IBuyerListService
{
    // Status as the buyer sees it now, not when they saved it (SCR-PUB-008/009
    // say the price, bid and availability are live).
    private const string StatusSql = @"
        CASE
            WHEN l.State = 'live' AND s.Status = 'active' AND l.ListingType = 'auction' THEN 'auction_open'
            WHEN l.State = 'live' AND s.Status = 'active' THEN 'available'
            WHEN l.State IN ('sold', 'unsold') AND l.ListingType = 'auction' THEN 'auction_closed'
            WHEN l.State = 'sold' THEN 'sold'
            ELSE 'unavailable'
        END";

    private const string ColumnsSql = @"
        l.ID AS ListingID, i.Reference AS ItemNumber, i.Title, l.ListingType, s.ID AS ShopID, s.TradingName AS ShopName, l.PriceMinor,
        (SELECT MAX(b.AmountMinor) FROM philmart.List_Bid b WHERE b.ListingID = l.ID) AS CurrentBidMinor,
        (SELECT TOP 1 im.StorageKey FROM philmart.Item_Image im WHERE im.ItemID = i.ID AND im.IsPrimary = 1) AS PrimaryImageUrl,";

    public async Task<PagedResult<BuyerListItemDTO>> GetSaved(string? search, PageRequest page, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();
        string like = string.IsNullOrWhiteSpace(search) ? "%" : "%" + EscapeLike(search.Trim()) + "%";

        using (var context = contextFactory.CreateDbContext())
        {
            // A listing that's been withdrawn is hidden from buyers, but it still has
            // to show here as Unavailable. Read as system, limited to this buyer's rows.
            await context.UseSystemSession(buyerId, cancellationToken);

            const string from = @"FROM philmart.Buy_SavedItem x
                            JOIN philmart.List_Listing l ON l.ID = x.ListingID
                            JOIN philmart.Item_Item i ON i.ID = l.ItemID
                            JOIN philmart.Shop_Shop s ON s.ID = l.ShopID
                            WHERE x.BuyerID = {0} AND x.RemovedAt IS NULL
                              AND (i.Title LIKE {1} OR i.Reference LIKE {1})";

            int total = await context.Database
                .SqlQueryRaw<int>("SELECT COUNT(*) AS Value " + from, buyerId, like)
                .SingleAsync(cancellationToken);

            var items = await context.Database
                .SqlQueryRaw<BuyerListItemDTO>(
                    "SELECT " + ColumnsSql + StatusSql + " AS Status, x.SavedAt AS At " + from +
                    " ORDER BY x.SavedAt DESC OFFSET {2} ROWS FETCH NEXT {3} ROWS ONLY",
                    buyerId, like, page.Skip, page.SafePageSize)
                .ToListAsync(cancellationToken);

            return PagedResult<BuyerListItemDTO>.Create(items, page.SafePage, page.SafePageSize, total);
        }
    }

    public async Task<SavedStateDTO> IsSaved(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            int count = await context.Database
                .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Buy_SavedItem WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND RemovedAt IS NULL")
                .SingleAsync(cancellationToken);

            return new SavedStateDTO { Saved = count > 0 };
        }
    }

    public async Task Save(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await CheckVisible(context, listingId, cancellationToken);

            try
            {
                await context.Database.ExecuteSqlAsync(
                    $@"IF NOT EXISTS (SELECT 1 FROM philmart.Buy_SavedItem WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND RemovedAt IS NULL)
                           INSERT INTO philmart.Buy_SavedItem (BuyerID, ListingID) VALUES ({buyerId}, {listingId})",
                    cancellationToken);
            }
            catch (SqlException ex) when (ex.Number == 2601)
            {
                // a double click got there first, it's saved either way
            }
        }
    }

    public async Task RemoveSaved(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await context.Database.ExecuteSqlAsync(
                $@"UPDATE philmart.Buy_SavedItem SET RemovedAt = philmart.ServerNow()
                   WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND RemovedAt IS NULL",
                cancellationToken);
        }
    }

    public async Task<PagedResult<BuyerListItemDTO>> GetRecent(PageRequest page, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(buyerId, cancellationToken);

            const string from = @"FROM philmart.Buy_RecentlyViewed x
                            JOIN philmart.List_Listing l ON l.ID = x.ListingID
                            JOIN philmart.Item_Item i ON i.ID = l.ItemID
                            JOIN philmart.Shop_Shop s ON s.ID = l.ShopID
                            WHERE x.BuyerID = {0} AND x.RemovedAt IS NULL";

            int total = await context.Database
                .SqlQueryRaw<int>("SELECT COUNT(*) AS Value " + from, buyerId)
                .SingleAsync(cancellationToken);

            var items = await context.Database
                .SqlQueryRaw<BuyerListItemDTO>(
                    "SELECT " + ColumnsSql + StatusSql + " AS Status, x.LastViewedAt AS At " + from +
                    " ORDER BY x.LastViewedAt DESC OFFSET {1} ROWS FETCH NEXT {2} ROWS ONLY",
                    buyerId, page.Skip, page.SafePageSize)
                .ToListAsync(cancellationToken);

            return PagedResult<BuyerListItemDTO>.Create(items, page.SafePage, page.SafePageSize, total);
        }
    }

    public async Task RecordView(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await CheckVisible(context, listingId, cancellationToken);

            try
            {
                await context.Database.ExecuteSqlAsync(
                    $@"UPDATE philmart.Buy_RecentlyViewed SET LastViewedAt = philmart.ServerNow()
                       WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND RemovedAt IS NULL;

                       IF @@ROWCOUNT = 0
                           INSERT INTO philmart.Buy_RecentlyViewed (BuyerID, ListingID) VALUES ({buyerId}, {listingId})",
                    cancellationToken);
            }
            catch (SqlException ex) when (ex.Number == 2601)
            {
                // two tabs opened the same item at once, one row is enough
            }
        }
    }

    public async Task RemoveRecent(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await context.Database.ExecuteSqlAsync(
                $@"UPDATE philmart.Buy_RecentlyViewed SET RemovedAt = philmart.ServerNow()
                   WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND RemovedAt IS NULL",
                cancellationToken);
        }
    }

    // runs as the buyer, so the database only shows listings the public can see
    private static async Task CheckVisible(PhilmartContext context, Guid listingId, CancellationToken cancellationToken)
    {
        int count = await context.Database
            .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.List_Listing WHERE ID = {listingId}")
            .SingleAsync(cancellationToken);

        if (count == 0)
        {
            throw new NotFoundException("Listing", listingId);
        }
    }

    private static string EscapeLike(string text)
    {
        return text.Replace("[", "[[]").Replace("%", "[%]").Replace("_", "[_]");
    }

    private Guid RequireBuyer()
    {
        if (!tenant.IsBuyer || tenant.ActorId == null)
        {
            throw new NotAuthorisedException("Sign in as a buyer to use your saved and recently viewed items.");
        }

        return tenant.ActorId.Value;
    }
}
