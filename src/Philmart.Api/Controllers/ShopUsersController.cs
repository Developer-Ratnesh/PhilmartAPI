using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.ShopUsers;
using Philmart.Domain.Constants;

namespace Philmart.Api.Controllers;

// BR-08, SCR-SHP-012 Users and Permissions. No Shop ID in any route: it comes
// from the login token and nowhere else.
[ApiController]
[Authorize]
[Route("api/shop/users")]
[Produces("application/json")]
public class ShopUsersController(IShopUserService users) : ControllerBase
{
    [HttpGet]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersView)]
    public Task<List<ShopUserDTO>> List(CancellationToken cancellationToken)
    {
        return users.List(cancellationToken);
    }

    [HttpGet("permissions")]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersView)]
    public Task<List<PermissionDTO>> Permissions(CancellationToken cancellationToken)
    {
        return users.Catalogue(cancellationToken);
    }

    [HttpPost]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersManage)]
    public Task<InviteResultDTO> Invite(InviteUserRequest request, CancellationToken cancellationToken)
    {
        return users.Invite(request, cancellationToken);
    }

    [HttpPut("{shopUserId:guid}/permissions")]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersManage)]
    public async Task<IActionResult> SetPermissions(Guid shopUserId, SetPermissionsRequest request, CancellationToken cancellationToken)
    {
        await users.SetPermissions(shopUserId, request, cancellationToken);
        return NoContent();
    }

    [HttpPost("{shopUserId:guid}/disable")]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersManage)]
    public async Task<IActionResult> Disable(Guid shopUserId, CancellationToken cancellationToken)
    {
        await users.Disable(shopUserId, cancellationToken);
        return NoContent();
    }

    [HttpPost("{shopUserId:guid}/enable")]
    [RequiresPermission(PhilmartConstants.Permission.ShopUsersManage)]
    public async Task<IActionResult> Enable(Guid shopUserId, CancellationToken cancellationToken)
    {
        await users.Enable(shopUserId, cancellationToken);
        return NoContent();
    }

    [HttpPost("/api/shop/invitations/accept")]
    [AllowAnonymous]
    public async Task<IActionResult> AcceptInvitation(AcceptInvitationRequest request, CancellationToken cancellationToken)
    {
        await users.AcceptInvitation(request, cancellationToken);
        return NoContent();
    }
}
