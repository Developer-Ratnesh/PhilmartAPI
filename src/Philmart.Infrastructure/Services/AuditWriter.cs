using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class AuditWriter(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant) : IAuditWriter
{
    public async Task Write(
        string entityTable,
        string entityId,
        string action,
        object? before = null,
        object? after = null,
        string? reason = null,
        CancellationToken cancellationToken = default)
    {
        bool reasonIsRequired = PhilmartConstants.AuditAction.RequireReason.Contains(action);

        if (reasonIsRequired && string.IsNullOrWhiteSpace(reason))
        {
            throw new BusinessRuleViolationException(
                "The action '" + action + "' must have a reason written with it.");
        }

        string? beforeJson = ToJson(before);
        string? afterJson = ToJson(after);

        Guid? actorId = tenant.ActorId;
        string actorKind = tenant.ActorKind;
        Guid? shopId = tenant.ShopId;

        using (var context = contextFactory.CreateDbContext())
        {
            await context.Database.ExecuteSqlAsync(
                $@"INSERT INTO philmart.Sys_AuditEvent
                       (ActorID, ActorKind, ShopID, EntityTable, EntityID,
                        Action, Reason, BeforeValue, AfterValue)
                   VALUES
                       ({actorId}, {actorKind}, {shopId}, {entityTable}, {entityId},
                        {action}, {reason}, {beforeJson}, {afterJson})",
                cancellationToken);
        }
    }

    private static string? ToJson(object? value)
    {
        if (value == null)
        {
            return null;
        }

        return JsonSerializer.Serialize(value);
    }
}
