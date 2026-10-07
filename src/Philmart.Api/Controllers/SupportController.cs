using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Philmart.Application.Support;

namespace Philmart.Api.Controllers;

// BR-02-R07, SCR-PUB-015. Open to visitors, signed-in buyers are recognised.
[ApiController]
[Route("api/support")]
[Produces("application/json")]
public class SupportController(ISupportService support) : ControllerBase
{
    [HttpGet("categories")]
    public Task<List<SupportCategoryDTO>> Categories(CancellationToken cancellationToken)
    {
        return support.GetCategories(cancellationToken);
    }

    [HttpPost]
    [EnableRateLimiting(Program.SupportLimit)]
    public Task<SupportReceiptDTO> Submit(SupportRequest request, CancellationToken cancellationToken)
    {
        return support.Submit(request, cancellationToken);
    }
}
