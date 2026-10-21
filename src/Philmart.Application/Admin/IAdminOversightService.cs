using Philmart.Application.Common;

namespace Philmart.Application.Admin;

// BR-21. Admin screens. Platform admins only, never a Shop user (D049).
public interface IAdminOversightService
{
    Task<AdminDashboardDTO> GetDashboard(CancellationToken cancellationToken = default);

    Task<PagedResult<AdminShopDTO>> SearchShops(AdminShopFilter filter, PageRequest page, CancellationToken cancellationToken = default);

    Task<AdminShopDTO?> GetShop(Guid shopId, CancellationToken cancellationToken = default);

    // D031: manual only, always with a reason. Fee arrears never do this on their own.
    Task DeactivateShop(Guid shopId, string reason, CancellationToken cancellationToken = default);

    Task ReactivateShop(Guid shopId, string reason, CancellationToken cancellationToken = default);
}

public class ShopStatusChangeRequest
{
    public string Reason { get; set; } = string.Empty;
}
