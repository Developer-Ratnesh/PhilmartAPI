using Microsoft.IdentityModel.JsonWebTokens;
using Philmart.Application.Auth;
using Philmart.Domain.Abstractions;

namespace Philmart.Api.Middleware;

// Tokens live for hours. Without this a disabled user would keep working until
// theirs ran out, a permission taken away would still be honoured, and a
// signed-out token would still work.
public class AccountCheckMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context, ITenantContext tenant, IAuthService auth)
    {
        if (tenant.ActorId != null)
        {
            string? tokenId = context.User.FindFirst(JwtRegisteredClaimNames.Jti)?.Value;
            var access = await auth.CheckAccess(tenant.ActorKind, tenant.ActorId.Value, tenant.ShopId, tokenId, context.RequestAborted);

            if (!access.Allowed)
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new
                {
                    status = 401,
                    title = "Unauthorized",
                    detail = "Your account no longer has access. Please sign in again."
                });
                return;
            }

            ((TenantContext)tenant).UsePermissions(access.Permissions);
        }

        await next(context);
    }
}
