using Philmart.Application.Common;

namespace Philmart.Application.Admin;

// BR-21. Read side of the PHILMART administration surfaces. Platform admins
// only, and never a Shop user (D049), the controller checks that.
public interface IAdminOversightService
{
    // SCR-ADM-001 current overview
    Task<AdminDashboardDTO> GetDashboard(CancellationToken cancellationToken = default);

    // SCR-ADM-004 Shop register
    Task<PagedResult<AdminShopDTO>> SearchShops(AdminShopFilter filter, PageRequest page, CancellationToken cancellationToken = default);

    Task<AdminShopDTO?> GetShop(Guid shopId, CancellationToken cancellationToken = default);
}
