namespace Philmart.Application.Auth;

public static class SignInKind
{
    public const string Buyer = "buyer";
    public const string Shop = "shop";
    public const string Admin = "admin";
}

public class SignInRequest
{
    public string Email { get; set; } = string.Empty;

    public string Password { get; set; } = string.Empty;

    // buyer, shop or admin. Login screens are separate so the user always knows
    // which one they're on.
    public string Kind { get; set; } = SignInKind.Buyer;

    // only when the same email is a user at more than one Shop
    public string? ShopReference { get; set; }
}

public class SignedInUserDTO
{
    public Guid ActorID { get; set; }

    public string ActorKind { get; set; } = string.Empty;

    public Guid? ShopID { get; set; }

    public string? ShopName { get; set; }

    public string Email { get; set; } = string.Empty;

    public string? FullName { get; set; }

    public List<string> Permissions { get; set; } = new List<string>();

    // buyers only. 1 to 4 while registering, null once complete.
    public int? RegistrationStep { get; set; }

    public bool EmailVerified { get; set; }

    // BR-01-R09: documents superseded since the buyer last accepted them.
    // Buy Now and Confirm Bid are refused until these are accepted again.
    public List<string> PendingAcceptances { get; set; } = new List<string>();
}

public class AccessCheckDTO
{
    public bool Allowed { get; set; }

    public List<string> Permissions { get; set; } = new List<string>();
}
