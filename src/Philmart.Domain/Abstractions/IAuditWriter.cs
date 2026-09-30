namespace Philmart.Domain.Abstractions;

// Sys_AuditEvent can only be added to. Write the audit row in the same
// transaction as the change or the two can get out of step.
public interface IAuditWriter
{
    Task Write(
        string entityTable,
        string entityId,
        string action,
        object? before = null,
        object? after = null,
        string? reason = null,
        CancellationToken cancellationToken = default);
}
