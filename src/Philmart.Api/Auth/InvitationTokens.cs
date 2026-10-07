using Microsoft.AspNetCore.DataProtection;
using Philmart.Application.ShopUsers;

namespace Philmart.Api.Auth;

// Signed, expiring links. Nothing is stored, the token carries the ID and the
// email and is only readable by this app.
public class SignedLink(IDataProtectionProvider provider, string purpose, TimeSpan lifetime)
{
    private readonly ITimeLimitedDataProtector protector =
        provider.CreateProtector(purpose).ToTimeLimitedDataProtector();

    public string Create(Guid id, string email)
    {
        return protector.Protect(id + "|" + email.ToLowerInvariant(), lifetime);
    }

    public Guid? Read(string token, out string? email)
    {
        email = null;

        try
        {
            string[] parts = protector.Unprotect(token).Split('|', 2);
            Guid id;

            if (parts.Length != 2 || !Guid.TryParse(parts[0], out id))
            {
                return null;
            }

            email = parts[1];
            return id;
        }
        catch (System.Security.Cryptography.CryptographicException)
        {
            // forged, tampered with or expired
            return null;
        }
    }
}

public class InvitationTokens(IDataProtectionProvider provider)
    : SignedLink(provider, "Philmart.ShopUserInvitation", TimeSpan.FromDays(7)), IInvitationTokens
{
}
