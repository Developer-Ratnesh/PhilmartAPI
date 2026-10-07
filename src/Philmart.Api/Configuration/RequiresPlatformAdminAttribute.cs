using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Philmart.Domain.Abstractions;

namespace Philmart.Api.Configuration;

// PHILMART admin isn't a Shop permission (D049). Only an admin login gets
// through here, no mix of Shop permissions will.
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public class RequiresPlatformAdminAttribute : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var tenant = context.HttpContext.RequestServices.GetService<ITenantContext>();

        if (tenant == null || !tenant.IsPlatformAdmin)
        {
            var result = new ObjectResult(new
            {
                status = 403,
                title = "Forbidden",
                detail = "Only a PHILMART administrator can do this."
            });

            result.StatusCode = StatusCodes.Status403Forbidden;

            context.Result = result;
        }
    }
}
