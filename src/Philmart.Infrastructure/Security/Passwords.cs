using Microsoft.AspNetCore.Identity;

namespace Philmart.Infrastructure.Security;

// ASP.NET Identity's password hasher on its own, without the rest of Identity.
public static class Passwords
{
    private static readonly PasswordHasher<string> Hasher = new PasswordHasher<string>();

    public const int MinimumLength = 10;

    public static string Hash(string password)
    {
        return Hasher.HashPassword(string.Empty, password);
    }

    public static bool Matches(string? hash, string password)
    {
        if (string.IsNullOrEmpty(hash))
        {
            return false;
        }

        try
        {
            return Hasher.VerifyHashedPassword(string.Empty, hash, password) != PasswordVerificationResult.Failed;
        }
        catch (FormatException)
        {
            // a hash written by something else, treat it as no match
            return false;
        }
    }
}
