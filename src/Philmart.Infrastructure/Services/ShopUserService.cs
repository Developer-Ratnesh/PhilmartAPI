using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Philmart.Application.Abstractions;
using Philmart.Application.ShopUsers;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Security;

namespace Philmart.Infrastructure.Services;

public class ShopUserService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IInvitationTokens invitations,
    IEmailSender emailSender,
    IConfiguration configuration,
    ILogger<ShopUserService> logger) : IShopUserService
{
    public async Task<List<ShopUserDTO>> List(CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            // The database hides other Shops anyway. Filter here too so we don't rely on that alone.
            var users = await context.Database
                .SqlQuery<UserRow>($@"SELECT ID, ShopID, Email, FullName, PasswordHash, IsAdministrator, DisabledAt
                                      FROM philmart.Shop_User WHERE ShopID = {shopId}")
                .ToListAsync(cancellationToken);

            var grants = await context.Database
                .SqlQuery<GrantRow>($"SELECT ShopUserID, PermissionCode FROM philmart.Shop_UserPermission WHERE ShopID = {shopId}")
                .ToListAsync(cancellationToken);

            var all = await Catalogue(context, cancellationToken);
            var result = new List<ShopUserDTO>();

            foreach (var u in users.OrderByDescending(x => x.IsAdministrator).ThenBy(x => x.FullName))
            {
                var dto = new ShopUserDTO();
                dto.ID = u.ID;
                dto.Email = u.Email;
                dto.FullName = u.FullName;
                dto.IsAdministrator = u.IsAdministrator;
                dto.Disabled = u.DisabledAt != null;
                dto.Pending = u.PasswordHash == null;

                // BR-08-R03: the administrator always has the full set
                dto.Permissions = u.IsAdministrator
                    ? all.Select(x => x.Code).ToList()
                    : grants.Where(x => x.ShopUserID == u.ID).Select(x => x.PermissionCode).OrderBy(x => x).ToList();

                result.Add(dto);
            }

            return result;
        }
    }

    public async Task<List<PermissionDTO>> Catalogue(CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            return await Catalogue(context, cancellationToken);
        }
    }

    public async Task<InviteResultDTO> Invite(InviteUserRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();
        string email = request.Email.Trim();
        string name = request.FullName.Trim();

        if (email.Length == 0 || !email.Contains('@') || name.Length == 0)
        {
            throw new BusinessRuleViolationException("Enter the new user's name and email address.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var codes = await CheckGrantable(context, request.Permissions, cancellationToken);

            Guid userId = await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                int existing = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Shop_User WHERE ShopID = {shopId} AND Email = {email}")
                    .FirstAsync(cancellationToken);

                if (existing > 0)
                {
                    throw new BusinessRuleViolationException("That email is already a user at your Shop.");
                }

                Guid id = Guid.NewGuid();
                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Shop_User (ID, ShopID, Email, FullName, IsAdministrator, InvitedAt, CreatedBy)
                       VALUES ({id}, {shopId}, {email}, {name}, 0, philmart.ServerNow(), {tenant.ActorId})",
                    cancellationToken);

                foreach (string code in codes)
                {
                    await Grant(context, id, shopId, code, cancellationToken);
                }

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Shop_User", id.ToString(),
                    "Shop_User.invited", new { Email = email, Permissions = codes }, cancellationToken: cancellationToken);

                return id;
            }, cancellationToken);

            string token = invitations.Create(userId, email);
            string baseUrl = configuration["Web:BaseUrl"] ?? "http://localhost:3000";
            string link = baseUrl.TrimEnd('/') + "/workspace/accept-invitation?token=" + Uri.EscapeDataString(token);

            // Invitations aren't in the email catalogue, so the link goes straight out
            // and the admin also sees it, in case the email doesn't arrive.
            if (emailSender.IsConfigured)
            {
                await emailSender.Send(email, "You've been invited to a PHILMART Shop",
                    "Hello " + name + ",\n\n" +
                    "You've been added as a user of a Shop on PHILMART. Open this link to set your password and sign in:\n\n" +
                    link + "\n\nThe link expires, so please use it soon.\n",
                    cancellationToken);
            }

            logger.LogInformation("Shop user {Email} invited. Invitation link: {Link}", email, link);

            return new InviteResultDTO { ShopUserID = userId, InvitationLink = link };
        }
    }

    public async Task SetPermissions(Guid shopUserId, SetPermissionsRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            var user = await LoadUser(context, shopId, shopUserId, cancellationToken);

            if (user.IsAdministrator)
            {
                throw new BusinessRuleViolationException("The Shop Administrator always has every permission. There's nothing to change.", "D050");
            }

            var wanted = await CheckGrantable(context, request.Permissions, cancellationToken);

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                var current = await context.Database
                    .SqlQuery<string>($"SELECT PermissionCode AS Value FROM philmart.Shop_UserPermission WHERE ShopUserID = {shopUserId} AND ShopID = {shopId}")
                    .ToListAsync(cancellationToken);

                var added = wanted.Except(current).ToList();
                var removed = current.Except(wanted).ToList();

                foreach (string code in added)
                {
                    await Grant(context, shopUserId, shopId, code, cancellationToken);
                }

                // 012: the only way a grant comes off, DELETE is denied elsewhere
                foreach (string code in removed)
                {
                    await context.Database.ExecuteSqlAsync(
                        $"EXEC philmart.P_Shop_UserPermission_Revoke {shopUserId}, {code}", cancellationToken);
                }

                // D051: one user changed, nobody else
                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Shop_User", shopUserId.ToString(),
                    "Shop_User.permissions_changed", new { Added = added, Removed = removed }, cancellationToken: cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    public async Task Disable(Guid shopUserId, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        if (shopUserId == tenant.ActorId)
        {
            throw new BusinessRuleViolationException("You can't disable your own account.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var user = await LoadUser(context, shopId, shopUserId, cancellationToken);

            if (user.IsAdministrator)
            {
                int admins = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Shop_User WHERE ShopID = {shopId} AND IsAdministrator = 1 AND DisabledAt IS NULL")
                    .FirstAsync(cancellationToken);

                if (admins <= 1)
                {
                    throw new BusinessRuleViolationException("A Shop needs at least one active administrator.", "D050");
                }
            }

            await SetDisabled(context, shopId, shopUserId, true, cancellationToken);
        }
    }

    public async Task Enable(Guid shopUserId, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            await LoadUser(context, shopId, shopUserId, cancellationToken);
            await SetDisabled(context, shopId, shopUserId, false, cancellationToken);
        }
    }

    public async Task AcceptInvitation(AcceptInvitationRequest request, CancellationToken cancellationToken = default)
    {
        string? email;
        Guid? userId = invitations.Read(request.Token, out email);

        if (userId == null)
        {
            throw new BusinessRuleViolationException("This invitation link isn't valid or has expired. Ask your Shop administrator for a new one.");
        }

        if (request.Password.Length < Passwords.MinimumLength)
        {
            throw new BusinessRuleViolationException("Your password needs at least " + Passwords.MinimumLength + " characters.");
        }

        string hash = Passwords.Hash(request.Password);

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(userId, cancellationToken);

            // only once, and not for a user who's been disabled since
            int rows = await context.Database.ExecuteSqlAsync(
                $@"UPDATE philmart.Shop_User
                      SET PasswordHash = {hash}, AcceptedAt = philmart.ServerNow(), UpdatedAt = philmart.ServerNow()
                    WHERE ID = {userId} AND Email = {email} AND PasswordHash IS NULL AND DisabledAt IS NULL",
                cancellationToken);

            if (rows == 0)
            {
                throw new BusinessRuleViolationException("This invitation has already been used. Sign in instead.");
            }
        }
    }

    private async Task SetDisabled(PhilmartContext context, Guid shopId, Guid shopUserId, bool disable, CancellationToken cancellationToken)
    {
        await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
        {
            await context.Database.OpenConnectionAsync(cancellationToken);

            if (disable)
            {
                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Shop_User SET DisabledAt = philmart.ServerNow(), UpdatedAt = philmart.ServerNow() WHERE ID = {shopUserId} AND ShopID = {shopId}",
                    cancellationToken);
            }
            else
            {
                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Shop_User SET DisabledAt = NULL, UpdatedAt = philmart.ServerNow() WHERE ID = {shopUserId} AND ShopID = {shopId}",
                    cancellationToken);
            }

            await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Shop_User", shopUserId.ToString(),
                disable ? "Shop_User.disabled" : "Shop_User.enabled", cancellationToken: cancellationToken);

            return true;
        }, cancellationToken);
    }

    private Guid RequireShop()
    {
        if (!tenant.IsShopUser || tenant.ShopId == null)
        {
            throw new NotAuthorisedException("Sign in as a Shop user to do this.");
        }

        return tenant.ShopId.Value;
    }

    // Not found, rather than forbidden, for another Shop's user. Saying it
    // exists elsewhere would leak something.
    private static async Task<UserRow> LoadUser(PhilmartContext context, Guid shopId, Guid shopUserId, CancellationToken cancellationToken)
    {
        var user = await context.Database
            .SqlQuery<UserRow>($@"SELECT ID, ShopID, Email, FullName, PasswordHash, IsAdministrator, DisabledAt
                                  FROM philmart.Shop_User WHERE ID = {shopUserId} AND ShopID = {shopId}")
            .FirstOrDefaultAsync(cancellationToken);

        if (user == null)
        {
            throw new NotFoundException("User", shopUserId);
        }

        return user;
    }

    private static async Task<List<string>> CheckGrantable(PhilmartContext context, List<string> requested, CancellationToken cancellationToken)
    {
        var all = await Catalogue(context, cancellationToken);
        var codes = requested.Select(x => x.Trim()).Where(x => x.Length > 0).Distinct().ToList();

        foreach (string code in codes)
        {
            var permission = all.FirstOrDefault(x => x.Code == code);
            if (permission == null)
            {
                throw new BusinessRuleViolationException("'" + code + "' isn't a permission.");
            }

            if (permission.AdminOnly)
            {
                throw new BusinessRuleViolationException("'" + permission.Name + "' belongs to the Shop Administrator only.", "D050");
            }
        }

        return codes;
    }

    private Task Grant(PhilmartContext context, Guid shopUserId, Guid shopId, string code, CancellationToken cancellationToken)
    {
        return context.Database.ExecuteSqlAsync(
            $"INSERT INTO philmart.Shop_UserPermission (ShopUserID, PermissionCode, ShopID, GrantedBy) VALUES ({shopUserId}, {code}, {shopId}, {tenant.ActorId})",
            cancellationToken);
    }

    private static Task<List<PermissionDTO>> Catalogue(PhilmartContext context, CancellationToken cancellationToken)
    {
        return context.Database
            .SqlQuery<PermissionDTO>($"SELECT Code, Name, Category, Description, AdminOnly FROM philmart.Sys_Permission ORDER BY Category, Name")
            .ToListAsync(cancellationToken);
    }

    private class UserRow
    {
        public Guid ID { get; set; }

        public Guid ShopID { get; set; }

        public string Email { get; set; } = null!;

        public string FullName { get; set; } = null!;

        public string? PasswordHash { get; set; }

        public bool IsAdministrator { get; set; }

        public DateTimeOffset? DisabledAt { get; set; }
    }

    private class GrantRow
    {
        public Guid ShopUserID { get; set; }

        public string PermissionCode { get; set; } = null!;
    }
}
