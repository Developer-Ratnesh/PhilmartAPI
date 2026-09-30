using System.Security.Claims;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;

namespace Philmart.Api.Middleware;

// Everything here comes off the login token. Nothing is read from the URL, the
// body or a header. If we ever trusted a shop id sent by the browser, a user
// from one shop could read another shop's data.
public class TenantContext : ITenantContext
{
    public const string ShopIdClaim = "philmart:shop_id";
    public const string ActorKindClaim = "philmart:actor_kind";
    public const string PermissionClaim = "philmart:permission";

    private readonly List<string> permissions = new List<string>();

    public TenantContext(IHttpContextAccessor accessor)
    {
        var user = accessor.HttpContext?.User;

        if (user == null || user.Identity == null || !user.Identity.IsAuthenticated)
        {
            ActorKind = PhilmartConstants.ActorKind.Anonymous;
            return;
        }

        Guid actorId;

        if (Guid.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out actorId))
        {
            ActorId = actorId;
        }

        ActorKind = user.FindFirstValue(ActorKindClaim) ?? PhilmartConstants.ActorKind.Anonymous;

        Guid shopId;

        if (Guid.TryParse(user.FindFirstValue(ShopIdClaim), out shopId))
        {
            ShopId = shopId;
        }

        foreach (var claim in user.FindAll(PermissionClaim))
        {
            permissions.Add(claim.Value);
        }
    }

    public Guid? ActorId { get; private set; }

    public Guid? ShopId { get; private set; }

    public string ActorKind { get; private set; } = PhilmartConstants.ActorKind.Anonymous;

    public IReadOnlyCollection<string> Permissions
    {
        get { return permissions; }
    }

    public bool IsPlatformAdmin
    {
        get { return ActorKind == PhilmartConstants.ActorKind.PlatformAdmin; }
    }

    public bool IsShopUser
    {
        get { return ActorKind == PhilmartConstants.ActorKind.ShopUser; }
    }

    public bool IsBuyer
    {
        get { return ActorKind == PhilmartConstants.ActorKind.Buyer; }
    }

    public bool Has(string permission)
    {
        return permissions.Contains(permission);
    }
}
