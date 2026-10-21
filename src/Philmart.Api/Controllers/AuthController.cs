using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.JsonWebTokens;
using Philmart.Api.Auth;
using Philmart.Application.Auth;

namespace Philmart.Api.Controllers;

[ApiController]
[Route("api/auth")]
[Produces("application/json")]
public class AuthController(IAuthService auth, TokenIssuer tokens) : ControllerBase
{
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<SignInResponse>> Login(SignInRequest request, CancellationToken cancellationToken)
    {
        var user = await auth.SignIn(request, cancellationToken);
        if (user == null)
        {
            return Unauthorized(new { status = 401, title = "Unauthorized", detail = "Email or password is wrong." });
        }

        return new SignInResponse { Token = tokens.Issue(user), User = user };
    }

    [HttpPost("buyer/pin")]
    [AllowAnonymous]
    [EnableRateLimiting(Program.PinLimit)]
    public Task<PinChallengeDTO> BuyerPin(PinRequest request, CancellationToken cancellationToken)
    {
        return auth.RequestBuyerPin(request.Email, cancellationToken);
    }

    [HttpPost("buyer/verify")]
    [AllowAnonymous]
    public async Task<ActionResult<SignInResponse>> BuyerVerify(PinVerifyRequest request, CancellationToken cancellationToken)
    {
        var user = await auth.SignInBuyerWithPin(request, cancellationToken);
        if (user == null)
        {
            return Unauthorized(new { status = 401, title = "Unauthorized", detail = "That PIN isn't right or has expired. Ask for a new one." });
        }

        return new SignInResponse { Token = tokens.Issue(user), User = user };
    }

    // N03: the token is refused from now on, not just forgotten by the browser
    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken)
    {
        string? tokenId = User.FindFirst(JwtRegisteredClaimNames.Jti)?.Value;
        long expires;

        if (tokenId != null && long.TryParse(User.FindFirst(JwtRegisteredClaimNames.Exp)?.Value, out expires))
        {
            await auth.SignOut(tokenId, DateTimeOffset.FromUnixTimeSeconds(expires), cancellationToken);
        }

        return NoContent();
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<ActionResult<SignedInUserDTO>> Me(CancellationToken cancellationToken)
    {
        var user = await auth.GetCurrent(cancellationToken);
        if (user == null)
        {
            return Unauthorized();
        }

        return user;
    }
}

public class SignInResponse
{
    public string Token { get; set; } = string.Empty;

    public SignedInUserDTO User { get; set; } = new SignedInUserDTO();
}
