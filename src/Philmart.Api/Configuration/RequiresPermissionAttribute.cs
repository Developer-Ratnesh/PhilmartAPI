using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Philmart.Domain.Abstractions;

namespace Philmart.Api.Configuration;

[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public class RequiresPermissionAttribute : Attribute, IAuthorizationFilter
{
    public RequiresPermissionAttribute(string permission)
    {
        Permission = permission;
    }

    public string Permission { get; private set; }

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var tenant = context.HttpContext.RequestServices.GetService<ITenantContext>();

        if (tenant == null || !tenant.Has(Permission))
        {
            var result = new ObjectResult(new
            {
                status = 403,
                title = "Forbidden",
                detail = "You need the '" + Permission + "' permission to do this."
            });

            result.StatusCode = StatusCodes.Status403Forbidden;

            context.Result = result;
        }
    }
}
