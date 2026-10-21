using System.Data;
using Microsoft.EntityFrameworkCore;
using Philmart.Application.Restrictions;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class BuyerRestrictionService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant) : IBuyerRestrictionService
{
    private const string LiftedAction = "Buy_Buyer.restriction_lifted";

    public async Task<List<BuyerRestrictionDTO>> List(CancellationToken cancellationToken = default)
    {
        Guid? shopId = RequireScope();

        using (var context = contextFactory.CreateDbContext())
        {
            // Buy_Buyer and the restriction rows sit behind RLS for a Shop user, and
            // the scope is checked above, so read as system and filter by Shop here
            await context.UseSystemSession(tenant.ActorId, cancellationToken);

            // a Shop user sees its own Shop's restrictions only; PHILMART sees all
            Guid filterShop = shopId ?? Guid.Empty;
            bool all = shopId == null;

            var rows = await context.Database
                .SqlQuery<BuyerRestrictionDTO>($@"SELECT r.ID, r.BuyerID, b.Email AS BuyerEmail, b.FullName AS BuyerName, r.Scope,
                                                         s.TradingName AS ShopName, r.Reason, r.ImposedAt, r.LiftedAt, r.LiftReason,
                                                         CAST(0 AS BIT) AS CanLift
                                                  FROM philmart.Buy_Restriction r
                                                  JOIN philmart.Buy_Buyer b ON b.ID = r.BuyerID
                                                  LEFT JOIN philmart.Shop_Shop s ON s.ID = r.ShopID
                                                  WHERE {all} = 1 OR r.ShopID = {filterShop}")
                .ToListAsync(cancellationToken);

            rows = rows.OrderBy(x => x.LiftedAt == null ? 0 : 1).ThenByDescending(x => x.ImposedAt).ToList();

            foreach (var row in rows)
            {
                row.CanLift = row.LiftedAt == null && OwnsScope(row.Scope, shopId);
            }

            return rows;
        }
    }

    public async Task<BuyerRestrictionDTO> Restrict(RestrictBuyerRequest request, CancellationToken cancellationToken = default)
    {
        Guid? shopId = RequireScope();
        string scope = shopId == null ? PhilmartConstants.RestrictionScope.Platform : PhilmartConstants.RestrictionScope.Shop;
        string email = (request.Email ?? string.Empty).Trim();
        string reason = CheckReason(request.Reason, "Give a reason for restricting this buyer.");

        if (email.Length == 0)
        {
            throw new BusinessRuleViolationException("Enter the buyer's email address.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(tenant.ActorId, cancellationToken);

            var buyerIds = await context.Database
                .SqlQuery<Guid>($"SELECT ID AS Value FROM philmart.Buy_Buyer WHERE Email = {email} AND RegistrationCompletedAt IS NOT NULL")
                .ToListAsync(cancellationToken);

            if (buyerIds.Count == 0)
            {
                throw new BusinessRuleViolationException("There's no registered buyer with that email address.");
            }

            Guid buyerId = buyerIds[0];
            Guid id = Guid.NewGuid();

            await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                Guid sameShop = shopId ?? Guid.Empty;
                int active = await context.Database
                    .SqlQuery<int>($@"SELECT COUNT(*) AS Value FROM philmart.Buy_Restriction
                                      WHERE BuyerID = {buyerId} AND Scope = {scope} AND LiftedAt IS NULL
                                        AND (ShopID IS NULL OR ShopID = {sameShop})")
                    .FirstAsync(cancellationToken);

                if (active > 0)
                {
                    throw new BusinessRuleViolationException("This buyer is already restricted.", "D044");
                }

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Buy_Restriction (ID, BuyerID, Scope, ShopID, Reason, ImposedBy)
                       VALUES ({id}, {buyerId}, {scope}, {shopId}, {reason}, {tenant.ActorId!.Value})",
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Buy_Buyer", buyerId.ToString(),
                    PhilmartConstants.AuditAction.BuyerRestricted, new { RestrictionID = id, Scope = scope }, reason, cancellationToken);

                return true;
            }, cancellationToken);

            var list = await List(cancellationToken);
            return list.First(x => x.ID == id);
        }
    }

    public async Task Lift(Guid restrictionId, LiftRestrictionRequest request, CancellationToken cancellationToken = default)
    {
        Guid? shopId = RequireScope();
        string reason = CheckReason(request.Reason, "Give a reason for lifting this restriction.");

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(tenant.ActorId, cancellationToken);

            var row = await context.Database
                .SqlQuery<RestrictionRow>($"SELECT BuyerID, Scope, ShopID, LiftedAt FROM philmart.Buy_Restriction WHERE ID = {restrictionId}")
                .FirstOrDefaultAsync(cancellationToken);

            // another Shop's restriction is reported as not found, like any other cross-Shop id
            if (row == null || (shopId != null && row.ShopID != shopId))
            {
                throw new NotFoundException("Restriction", restrictionId);
            }

            // D045: each side lifts only its own
            if (!OwnsScope(row.Scope, shopId))
            {
                throw new BusinessRuleViolationException(
                    shopId == null ? "A Shop's own restriction can only be lifted by that Shop." : "A PHILMART restriction can only be lifted by PHILMART.", "D045");
            }

            if (row.LiftedAt != null)
            {
                throw new BusinessRuleViolationException("This restriction has already been lifted.");
            }

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.ExecuteSqlAsync(
                    $@"UPDATE philmart.Buy_Restriction
                          SET LiftedAt = philmart.ServerNow(), LiftedBy = {tenant.ActorId!.Value}, LiftReason = {reason}
                        WHERE ID = {restrictionId} AND LiftedAt IS NULL",
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, row.ShopID, "Buy_Buyer", row.BuyerID.ToString(),
                    LiftedAction, new { RestrictionID = restrictionId, row.Scope }, reason, cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    // null = PHILMART (platform scope); otherwise the Shop the user belongs to
    private Guid? RequireScope()
    {
        if (tenant.IsPlatformAdmin)
        {
            return null;
        }

        if (tenant.IsShopUser && tenant.ShopId != null && tenant.Has(PhilmartConstants.Permission.BuyerRestrict))
        {
            return tenant.ShopId.Value;
        }

        throw new NotAuthorisedException("You don't have permission to restrict buyers.");
    }

    private static bool OwnsScope(string scope, Guid? shopId)
    {
        return shopId == null ? scope == PhilmartConstants.RestrictionScope.Platform : scope == PhilmartConstants.RestrictionScope.Shop;
    }

    private static string CheckReason(string? reason, string missing)
    {
        string why = (reason ?? string.Empty).Trim();

        if (why.Length == 0)
        {
            throw new BusinessRuleViolationException(missing, "D044");
        }

        if (why.Length > 1000)
        {
            throw new BusinessRuleViolationException("Keep the reason under 1000 characters.");
        }

        return why;
    }

    private class RestrictionRow
    {
        public Guid BuyerID { get; set; }

        public string Scope { get; set; } = null!;

        public Guid? ShopID { get; set; }

        public DateTimeOffset? LiftedAt { get; set; }
    }
}
