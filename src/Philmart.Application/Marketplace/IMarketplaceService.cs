using Philmart.Application.Common;

namespace Philmart.Application.Marketplace;

public interface IMarketplaceService
{
    // grid and list view both call this, they show the same results two ways
    Task<PagedResult<MarketplaceItemDTO>> Browse(MarketplaceFilter filter, PageRequest page, CancellationToken cancellationToken = default);

    Task<MarketplaceItemDTO?> GetListing(Guid listingId, CancellationToken cancellationToken = default);

    Task<ListingDetailDTO?> GetDetail(Guid listingId, CancellationToken cancellationToken = default);

    Task<ShopProfileDTO?> GetShopProfile(Guid shopId, CancellationToken cancellationToken = default);

    Task<PagedResult<MarketplaceItemDTO>> GetStorefront(Guid shopId, PageRequest page, CancellationToken cancellationToken = default);

    Task<List<ClassificationOptionDTO>> GetAreaCountries(CancellationToken cancellationToken = default);

    Task<List<ClassificationOptionDTO>> GetTypes(CancellationToken cancellationToken = default);

    Task<List<ClassificationOptionDTO>> GetSubtypes(Guid typeId, CancellationToken cancellationToken = default);

    Task<List<ClassificationOptionDTO>> GetThemes(CancellationToken cancellationToken = default);
}
