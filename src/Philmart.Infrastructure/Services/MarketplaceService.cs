using Microsoft.EntityFrameworkCore;
using Philmart.Application.Common;
using Philmart.Application.Marketplace;
using Philmart.Application.Registration;
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

    public async Task<ListingDetailDTO?> GetDetail(Guid listingId, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            // the database only shows the public live and closed listings (011)
            var row = await context.Database
                .SqlQuery<DetailRow>($@"SELECT l.ID AS ListingID, i.ID AS ItemID, l.Reference, i.Title, i.Description,
                                                      l.ListingType, l.State, ac.Name AS AreaCountry, t.Name AS Type, st.Name AS Subtype,
                                                      th.Name AS Theme, c.Name AS Condition, i.CatalogueReference,
                                                      s.ID AS ShopID, s.TradingName AS ShopName, s.Reference AS ShopReference,
                                                      CAST(CASE WHEN s.Status = 'active' THEN 1 ELSE 0 END AS BIT) AS ShopActive,
                                                      l.PriceMinor, l.StartingPriceMinor, l.BidIncrementMinor,
                                                      l.ReservePriceMinor, l.StartsAt, l.EndsAt, l.SoftCloseSeconds, l.ExtensionCount,
                                                      philmart.ServerNow() AS ServerNow
                                               FROM philmart.List_Listing l
                                               JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                               JOIN philmart.Shop_Shop s ON s.ID = l.ShopID
                                               LEFT JOIN philmart.Sys_ClassificationAreaCountry ac ON ac.ID = i.AreaCountryID
                                               LEFT JOIN philmart.Sys_ClassificationType t ON t.ID = i.TypeID
                                               LEFT JOIN philmart.Sys_ClassificationSubtype st ON st.ID = i.SubtypeID
                                               LEFT JOIN philmart.Sys_ClassificationTheme th ON th.ID = i.ThemeID
                                               LEFT JOIN philmart.Sys_ItemCondition c ON c.ID = i.ConditionID
                                               WHERE l.ID = {listingId}")
                .FirstOrDefaultAsync(cancellationToken);

            if (row == null)
            {
                return null;
            }

            var dto = ToDetail(row);

            dto.Images = await context.Database
                .SqlQuery<string>($"SELECT StorageKey AS Value FROM philmart.Item_Image WHERE ItemID = {dto.ItemID} ORDER BY IsPrimary DESC, SortOrder")
                .ToListAsync(cancellationToken);

            dto.DeliveryOptions = await DeliveryOptions.Load(context, dto.ShopID, cancellationToken);

            string commitmentCode = dto.ListingType == PhilmartConstants.ListingType.Auction ? "LEGAL-DEC-002" : "LEGAL-DEC-001";
            dto.Commitment = await context.Database
                .SqlQuery<LegalDocumentDTO>($@"SELECT v.ID AS VersionID, d.Code, d.Name, v.Version, d.AcceptanceMode, v.Body
                                               FROM philmart.Sys_LegalDocumentVersion v JOIN philmart.Sys_LegalDocument d ON d.Code = v.DocumentCode
                                               WHERE v.DocumentCode = {commitmentCode} AND v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL")
                .FirstOrDefaultAsync(cancellationToken);

            if (dto.ListingType == PhilmartConstants.ListingType.Auction)
            {
                dto.Bids = await context.Database
                    .SqlQuery<BidHistoryDTO>($"SELECT SequenceNo, AmountMinor, PlacedAt FROM philmart.List_Bid WHERE ListingID = {listingId} ORDER BY SequenceNo DESC")
                    .ToListAsync(cancellationToken);

                long high = dto.Bids.Count == 0 ? 0 : dto.Bids.Max(x => x.AmountMinor);
                long step = dto.BidIncrementMinor ?? 1;
                long start = dto.StartingPriceMinor ?? 0;

                dto.CurrentBidMinor = dto.Bids.Count == 0 ? null : high;
                dto.NextMinimumBidMinor = Math.Max(start, high + step);

                // the reserve amount itself stays private, only whether it's met
                dto.ReserveMet = row.ReservePriceMinor == null || high >= row.ReservePriceMinor;
            }

            return dto;
        }
    }

    public async Task<ShopProfileDTO?> GetShopProfile(Guid shopId, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            // Shop settings are private to the Shop, so read as system and only
            // send back the public fields
            await context.UseSystemSession(null, cancellationToken);

            return await context.Database
                .SqlQuery<ShopProfileDTO>($@"SELECT s.ID AS ShopID, s.Reference, ISNULL(ss.PublicProfileName, s.TradingName) AS Name,
                                                    ss.PublicProfileBlurb AS Blurb,
                                                    CAST(CASE WHEN s.Status = 'active' THEN 1 ELSE 0 END AS BIT) AS Active
                                             FROM philmart.Shop_Shop s
                                             LEFT JOIN philmart.Shop_Settings ss ON ss.ShopID = s.ID
                                             WHERE s.ID = {shopId} AND s.Status IN ('active', 'deactivated')")
                .FirstOrDefaultAsync(cancellationToken);
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

    private static ListingDetailDTO ToDetail(DetailRow row)
    {
        var dto = new ListingDetailDTO();
        dto.ListingID = row.ListingID;
        dto.ItemID = row.ItemID;
        dto.Reference = row.Reference;
        dto.Title = row.Title;
        dto.Description = row.Description;
        dto.ListingType = row.ListingType;
        dto.State = row.State;
        dto.AreaCountry = row.AreaCountry;
        dto.Type = row.Type;
        dto.Subtype = row.Subtype;
        dto.Theme = row.Theme;
        dto.Condition = row.Condition;
        dto.CatalogueReference = row.CatalogueReference;
        dto.ShopID = row.ShopID;
        dto.ShopName = row.ShopName;
        dto.ShopReference = row.ShopReference;
        dto.ShopActive = row.ShopActive;
        dto.PriceMinor = row.PriceMinor;
        dto.StartingPriceMinor = row.StartingPriceMinor;
        dto.BidIncrementMinor = row.BidIncrementMinor;
        dto.StartsAt = row.StartsAt;
        dto.EndsAt = row.EndsAt;
        dto.SoftCloseSeconds = row.SoftCloseSeconds;
        dto.ExtensionCount = row.ExtensionCount;
        dto.ServerNow = row.ServerNow;
        return dto;
    }

    private class DetailRow
    {
        public Guid ListingID { get; set; }

        public Guid ItemID { get; set; }

        public string Reference { get; set; } = null!;

        public string Title { get; set; } = null!;

        public string? Description { get; set; }

        public string ListingType { get; set; } = null!;

        public string State { get; set; } = null!;

        public string? AreaCountry { get; set; }

        public string? Type { get; set; }

        public string? Subtype { get; set; }

        public string? Theme { get; set; }

        public string? Condition { get; set; }

        public string? CatalogueReference { get; set; }

        public Guid ShopID { get; set; }

        public string ShopName { get; set; } = null!;

        public string ShopReference { get; set; } = null!;

        public bool ShopActive { get; set; }

        public long? PriceMinor { get; set; }

        public long? StartingPriceMinor { get; set; }

        public long? BidIncrementMinor { get; set; }

        public long? ReservePriceMinor { get; set; }

        public DateTimeOffset? StartsAt { get; set; }

        public DateTimeOffset? EndsAt { get; set; }

        public int? SoftCloseSeconds { get; set; }

        public int ExtensionCount { get; set; }

        public DateTimeOffset ServerNow { get; set; }
    }
}
