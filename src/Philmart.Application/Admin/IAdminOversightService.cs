using Philmart.Application.Common;

namespace Philmart.Application.Admin;

// BR-21. Read-only admin screens. Platform admins only, never a Shop user (D049).
public interface IAdminOversightService
{
    Task<AdminDashboardDTO> GetDashboard(CancellationToken cancellationToken = default);

    Task<PagedResult<AdminShopDTO>> SearchShops(AdminShopFilter filter, PageRequest page, CancellationToken cancellationToken = default);

    Task<AdminShopDTO?> GetShop(Guid shopId, CancellationToken cancellationToken = default);
}
