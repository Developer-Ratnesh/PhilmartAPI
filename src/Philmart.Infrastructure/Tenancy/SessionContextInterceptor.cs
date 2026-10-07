using System.Data;
using System.Data.Common;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;

namespace Philmart.Infrastructure.Tenancy;

// The database security rules read the caller's details from session context.
// That lives on the connection and pooled connections get cleared, so we set it
// every time one opens. Don't use read_only = 1 or the next request can't set it.
public class SessionContextInterceptor(ITenantContext tenant) : DbConnectionInterceptor
{
    public override void ConnectionOpened(DbConnection connection, ConnectionEndEventData eventData)
    {
        Set(connection, PhilmartConstants.SessionContext.ActorId, tenant.ActorId);
        Set(connection, PhilmartConstants.SessionContext.ShopId, tenant.ShopId);
        Set(connection, PhilmartConstants.SessionContext.ActorKind, tenant.ActorKind);

        base.ConnectionOpened(connection, eventData);
    }

    public override async Task ConnectionOpenedAsync(DbConnection connection, ConnectionEndEventData eventData, CancellationToken cancellationToken = default)
    {
        await SetAsync(connection, PhilmartConstants.SessionContext.ActorId, tenant.ActorId, cancellationToken);
        await SetAsync(connection, PhilmartConstants.SessionContext.ShopId, tenant.ShopId, cancellationToken);
        await SetAsync(connection, PhilmartConstants.SessionContext.ActorKind, tenant.ActorKind, cancellationToken);

        await base.ConnectionOpenedAsync(connection, eventData, cancellationToken);
    }

    private static void Set(DbConnection connection, string key, object? value)
    {
        using (var cmd = Build(connection, key, value))
        {
            cmd.ExecuteNonQuery();
        }
    }

    private static async Task SetAsync(DbConnection connection, string key, object? value, CancellationToken cancellationToken)
    {
        using (var cmd = Build(connection, key, value))
        {
            await cmd.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private static DbCommand Build(DbConnection connection, string key, object? value)
    {
        var cmd = connection.CreateCommand();
        cmd.CommandText = "EXEC sp_set_session_context @key, @value;";

        var keyParam = new SqlParameter("@key", SqlDbType.NVarChar, 128);
        keyParam.Value = key;

        var valueParam = new SqlParameter("@value", SqlDbType.Variant);
        valueParam.Value = value ?? (object)DBNull.Value;

        cmd.Parameters.Add(keyParam);
        cmd.Parameters.Add(valueParam);

        return cmd;
    }
}
