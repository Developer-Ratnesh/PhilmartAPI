using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Common;
using Philmart.Application.Items;
using Philmart.Domain.Constants;

namespace Philmart.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/items")]
[Produces("application/json")]
public class ItemsController(IItemService items) : ControllerBase
{
    [HttpGet]
    [RequiresPermission(PhilmartConstants.Permission.ItemView)]
    public async Task<ActionResult<PagedResult<ItemDTO>>> Search(
        [FromQuery] string? query,
        [FromQuery] string? state,
        [FromQuery] Guid? sellerId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        CancellationToken cancellationToken = default)
    {
        var request = new ItemSearchRequest();
        request.Query = query;
        request.State = state;
        request.SellerID = sellerId;
        request.Page = new PageRequest(page, pageSize);

        return Ok(await items.Search(request, cancellationToken));
    }

    [HttpGet("{id:guid}")]
    [RequiresPermission(PhilmartConstants.Permission.ItemView)]
    public async Task<ActionResult<ItemDTO>> GetById(Guid id, CancellationToken cancellationToken)
    {
        var item = await items.GetById(id, cancellationToken);

        if (item == null)
        {
            return NotFound();
        }

        return Ok(item);
    }

    // use this to draw the buttons, the allowed list lives in the database
    [HttpGet("{id:guid}/transitions")]
    [RequiresPermission(PhilmartConstants.Permission.ItemView)]
    public async Task<ActionResult<List<ItemTransitionOption>>> GetTransitions(
        Guid id,
        CancellationToken cancellationToken)
    {
        return Ok(await items.GetTransitions(id, cancellationToken));
    }

    [HttpPost("{id:guid}/transition")]
    [RequiresPermission(PhilmartConstants.Permission.ItemRemove)]
    public async Task<IActionResult> Transition(
        Guid id,
        [FromBody] ItemTransitionRequest request,
        CancellationToken cancellationToken)
    {
        var result = await items.Transition(id, request, cancellationToken);

        if (!result.Succeeded)
        {
            var body = new
            {
                status = 422,
                title = "That change is not allowed",
                detail = result.Error,
                decisionRef = result.DecisionRef
            };

            return UnprocessableEntity(body);
        }

        return NoContent();
    }

    // report only, doesn't touch the items
    [HttpGet("ageing")]
    [RequiresPermission(PhilmartConstants.Permission.ItemView)]
    public async Task<ActionResult<List<ItemDTO>>> GetAgeing(
        [FromQuery] int minimumDays = PhilmartConstants.Thresholds.ReadyToListAttentionDays,
        CancellationToken cancellationToken = default)
    {
        return Ok(await items.GetAgeing(minimumDays, cancellationToken));
    }
}
