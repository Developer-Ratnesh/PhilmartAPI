using System.Data;
using Microsoft.EntityFrameworkCore;
using Philmart.Domain.Constants;

namespace Philmart.Infrastructure.Persistence;

// Some work has to see across Shops, like the auction job and login lookups.
// Check permissions first, then switch the connection to 'system'. Migration
// 011 is what lets 'system' past the row security rules.
public static class SystemSession
{
    public static async Task UseSystemSession(this PhilmartContext context, Guid? actingFor, CancellationToken cancellationToken = default)
    {
        await context.Database.OpenConnectionAsync(cancellationToken);

        await SetKind(context, PhilmartConstants.ActorKind.System, cancellationToken);
        await context.Database.ExecuteSqlAsync(
            $"EXEC sp_set_session_context N'philmart.actor_id', {actingFor}", cancellationToken);
    }

    // For one write that has to be 'system' (usually the audit row) in the
    // middle of work that otherwise runs as the user. Puts the user back after.
    public static async Task AsSystem(this PhilmartContext context, string userKind, Func<Task> work, CancellationToken cancellationToken = default)
    {
        await SetKind(context, PhilmartConstants.ActorKind.System, cancellationToken);
        try
        {
            await work();
        }
        finally
        {
            await SetKind(context, userKind, cancellationToken);
        }
    }

    // EF only retries if the whole transaction runs inside its strategy, so it can
    // run the lot again. That's also how a bid that hits a deadlock gets retried.
    public static Task<T> InTransaction<T>(this PhilmartContext context, IsolationLevel isolation, Func<Task<T>> work, CancellationToken cancellationToken = default)
    {
        var strategy = context.Database.CreateExecutionStrategy();

        return strategy.ExecuteAsync(async () =>
        {
            using (var tx = await context.Database.BeginTransactionAsync(isolation, cancellationToken))
            {
                T result = await work();
                await tx.CommitAsync(cancellationToken);
                return result;
            }
        });
    }

    private static Task SetKind(PhilmartContext context, string kind, CancellationToken cancellationToken)
    {
        return context.Database.ExecuteSqlAsync(
            $"EXEC sp_set_session_context N'philmart.actor_kind', {kind}", cancellationToken);
    }
}
