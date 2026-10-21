using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.ShopDashboard;

namespace Philmart.Api.Controllers;

// SCR-SHP-002. Every Shop user gets it; the service leaves out the figures
// their permissions don't cover.
[ApiController]
[Authorize]
[Route("api/shop/dashboard")]
[Produces("application/json")]
public class ShopDashboardController(IShopDashboardService dashboard) : ControllerBase
{
    [HttpGet]
    public Task<ShopDashboardDTO> Get(CancellationToken cancellationToken)
    {
        return dashboard.Get(cancellationToken);
    }
}
