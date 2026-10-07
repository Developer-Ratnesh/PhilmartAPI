namespace Philmart.Application.ShopUsers;

public class ShopUserDTO
{
    public Guid ID { get; set; }

    public string Email { get; set; } = string.Empty;

    public string FullName { get; set; } = string.Empty;

    public bool IsAdministrator { get; set; }

    public bool Disabled { get; set; }

    // invited but hasn't set a password yet
    public bool Pending { get; set; }

    public List<string> Permissions { get; set; } = new List<string>();
}

public class PermissionDTO
{
    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string Category { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    // only a Shop Administrator holds these
    public bool AdminOnly { get; set; }
}

public class InviteUserRequest
{
    public string Email { get; set; } = string.Empty;

    public string FullName { get; set; } = string.Empty;

    public List<string> Permissions { get; set; } = new List<string>();
}

public class InviteResultDTO
{
    public Guid ShopUserID { get; set; }

    // the link the new user opens to set a password
    public string InvitationLink { get; set; } = string.Empty;
}

public class SetPermissionsRequest
{
    public List<string> Permissions { get; set; } = new List<string>();
}

public class AcceptInvitationRequest
{
    public string Token { get; set; } = string.Empty;

    public string Password { get; set; } = string.Empty;
}
