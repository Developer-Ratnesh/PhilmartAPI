using Philmart.Application.Common;

namespace Philmart.Application.Account;

// Saved Items and Recently Viewed. Both belong to the signed-in buyer only.
public interface IBuyerListService
{
    Task<PagedResult<BuyerListItemDTO>> GetSaved(string? search, PageRequest page, CancellationToken cancellationToken = default);

    Task<SavedStateDTO> IsSaved(Guid listingId, CancellationToken cancellationToken = default);

    Task Save(Guid listingId, CancellationToken cancellationToken = default);

    Task RemoveSaved(Guid listingId, CancellationToken cancellationToken = default);

    Task<PagedResult<BuyerListItemDTO>> GetRecent(PageRequest page, CancellationToken cancellationToken = default);

    Task RecordView(Guid listingId, CancellationToken cancellationToken = default);

    Task RemoveRecent(Guid listingId, CancellationToken cancellationToken = default);
}
