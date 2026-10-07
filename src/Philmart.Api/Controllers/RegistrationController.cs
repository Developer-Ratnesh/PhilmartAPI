using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Auth;
using Philmart.Application.Auth;
using Philmart.Application.Registration;

namespace Philmart.Api.Controllers;

// BR-01, SCR-PUB-014.1 to 014.4
[ApiController]
[Route("api/register")]
[Produces("application/json")]
public class RegistrationController(IRegistrationService registration, IAuthService auth, TokenIssuer tokens) : ControllerBase
{
    // Step 1, "Send verification PIN". Also the resend.
    [HttpPost]
    [AllowAnonymous]
    public Task<PinChallengeDTO> Start(StartRegistrationRequest request, CancellationToken cancellationToken)
    {
        return registration.Start(request, cancellationToken);
    }

    // Step 1, "Verify email and continue". Signs them in so they can carry on
    // through the steps. Nothing that commits money is open until step 4.
    [HttpPost("verify")]
    [AllowAnonymous]
    public async Task<ActionResult<SignInResponse>> Verify(PinVerifyRequest request, CancellationToken cancellationToken)
    {
        Guid buyerId = await registration.VerifyEmail(request, cancellationToken);

        var user = await auth.ForBuyer(buyerId, cancellationToken);
        return new SignInResponse { Token = tokens.Issue(user), User = user };
    }

    [HttpGet]
    [Authorize]
    public Task<RegistrationStateDTO> State(CancellationToken cancellationToken)
    {
        return registration.GetState(cancellationToken);
    }

    [HttpPut("personal")]
    [Authorize]
    public async Task<IActionResult> Personal(PersonalDetailsRequest request, CancellationToken cancellationToken)
    {
        await registration.SavePersonalDetails(request, cancellationToken);
        return NoContent();
    }

    [HttpGet("delivery-options")]
    [Authorize]
    public Task<List<DeliveryOptionDTO>> DeliveryOptions(CancellationToken cancellationToken)
    {
        return registration.GetDeliveryOptions(cancellationToken);
    }

    [HttpPut("address")]
    [Authorize]
    public async Task<IActionResult> Address(AddressDetailsRequest request, CancellationToken cancellationToken)
    {
        await registration.SaveAddressDetails(request, cancellationToken);
        return NoContent();
    }

    [HttpGet("legal")]
    [Authorize]
    public Task<List<LegalDocumentDTO>> Legal(CancellationToken cancellationToken)
    {
        return registration.GetDocumentsToAccept(cancellationToken);
    }

    // step 4, and also where a buyer renews after a document is superseded
    [HttpPost("accept")]
    [Authorize]
    public async Task<IActionResult> Accept(AcceptLegalRequest request, CancellationToken cancellationToken)
    {
        string? ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        string? agent = Request.Headers.UserAgent.ToString();

        await registration.Accept(request, ip, agent, cancellationToken);
        return NoContent();
    }
}
