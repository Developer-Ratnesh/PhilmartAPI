using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.Account;
using Philmart.Application.Common;

namespace Philmart.Api.Controllers;

// Saved Items (SCR-PUB-009) and Recently Viewed (SCR-PUB-008). The buyer is
// always the one on the login token.
[ApiController]
[Authorize]
[Route("api/account")]
[Produces("application/json")]
public class AccountController(IBuyerListService lists) : ControllerBase
{
    [HttpGet("saved")]
    public Task<PagedResult<BuyerListItemDTO>> Saved([FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
    {
        return lists.GetSaved(search, new PageRequest(page, pageSize), cancellationToken);
    }

    [HttpGet("saved/{listingId:guid}")]
    public Task<SavedStateDTO> IsSaved(Guid listingId, CancellationToken cancellationToken)
    {
        return lists.IsSaved(listingId, cancellationToken);
    }

    [HttpPut("saved/{listingId:guid}")]
    public async Task<IActionResult> Save(Guid listingId, CancellationToken cancellationToken)
    {
        await lists.Save(listingId, cancellationToken);
        return NoContent();
    }

    [HttpDelete("saved/{listingId:guid}")]
    public async Task<IActionResult> RemoveSaved(Guid listingId, CancellationToken cancellationToken)
    {
        await lists.RemoveSaved(listingId, cancellationToken);
        return NoContent();
    }

    [HttpGet("recent")]
    public Task<PagedResult<BuyerListItemDTO>> Recent([FromQuery] int page = 1, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
    {
        return lists.GetRecent(new PageRequest(page, pageSize), cancellationToken);
    }

    [HttpPut("recent/{listingId:guid}")]
    public async Task<IActionResult> RecordView(Guid listingId, CancellationToken cancellationToken)
    {
        await lists.RecordView(listingId, cancellationToken);
        return NoContent();
    }

    [HttpDelete("recent/{listingId:guid}")]
    public async Task<IActionResult> RemoveRecent(Guid listingId, CancellationToken cancellationToken)
    {
        await lists.RemoveRecent(listingId, cancellationToken);
        return NoContent();
    }
}
