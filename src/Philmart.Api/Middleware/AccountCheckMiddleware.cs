using Philmart.Application.Auth;
using Philmart.Domain.Abstractions;

namespace Philmart.Api.Middleware;

// Tokens live for hours. Without this a disabled user would keep working until
// theirs ran out, and a permission taken away would still be honoured.
public class AccountCheckMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context, ITenantContext tenant, IAuthService auth)
    {
        if (tenant.ActorId != null)
        {
            var access = await auth.CheckAccess(tenant.ActorKind, tenant.ActorId.Value, tenant.ShopId, context.RequestAborted);

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
