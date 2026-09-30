using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Application.Common;
using Philmart.Application.Marketplace;

namespace Philmart.Api.Controllers;

// the only controller that doesn't need a login
[ApiController]
[AllowAnonymous]
[Route("api/marketplace")]
[Produces("application/json")]
public class MarketplaceController(IMarketplaceService marketplace) : ControllerBase
{
    [HttpGet("items")]
    public async Task<ActionResult<PagedResult<MarketplaceItemDTO>>> Browse(
        [FromQuery] string? query,
        [FromQuery] string? sellingMethod,
        [FromQuery] Guid? areaCountryId,
        [FromQuery] Guid? typeId,
        [FromQuery] Guid? subtypeId,
        [FromQuery] Guid? formatId,
        [FromQuery] Guid? stampStateId,
        [FromQuery] Guid? themeId,
        [FromQuery] Guid? shopId,
        [FromQuery] string sort = "newest",
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken cancellationToken = default)
    {
        var filter = new MarketplaceFilter();
        filter.Query = query;
        filter.SellingMethod = sellingMethod;
        filter.AreaCountryID = areaCountryId;
        filter.TypeID = typeId;
        filter.SubtypeID = subtypeId;
        filter.FormatID = formatId;
        filter.StampStateID = stampStateId;
        filter.ThemeID = themeId;
        filter.ShopID = shopId;
        filter.Sort = sort;

        var results = await marketplace.Browse(
            filter, new PageRequest(page, pageSize), cancellationToken);

        return Ok(results);
    }

    [HttpGet("items/{listingId:guid}")]
    public async Task<ActionResult<MarketplaceItemDTO>> GetListing(
        Guid listingId,
        CancellationToken cancellationToken)
    {
        var listing = await marketplace.GetListing(listingId, cancellationToken);

        if (listing == null)
        {
            return NotFound();
        }

        return Ok(listing);
    }

    [HttpGet("shops/{shopId:guid}/items")]
    public async Task<ActionResult<PagedResult<MarketplaceItemDTO>>> Storefront(
        Guid shopId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken cancellationToken = default)
    {
        var results = await marketplace.GetStorefront(
            shopId, new PageRequest(page, pageSize), cancellationToken);

        return Ok(results);
    }

    // filter dropdowns
    [HttpGet("classifications/area-countries")]
    public async Task<ActionResult<List<ClassificationOptionDTO>>> AreaCountries(
        CancellationToken cancellationToken)
    {
        return Ok(await marketplace.GetAreaCountries(cancellationToken));
    }

    [HttpGet("classifications/types")]
    public async Task<ActionResult<List<ClassificationOptionDTO>>> Types(
        CancellationToken cancellationToken)
    {
        return Ok(await marketplace.GetTypes(cancellationToken));
    }

    [HttpGet("classifications/types/{typeId:guid}/subtypes")]
    public async Task<ActionResult<List<ClassificationOptionDTO>>> Subtypes(
        Guid typeId,
        CancellationToken cancellationToken)
    {
        return Ok(await marketplace.GetSubtypes(typeId, cancellationToken));
    }

    [HttpGet("classifications/themes")]
    public async Task<ActionResult<List<ClassificationOptionDTO>>> Themes(
        CancellationToken cancellationToken)
    {
        return Ok(await marketplace.GetThemes(cancellationToken));
    }
}
