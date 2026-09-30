using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Admin;
using Philmart.Application.Common;

namespace Philmart.Api.Controllers;

// BR-21 PHILMART administration and oversight
[ApiController]
[Authorize]
[RequiresPlatformAdmin]
[Route("api/admin")]
[Produces("application/json")]
public class AdminController(IAdminOversightService oversight) : ControllerBase
{
    // SCR-ADM-001
    [HttpGet("dashboard")]
    public async Task<ActionResult<AdminDashboardDTO>> Dashboard(CancellationToken cancellationToken)
    {
        return Ok(await oversight.GetDashboard(cancellationToken));
    }

    // SCR-ADM-004
    [HttpGet("shops")]
    public async Task<ActionResult<PagedResult<AdminShopDTO>>> Shops(
        [FromQuery] string? query,
        [FromQuery] string? status,
        [FromQuery] bool overdueOnly = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        CancellationToken cancellationToken = default)
    {
        var filter = new AdminShopFilter();
        filter.Query = query;
        filter.Status = status;
        filter.OverdueOnly = overdueOnly;

        return Ok(await oversight.SearchShops(filter, new PageRequest(page, pageSize), cancellationToken));
    }

    [HttpGet("shops/{id:guid}")]
    public async Task<ActionResult<AdminShopDTO>> GetShop(Guid id, CancellationToken cancellationToken)
    {
        var shop = await oversight.GetShop(id, cancellationToken);

        if (shop == null)
        {
            return NotFound();
        }

        return Ok(shop);
    }
}
