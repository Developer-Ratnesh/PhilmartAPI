namespace Philmart.Application.Auth;

// Buyers have no password, they get a 4-digit PIN by email instead. There's no
// table for PINs, so we send back a sealed challenge holding a hash of the PIN
// and the buyer returns it with the PIN they typed.
public interface IPinChallenges
{
    // purpose stops a registration PIN being used to sign in and the other way round
    PinChallenge Create(string purpose, string email, Guid? buyerId);

    // null if the PIN is wrong, the challenge has expired or too many tries were made
    PinChallengeResult? Verify(string purpose, string challenge, string pin);

    // false once an email has asked for too many PINs in the hour
    bool CanSend(string email);
}

public class PinChallenge
{
    public string Challenge { get; set; } = string.Empty;

    public string Pin { get; set; } = string.Empty;
}

public class PinChallengeResult
{
    public string Email { get; set; } = string.Empty;

    public Guid? BuyerID { get; set; }
}

public static class PinPurpose
{
    public const string Registration = "registration";
    public const string SignIn = "sign-in";
}

public class PinRequest
{
    public string Email { get; set; } = string.Empty;
}

public class PinChallengeDTO
{
    public string Challenge { get; set; } = string.Empty;
}

public class PinVerifyRequest
{
    public string Challenge { get; set; } = string.Empty;

    public string Pin { get; set; } = string.Empty;
}
