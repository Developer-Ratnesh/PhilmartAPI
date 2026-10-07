using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;

namespace Philmart.Infrastructure.Persistence;

// Writes the audit row on the caller's connection, so it lands in the same
// transaction as the change it describes.
public static class AuditSql
{
    public static Task Add(
        PhilmartContext context,
        Guid? actorId,
        string actorKind,
        Guid? shopId,
        string entityTable,
        string entityId,
        string action,
        object? after = null,
        string? reason = null,
        CancellationToken cancellationToken = default)
    {
        if (PhilmartConstants.AuditAction.RequireReason.Contains(action) && string.IsNullOrWhiteSpace(reason))
        {
            throw new BusinessRuleViolationException("'" + action + "' needs a reason.");
        }

        string? afterJson = after == null ? null : JsonSerializer.Serialize(after);

        return context.Database.ExecuteSqlAsync(
            $@"INSERT INTO philmart.Sys_AuditEvent
                   (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, Reason, AfterValue)
               VALUES
                   ({actorId}, {actorKind}, {shopId}, {entityTable}, {entityId}, {action}, {reason}, {afterJson})",
            cancellationToken);
    }
}
