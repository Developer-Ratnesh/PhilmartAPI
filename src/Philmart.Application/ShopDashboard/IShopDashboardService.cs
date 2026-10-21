namespace Philmart.Application.ShopDashboard;

public interface IShopDashboardService
{
    // the Shop comes from the login token, never from the request
    Task<ShopDashboardDTO> Get(CancellationToken cancellationToken = default);
}
