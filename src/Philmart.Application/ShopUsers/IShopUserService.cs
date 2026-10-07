namespace Philmart.Application.ShopUsers;

// BR-08. Permissions are given to each user directly, there are no roles (D050).
// The Shop always comes from the login token, never from the request.
public interface IShopUserService
{
    Task<List<ShopUserDTO>> List(CancellationToken cancellationToken = default);

    Task<List<PermissionDTO>> Catalogue(CancellationToken cancellationToken = default);

    Task<InviteResultDTO> Invite(InviteUserRequest request, CancellationToken cancellationToken = default);

    Task SetPermissions(Guid shopUserId, SetPermissionsRequest request, CancellationToken cancellationToken = default);

    // D049: access goes, history stays. Never a delete.
    Task Disable(Guid shopUserId, CancellationToken cancellationToken = default);

    Task Enable(Guid shopUserId, CancellationToken cancellationToken = default);

    Task AcceptInvitation(AcceptInvitationRequest request, CancellationToken cancellationToken = default);
}

public interface IInvitationTokens
{
    string Create(Guid shopUserId, string email);

    Guid? Read(string token, out string? email);
}
