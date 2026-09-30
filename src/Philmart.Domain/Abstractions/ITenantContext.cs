namespace Philmart.Domain.Abstractions;

// Who is making the current request. All of it comes from the login token.
// A shop id sent by the browser proves nothing, never trust one.
public interface ITenantContext
{
    Guid? ActorId { get; }

    Guid? ShopId { get; }

    string ActorKind { get; }

    bool IsPlatformAdmin { get; }

    bool IsShopUser { get; }

    bool IsBuyer { get; }

    IReadOnlyCollection<string> Permissions { get; }

    bool Has(string permission);
}
