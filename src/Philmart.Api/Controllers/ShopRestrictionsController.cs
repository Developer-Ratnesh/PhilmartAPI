using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Restrictions;
using Philmart.Domain.Constants;

namespace Philmart.Api.Controllers;

// D044. A Shop restricts a buyer from new purchases and bids with that Shop.
[ApiController]
[Authorize]
[RequiresPermission(PhilmartConstants.Permission.BuyerRestrict)]
[Route("api/shop/restrictions")]
[Produces("application/json")]
public class ShopRestrictionsController(IBuyerRestrictionService restrictions) : ControllerBase
{
    [HttpGet]
    public Task<List<BuyerRestrictionDTO>> List(CancellationToken cancellationToken)
    {
        return restrictions.List(cancellationToken);
    }

    [HttpPost]
    public Task<BuyerRestrictionDTO> Restrict(RestrictBuyerRequest request, CancellationToken cancellationToken)
    {
        return restrictions.Restrict(request, cancellationToken);
    }

    [HttpPost("{id:guid}/lift")]
    public async Task<IActionResult> Lift(Guid id, LiftRestrictionRequest request, CancellationToken cancellationToken)
    {
        await restrictions.Lift(id, request, cancellationToken);
        return NoContent();
    }
}
