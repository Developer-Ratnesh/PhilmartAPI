using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.Registration;

namespace Philmart.Api.Controllers;

// The public Terms & Conditions page. Only the current published buyer
// documents, the same ones registration asks people to accept.
[ApiController]
[AllowAnonymous]
[Route("api/legal")]
[Produces("application/json")]
public class LegalController(IRegistrationService registration) : ControllerBase
{
    [HttpGet]
    public Task<List<LegalDocumentDTO>> Current(CancellationToken cancellationToken)
    {
        return registration.GetDocumentsToAccept(cancellationToken);
    }
}
