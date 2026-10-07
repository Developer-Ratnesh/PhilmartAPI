using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Philmart.Application.Abstractions;
using Philmart.Application.Auth;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Security;

namespace Philmart.Infrastructure.Services;

public class AuthService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IPinChallenges pins,
    IEmailSender emailSender,
    IConfiguration configuration,
    ILogger<AuthService> logger) : IAuthService
{
    // what a buyer has to have accepted, as published, before committing
    public static readonly string[] BuyerDocuments = new[] { "LEGAL-BUY-001", "LEGAL-AUC-001", "LEGAL-PRV-001" };

    public async Task<SignedInUserDTO?> SignIn(SignInRequest request, CancellationToken cancellationToken = default)
    {
        string email = request.Email.Trim();

        using (var context = contextFactory.CreateDbContext())
        {
            // Shop_User is behind RLS and nobody is signed in yet
            await context.UseSystemSession(null, cancellationToken);

            switch (request.Kind)
            {
                case SignInKind.Buyer:
                    throw new BusinessRuleViolationException("Buyers sign in with a PIN sent to their email.");

                case SignInKind.Shop:
                    return await SignInShopUser(context, email, request.Password, request.ShopReference, cancellationToken);

                case SignInKind.Admin:
                    return await SignInAdmin(context, email, request.Password, cancellationToken);

                default:
                    throw new BusinessRuleViolationException("Unknown login type '" + request.Kind + "'.");
            }
        }
    }

    public async Task<PinChallengeDTO> RequestBuyerPin(string email, CancellationToken cancellationToken = default)
    {
        email = email.Trim();

        if (email.Length == 0 || !email.Contains('@'))
        {
            throw new BusinessRuleViolationException("Enter your registered email address.");
        }

        if (!pins.CanSend(email))
        {
            throw new BusinessRuleViolationException("Too many PINs have been asked for. Please wait an hour and try again.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await context.Database
                .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, PasswordHash, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep, DisabledAt FROM philmart.Buy_Buyer WHERE Email = {email}")
                .FirstOrDefaultAsync(cancellationToken);

            bool canSignIn = buyer != null && buyer.DisabledAt == null && buyer.EmailVerifiedAt != null;
            var challenge = pins.Create(PinPurpose.SignIn, email, canSignIn ? buyer!.ID : null);

            // Unknown emails still get a challenge, it just never passes, so this can't be
            // used to find out who's registered. The sign-in PIN isn't in the email
            // catalogue, so it's sent straight out and never stored.
            if (canSignIn && emailSender.IsConfigured)
            {
                await emailSender.Send(email, "Your PHILMART sign-in PIN",
                    "Your sign-in PIN is " + challenge.Pin + ". It expires in 10 minutes.\n\n" +
                    "If you didn't try to sign in to PHILMART, you can ignore this email.\n",
                    cancellationToken);
            }

            if (canSignIn && configuration.GetValue("Auth:LogPins", false))
            {
                logger.LogInformation("Sign-in PIN for {Email}: {Pin}", email, challenge.Pin);
            }

            return new PinChallengeDTO { Challenge = challenge.Challenge };
        }
    }

    public async Task<SignedInUserDTO?> SignInBuyerWithPin(PinVerifyRequest request, CancellationToken cancellationToken = default)
    {
        var result = pins.Verify(PinPurpose.SignIn, request.Challenge, request.Pin);
        if (result?.BuyerID == null)
        {
            return null;
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await context.Database
                .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, PasswordHash, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep, DisabledAt FROM philmart.Buy_Buyer WHERE ID = {result.BuyerID}")
                .FirstOrDefaultAsync(cancellationToken);

            if (buyer == null || buyer.DisabledAt != null)
            {
                return null;
            }

            return await ToBuyerDto(context, buyer, cancellationToken);
        }
    }

    public async Task<SignedInUserDTO> ForBuyer(Guid buyerId, CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await context.Database
                .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, PasswordHash, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep, DisabledAt FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
                .FirstAsync(cancellationToken);

            return await ToBuyerDto(context, buyer, cancellationToken);
        }
    }

    public async Task<SignedInUserDTO?> GetCurrent(CancellationToken cancellationToken = default)
    {
        if (tenant.ActorId == null)
        {
            return null;
        }

        Guid id = tenant.ActorId.Value;

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(id, cancellationToken);

            if (tenant.IsBuyer)
            {
                var buyer = await context.Database
                    .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, PasswordHash, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep, DisabledAt FROM philmart.Buy_Buyer WHERE ID = {id}")
                    .FirstOrDefaultAsync(cancellationToken);

                return buyer == null ? null : await ToBuyerDto(context, buyer, cancellationToken);
            }

            if (tenant.IsShopUser)
            {
                var user = await context.Database
                    .SqlQuery<ShopUserRow>($@"SELECT u.ID, u.ShopID, s.Reference AS ShopReference, s.TradingName AS ShopName, u.Email, u.FullName,
                                                     u.PasswordHash, u.IsAdministrator, u.DisabledAt
                                              FROM philmart.Shop_User u JOIN philmart.Shop_Shop s ON s.ID = u.ShopID
                                              WHERE u.ID = {id}")
                    .FirstOrDefaultAsync(cancellationToken);

                return user == null ? null : await ToShopUserDto(context, user, cancellationToken);
            }

            if (tenant.IsPlatformAdmin)
            {
                var admin = await context.Database
                    .SqlQuery<AdminRow>($"SELECT ID, Email, FullName, PasswordHash, DisabledAt FROM philmart.Sys_PlatformUser WHERE ID = {id}")
                    .FirstOrDefaultAsync(cancellationToken);

                return admin == null ? null : ToAdminDto(admin);
            }

            return null;
        }
    }

    public async Task<AccessCheckDTO> CheckAccess(string actorKind, Guid actorId, Guid? shopId, CancellationToken cancellationToken = default)
    {
        var result = new AccessCheckDTO();

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(actorId, cancellationToken);

            if (actorKind == PhilmartConstants.ActorKind.ShopUser)
            {
                var user = await context.Database
                    .SqlQuery<ShopUserRow>($@"SELECT u.ID, u.ShopID, s.Reference AS ShopReference, s.TradingName AS ShopName, u.Email, u.FullName,
                                                     u.PasswordHash, u.IsAdministrator, u.DisabledAt
                                              FROM philmart.Shop_User u JOIN philmart.Shop_Shop s ON s.ID = u.ShopID
                                              WHERE u.ID = {actorId}")
                    .FirstOrDefaultAsync(cancellationToken);

                // a token for one Shop can't be replayed against another
                if (user == null || user.DisabledAt != null || user.ShopID != shopId)
                {
                    return result;
                }

                result.Allowed = true;
                result.Permissions = await LoadPermissions(context, user, cancellationToken);
                return result;
            }

            if (actorKind == PhilmartConstants.ActorKind.Buyer)
            {
                var disabled = await context.Database
                    .SqlQuery<DateTimeOffset?>($"SELECT DisabledAt AS Value FROM philmart.Buy_Buyer WHERE ID = {actorId}")
                    .ToListAsync(cancellationToken);

                result.Allowed = disabled.Count == 1 && disabled[0] == null;
                return result;
            }

            if (actorKind == PhilmartConstants.ActorKind.PlatformAdmin)
            {
                var disabled = await context.Database
                    .SqlQuery<DateTimeOffset?>($"SELECT DisabledAt AS Value FROM philmart.Sys_PlatformUser WHERE ID = {actorId}")
                    .ToListAsync(cancellationToken);

                result.Allowed = disabled.Count == 1 && disabled[0] == null;
                return result;
            }
        }

        return result;
    }

    private async Task<SignedInUserDTO?> SignInShopUser(PhilmartContext context, string email, string password, string? shopReference, CancellationToken cancellationToken)
    {
        var users = await context.Database
            .SqlQuery<ShopUserRow>($@"SELECT u.ID, u.ShopID, s.Reference AS ShopReference, s.TradingName AS ShopName, u.Email, u.FullName,
                                             u.PasswordHash, u.IsAdministrator, u.DisabledAt
                                      FROM philmart.Shop_User u JOIN philmart.Shop_Shop s ON s.ID = u.ShopID
                                      WHERE u.Email = {email} AND u.DisabledAt IS NULL")
            .ToListAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(shopReference))
        {
            users = users.Where(x => string.Equals(x.ShopReference, shopReference.Trim(), StringComparison.OrdinalIgnoreCase)).ToList();
        }

        var matches = users.Where(x => Passwords.Matches(x.PasswordHash, password)).ToList();

        if (matches.Count == 0)
        {
            return null;
        }

        if (matches.Count > 1)
        {
            throw new BusinessRuleViolationException("You're a user at more than one Shop. Enter the Shop reference to choose which one.");
        }

        return await ToShopUserDto(context, matches[0], cancellationToken);
    }

    private static async Task<SignedInUserDTO?> SignInAdmin(PhilmartContext context, string email, string password, CancellationToken cancellationToken)
    {
        var admin = await context.Database
            .SqlQuery<AdminRow>($"SELECT ID, Email, FullName, PasswordHash, DisabledAt FROM philmart.Sys_PlatformUser WHERE Email = {email}")
            .FirstOrDefaultAsync(cancellationToken);

        if (admin == null || admin.DisabledAt != null || !Passwords.Matches(admin.PasswordHash, password))
        {
            return null;
        }

        return ToAdminDto(admin);
    }

    private static async Task<SignedInUserDTO> ToBuyerDto(PhilmartContext context, BuyerRow buyer, CancellationToken cancellationToken)
    {
        var dto = new SignedInUserDTO();
        dto.ActorID = buyer.ID;
        dto.ActorKind = PhilmartConstants.ActorKind.Buyer;
        dto.Email = buyer.Email;
        dto.FullName = buyer.FullName;
        dto.EmailVerified = buyer.EmailVerifiedAt != null;
        dto.RegistrationStep = buyer.RegistrationCompletedAt == null ? buyer.RegistrationStep : null;

        if (buyer.RegistrationCompletedAt != null)
        {
            dto.PendingAcceptances = await PendingAcceptances(context, buyer.ID, cancellationToken);
        }

        return dto;
    }

    private static async Task<SignedInUserDTO> ToShopUserDto(PhilmartContext context, ShopUserRow user, CancellationToken cancellationToken)
    {
        var dto = new SignedInUserDTO();
        dto.ActorID = user.ID;
        dto.ActorKind = PhilmartConstants.ActorKind.ShopUser;
        dto.ShopID = user.ShopID;
        dto.ShopName = user.ShopName;
        dto.Email = user.Email;
        dto.FullName = user.FullName;
        dto.EmailVerified = true;
        dto.Permissions = await LoadPermissions(context, user, cancellationToken);
        return dto;
    }

    private static SignedInUserDTO ToAdminDto(AdminRow admin)
    {
        var dto = new SignedInUserDTO();
        dto.ActorID = admin.ID;
        dto.ActorKind = PhilmartConstants.ActorKind.PlatformAdmin;
        dto.Email = admin.Email;
        dto.FullName = admin.FullName;
        dto.EmailVerified = true;
        return dto;
    }

    // D050: the Shop Administrator always holds the full set. Everyone else
    // has exactly what was granted to them, nothing inherited.
    private static async Task<List<string>> LoadPermissions(PhilmartContext context, ShopUserRow user, CancellationToken cancellationToken)
    {
        if (user.IsAdministrator)
        {
            return await context.Database
                .SqlQuery<string>($"SELECT Code AS Value FROM philmart.Sys_Permission ORDER BY Code")
                .ToListAsync(cancellationToken);
        }

        return await context.Database
            .SqlQuery<string>($"SELECT PermissionCode AS Value FROM philmart.Shop_UserPermission WHERE ShopUserID = {user.ID} ORDER BY PermissionCode")
            .ToListAsync(cancellationToken);
    }

    public static async Task<List<string>> PendingAcceptances(PhilmartContext context, Guid buyerId, CancellationToken cancellationToken)
    {
        var pending = new List<string>();

        foreach (string code in BuyerDocuments)
        {
            // nothing published means nothing to accept yet
            var published = await context.Database
                .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Sys_LegalDocumentVersion WHERE DocumentCode = {code} AND PublishedAt IS NOT NULL AND SupersededAt IS NULL")
                .FirstAsync(cancellationToken);

            if (published == 0)
            {
                continue;
            }

            bool accepted = await context.Database
                .SqlQuery<bool>($"SELECT philmart.BuyerHasCurrentAcceptance({buyerId}, {code}) AS Value")
                .FirstAsync(cancellationToken);

            if (!accepted)
            {
                pending.Add(code);
            }
        }

        return pending;
    }

    private class BuyerRow
    {
        public Guid ID { get; set; }

        public string Email { get; set; } = null!;

        public string? FullName { get; set; }

        public string? PasswordHash { get; set; }

        public DateTimeOffset? EmailVerifiedAt { get; set; }

        public DateTimeOffset? RegistrationCompletedAt { get; set; }

        public byte RegistrationStep { get; set; }

        public DateTimeOffset? DisabledAt { get; set; }
    }

    private class ShopUserRow
    {
        public Guid ID { get; set; }

        public Guid ShopID { get; set; }

        public string ShopReference { get; set; } = null!;

        public string ShopName { get; set; } = null!;

        public string Email { get; set; } = null!;

        public string FullName { get; set; } = null!;

        public string? PasswordHash { get; set; }

        public bool IsAdministrator { get; set; }

        public DateTimeOffset? DisabledAt { get; set; }
    }

    private class AdminRow
    {
        public Guid ID { get; set; }

        public string Email { get; set; } = null!;

        public string FullName { get; set; } = null!;

        public string? PasswordHash { get; set; }

        public DateTimeOffset? DisabledAt { get; set; }
    }
}
