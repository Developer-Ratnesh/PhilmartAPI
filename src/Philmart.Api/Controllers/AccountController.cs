using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.Account;
using Philmart.Application.Common;
using Philmart.Application.Registration;

namespace Philmart.Api.Controllers;

// Saved Items (SCR-PUB-009) and Recently Viewed (SCR-PUB-008). The buyer is
// always the one on the login token.
[ApiController]
[Authorize]
[Route("api/account")]
[Produces("application/json")]
public class AccountController(IBuyerListService lists, IBuyerProfileService profile) : ControllerBase
{
    // SCR-PUB-006.1
    [HttpGet("profile")]
    public Task<BuyerProfileDTO> Profile(CancellationToken cancellationToken)
    {
        return profile.GetProfile(cancellationToken);
    }

    [HttpPut("profile/mobile")]
    public async Task<IActionResult> UpdateMobile(UpdateMobileRequest request, CancellationToken cancellationToken)
    {
        await profile.UpdateMobile(request, cancellationToken);
        return NoContent();
    }

    [HttpPut("profile/address")]
    public async Task<IActionResult> UpdateAddress(AddressDetailsRequest request, CancellationToken cancellationToken)
    {
        await profile.UpdateAddress(request, cancellationToken);
        return NoContent();
    }

    // SCR-PUB-006.3
    [HttpGet("preferences")]
    public Task<CommunicationPreferencesDTO> Preferences(CancellationToken cancellationToken)
    {
        return profile.GetPreferences(cancellationToken);
    }

    [HttpPut("preferences")]
    public async Task<IActionResult> SavePreferences(CommunicationPreferencesDTO request, CancellationToken cancellationToken)
    {
        await profile.SavePreferences(request, cancellationToken);
        return NoContent();
    }

    // the document versions this buyer accepted, newest first
    [HttpGet("legal")]
    public Task<List<LegalAcceptanceDTO>> Legal(CancellationToken cancellationToken)
    {
        return profile.GetLegalAcceptances(cancellationToken);
    }

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
