using Philmart.Application.Common;

namespace Philmart.Application.Items;

public interface IItemService
{
    Task<ItemDTO?> GetById(Guid id, CancellationToken cancellationToken = default);

    Task<PagedResult<ItemDTO>> GetByState(string state, PageRequest page, CancellationToken cancellationToken = default);

    Task<PagedResult<ItemDTO>> Search(ItemSearchRequest request, CancellationToken cancellationToken = default);

    Task<List<ItemTransitionOption>> GetTransitions(Guid id, CancellationToken cancellationToken = default);

    Task<Result> Transition(Guid id, ItemTransitionRequest request, CancellationToken cancellationToken = default);

    // items sitting in Ready to List too long, for the 60 and 75 day warnings
    Task<List<ItemDTO>> GetAgeing(int minimumDays, CancellationToken cancellationToken = default);
}
