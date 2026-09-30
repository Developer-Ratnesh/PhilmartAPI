using Microsoft.EntityFrameworkCore;
using Philmart.Application.Common;
using Philmart.Application.Marketplace;
using Philmart.Domain.Constants;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Persistence.Entities;

namespace Philmart.Infrastructure.Services;

public class MarketplaceService(IDbContextFactory<PhilmartContext> contextFactory) : IMarketplaceService
{
    public async Task<PagedResult<MarketplaceItemDTO>> Browse(MarketplaceFilter filter, PageRequest page, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var query = PublicListings(context);

            if (!string.IsNullOrWhiteSpace(filter.Query))
            {
                string term = filter.Query.Trim();
                query = query.Where(x => x.Item.Title.Contains(term) || (x.Item.Description != null && x.Item.Description.Contains(term)));
            }

            if (!string.IsNullOrWhiteSpace(filter.SellingMethod) && filter.SellingMethod != "All")
            {
                query = query.Where(x => x.ListingType == filter.SellingMethod);
            }

            if (filter.AreaCountryID != null)
            {
                query = query.Where(x => x.Item.AreaCountryID == filter.AreaCountryID);
            }

            if (filter.TypeID != null)
            {
                query = query.Where(x => x.Item.TypeID == filter.TypeID);
            }

            if (filter.SubtypeID != null)
            {
                query = query.Where(x => x.Item.SubtypeID == filter.SubtypeID);
            }

            if (filter.FormatID != null)
            {
                query = query.Where(x => x.Item.FormatID == filter.FormatID);
            }

            if (filter.StampStateID != null)
            {
                query = query.Where(x => x.Item.StampStateID == filter.StampStateID);
            }

            if (filter.ThemeID != null)
            {
                query = query.Where(x => x.Item.ThemeID == filter.ThemeID);
            }

            if (filter.ShopID != null)
            {
                query = query.Where(x => x.ShopID == filter.ShopID);
            }

            query = Sort(query, filter.Sort);

            int total = await query.CountAsync(cancellationToken);

            var rows = await query.Skip(page.Skip).Take(page.SafePageSize).ToListAsync(cancellationToken);

            var items = new List<MarketplaceItemDTO>();

            foreach (var row in rows)
            {
                items.Add(ToDto(row));
            }

            return PagedResult<MarketplaceItemDTO>.Create(items, page.SafePage, page.SafePageSize, total);
        }
    }

    public async Task<MarketplaceItemDTO?> GetListing(Guid listingId, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var listing = await PublicListings(context).Where(x => x.ID == listingId).FirstOrDefaultAsync(cancellationToken);

            if (listing == null)
            {
                return null;
            }

            return ToDto(listing);
        }
    }

    public async Task<PagedResult<MarketplaceItemDTO>> GetStorefront(Guid shopId, PageRequest page, CancellationToken cancellationToken = default)
    {
        var filter = new MarketplaceFilter();
        filter.ShopID = shopId;

        return await Browse(filter, page, cancellationToken);
    }

    // Live listings from active shops. Anything else has no live listing so it
    // never shows up publicly.
    private static IQueryable<ListListing> PublicListings(PhilmartContext context)
    {
        return context.ListListings.AsNoTracking()
            .Include(i => i.Item).ThenInclude(i => i.ItemImages)
            .Include(i => i.Shop)
            .Include(i => i.ListBids)
            .Where(x => x.State == PhilmartConstants.ListingState.Live && x.Shop.Status == PhilmartConstants.ShopStatus.Active);
    }

    private static IQueryable<ListListing> Sort(IQueryable<ListListing> query, string sort)
    {
        switch (sort)
        {
            case "price_asc":
                return query.OrderBy(x => x.PriceMinor ?? x.StartingPriceMinor);

            case "price_desc":
                return query.OrderByDescending(x => x.PriceMinor ?? x.StartingPriceMinor);

            case "ending":
                return query.OrderBy(x => x.EndsAt ?? DateTimeOffset.MaxValue);

            default:
                return query.OrderByDescending(x => x.ListedAt ?? x.CreatedAt);
        }
    }

    private static MarketplaceItemDTO ToDto(ListListing listing)
    {
        var dto = new MarketplaceItemDTO();
        dto.ListingID = listing.ID;
        dto.ItemID = listing.ItemID;
        dto.Title = listing.Item.Title;
        dto.ListingType = listing.ListingType;
        dto.ShopID = listing.ShopID;
        dto.ShopName = listing.Shop.TradingName;
        dto.PriceMinor = listing.PriceMinor;
        dto.EndsAt = listing.EndsAt;
        dto.BidCount = listing.ListBids.Count;
        dto.ListedAt = listing.ListedAt ?? listing.CreatedAt;
        dto.ImageCount = listing.Item.ItemImages.Count;

        if (listing.ListBids.Count > 0)
        {
            long high = 0;

            foreach (var bid in listing.ListBids)
            {
                if (bid.AmountMinor > high)
                {
                    high = bid.AmountMinor;
                }
            }

            dto.CurrentBidMinor = high;
        }

        foreach (var image in listing.Item.ItemImages)
        {
            if (image.IsPrimary)
            {
                dto.PrimaryImageUrl = image.StorageKey;
                break;
            }
        }

        return dto;
    }

    public async Task<List<ClassificationOptionDTO>> GetAreaCountries(CancellationToken cancellationToken = default)
    {
        return await Options("Sys_ClassificationAreaCountry", null, cancellationToken);
    }

    public async Task<List<ClassificationOptionDTO>> GetTypes(CancellationToken cancellationToken = default)
    {
        return await Options("Sys_ClassificationType", null, cancellationToken);
    }

    public async Task<List<ClassificationOptionDTO>> GetSubtypes(Guid typeId, CancellationToken cancellationToken = default)
    {
        return await Options("Sys_ClassificationSubtype", typeId, cancellationToken);
    }

    public async Task<List<ClassificationOptionDTO>> GetThemes(CancellationToken cancellationToken = default)
    {
        return await Options("Sys_ClassificationTheme", null, cancellationToken);
    }

    // table name comes from the four methods above, never from the user
    private async Task<List<ClassificationOptionDTO>> Options(string table, Guid? typeId, CancellationToken cancellationToken)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            if (typeId == null)
            {
                string sql = "SELECT ID, Code, Name, SortOrder FROM philmart." + table + " WHERE Active = 1 ORDER BY SortOrder, Name";

                return await context.Database.SqlQueryRaw<ClassificationOptionDTO>(sql).ToListAsync(cancellationToken);
            }

            string filtered = "SELECT ID, Code, Name, SortOrder FROM philmart." + table + " WHERE Active = 1 AND TypeID = {0} ORDER BY SortOrder, Name";

            return await context.Database.SqlQueryRaw<ClassificationOptionDTO>(filtered, typeId.Value).ToListAsync(cancellationToken);
        }
    }
}
