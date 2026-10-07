using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Philmart.Api.Middleware;
using Philmart.Application.Auth;

namespace Philmart.Api.Auth;

// The token says who you are and which Shop. It doesn't carry permissions,
// those are read fresh on every request (see AccountCheckMiddleware).
public class TokenIssuer(AuthSettings settings)
{
    public string Issue(SignedInUserDTO user)
    {
        var claims = new List<Claim>();
        claims.Add(new Claim(JwtRegisteredClaimNames.Sub, user.ActorID.ToString()));
        claims.Add(new Claim(JwtRegisteredClaimNames.Email, user.Email));
        claims.Add(new Claim(TenantContext.ActorKindClaim, user.ActorKind));

        if (user.ShopID != null)
        {
            claims.Add(new Claim(TenantContext.ShopIdClaim, user.ShopID.Value.ToString()));
        }

        var descriptor = new SecurityTokenDescriptor();
        descriptor.Issuer = settings.Issuer;
        descriptor.Audience = settings.Audience;
        descriptor.Subject = new ClaimsIdentity(claims);
        descriptor.Expires = DateTime.UtcNow.AddMinutes(settings.LifetimeMinutes);
        descriptor.SigningCredentials = new SigningCredentials(settings.Key(), SecurityAlgorithms.HmacSha256);

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }
}

public class AuthSettings
{
    public string Issuer { get; set; } = "philmart";

    public string Audience { get; set; } = "philmart-web";

    public string SigningKey { get; set; } = string.Empty;

    public int LifetimeMinutes { get; set; } = 480;

    public SymmetricSecurityKey Key()
    {
        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey));
    }
}
