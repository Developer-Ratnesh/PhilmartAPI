using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Admin;
using Philmart.Application.Common;
using Philmart.Application.Restrictions;

namespace Philmart.Api.Controllers;

// BR-21 PHILMART administration and oversight
[ApiController]
[Authorize]
[RequiresPlatformAdmin]
[Route("api/admin")]
[Produces("application/json")]
public class AdminController(IAdminOversightService oversight, IBuyerRestrictionService restrictions) : ControllerBase
{
    [HttpGet("dashboard")]
    public async Task<ActionResult<AdminDashboardDTO>> Dashboard(CancellationToken cancellationToken)
    {
        return Ok(await oversight.GetDashboard(cancellationToken));
    }

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

    [HttpPost("shops/{id:guid}/deactivate")]
    public async Task<IActionResult> Deactivate(Guid id, ShopStatusChangeRequest request, CancellationToken cancellationToken)
    {
        await oversight.DeactivateShop(id, request.Reason, cancellationToken);
        return NoContent();
    }

    [HttpPost("shops/{id:guid}/reactivate")]
    public async Task<IActionResult> Reactivate(Guid id, ShopStatusChangeRequest request, CancellationToken cancellationToken)
    {
        await oversight.ReactivateShop(id, request.Reason, cancellationToken);
        return NoContent();
    }

    // D045: PHILMART's platform-wide buyer restrictions; Shop ones are listed too
    [HttpGet("restrictions")]
    public Task<List<BuyerRestrictionDTO>> Restrictions(CancellationToken cancellationToken)
    {
        return restrictions.List(cancellationToken);
    }

    [HttpPost("restrictions")]
    public Task<BuyerRestrictionDTO> Restrict(RestrictBuyerRequest request, CancellationToken cancellationToken)
    {
        return restrictions.Restrict(request, cancellationToken);
    }

    [HttpPost("restrictions/{id:guid}/lift")]
    public async Task<IActionResult> Lift(Guid id, LiftRestrictionRequest request, CancellationToken cancellationToken)
    {
        await restrictions.Lift(id, request, cancellationToken);
        return NoContent();
    }
}
