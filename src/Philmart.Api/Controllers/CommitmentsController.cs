using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.Commitments;

namespace Philmart.Api.Controllers;

// BR-03. Confirm Purchase (SCR-PUB-003A) and Confirm Bid (SCR-PUB-003B).
[ApiController]
[Authorize]
[Route("api/listings/{listingId:guid}")]
[Produces("application/json")]
public class CommitmentsController(ICommitmentService commitments) : ControllerBase
{
    [HttpGet("purchase-defaults")]
    public Task<List<PurchaseDefaultsDTO>> PurchaseDefaults(Guid listingId, CancellationToken cancellationToken)
    {
        return commitments.GetPurchaseDefaults(listingId, cancellationToken);
    }

    [HttpPost("buy")]
    public Task<PurchaseResultDTO> Buy(Guid listingId, BuyNowRequest request, CancellationToken cancellationToken)
    {
        return commitments.BuyNow(listingId, request, Ip(), Agent(), cancellationToken);
    }

    [HttpPost("bids")]
    public Task<BidResultDTO> Bid(Guid listingId, PlaceBidRequest request, CancellationToken cancellationToken)
    {
        return commitments.PlaceBid(listingId, request, Ip(), Agent(), cancellationToken);
    }

    private string? Ip()
    {
        return HttpContext.Connection.RemoteIpAddress?.ToString();
    }

    private string? Agent()
    {
        return Request.Headers.UserAgent.ToString();
    }
}
