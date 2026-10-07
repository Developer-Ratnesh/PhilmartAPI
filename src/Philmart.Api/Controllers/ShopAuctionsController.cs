using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Auctions;
using Philmart.Domain.Constants;

namespace Philmart.Api.Controllers;

// BR-13, Shop side
[ApiController]
[Authorize]
[Route("api/shop/auctions")]
[Produces("application/json")]
public class ShopAuctionsController(IAuctionService auctions) : ControllerBase
{
    [HttpGet]
    [RequiresPermission(PhilmartConstants.Permission.AuctionManage)]
    public Task<List<ShopAuctionDTO>> List(CancellationToken cancellationToken)
    {
        return auctions.List(cancellationToken);
    }

    [HttpGet("ready-items")]
    [RequiresPermission(PhilmartConstants.Permission.AuctionManage)]
    public Task<List<ReadyItemDTO>> ReadyItems(CancellationToken cancellationToken)
    {
        return auctions.ReadyItems(cancellationToken);
    }

    [HttpPost]
    [RequiresPermission(PhilmartConstants.Permission.AuctionManage)]
    public async Task<ActionResult<Guid>> Create(CreateAuctionRequest request, CancellationToken cancellationToken)
    {
        return await auctions.Create(request, cancellationToken);
    }

    // with bids it also needs auction.cancel_with_bids, checked in the service
    // because only it knows whether there are bids
    [HttpPost("{listingId:guid}/cancel")]
    [RequiresPermission(PhilmartConstants.Permission.AuctionManage)]
    public async Task<IActionResult> Cancel(Guid listingId, CancelAuctionRequest request, CancellationToken cancellationToken)
    {
        await auctions.Cancel(listingId, request, cancellationToken);
        return NoContent();
    }
}
