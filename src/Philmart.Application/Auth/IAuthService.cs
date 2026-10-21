namespace Philmart.Application.Auth;

public interface IAuthService
{
    // Shop users and admins. Null for a wrong password or a disabled account,
    // without saying which, so nobody can use it to check who has an account.
    Task<SignedInUserDTO?> SignIn(SignInRequest request, CancellationToken cancellationToken = default);

    // Buyers (SCR-PUB-014). Always hands back a challenge, registered or not.
    Task<PinChallengeDTO> RequestBuyerPin(string email, CancellationToken cancellationToken = default);

    Task<SignedInUserDTO?> SignInBuyerWithPin(PinVerifyRequest request, CancellationToken cancellationToken = default);

    // only after something else has proved who they are, the registration PIN
    Task<SignedInUserDTO> ForBuyer(Guid buyerId, CancellationToken cancellationToken = default);

    Task<SignedInUserDTO?> GetCurrent(CancellationToken cancellationToken = default);

    // Run on every request. Permissions come from the database, not the token,
    // so a change or a disable takes effect straight away (D051, BR-08-R05).
    // A signed-out token is refused here too (N03).
    Task<AccessCheckDTO> CheckAccess(string actorKind, Guid actorId, Guid? shopId, string? tokenId, CancellationToken cancellationToken = default);

    // Sign out: the token stops working on the server, not just in the browser.
    Task SignOut(string tokenId, DateTimeOffset expiresAt, CancellationToken cancellationToken = default);
}
