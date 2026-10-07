using Microsoft.Data.SqlClient;

namespace Philmart.IntegrationTests.Support;

// Moves the single row in philmart.Sys_TestClock that ServerNow() reads.
// It's shared by the whole database, so these tests run one at a time.
public class TestClock(string connectionString)
{
    public Task FreezeAt(DateTimeOffset at)
    {
        return Execute(
            "UPDATE philmart.Sys_TestClock SET Enabled = 1, FrozenAt = @at, OffsetSeconds = 0 WHERE ID = 1",
            new SqlParameter("@at", at));
    }

    public Task Advance(TimeSpan by)
    {
        // OffsetSeconds is whole seconds, half a second would just get lost
        if (by.Ticks % TimeSpan.TicksPerSecond != 0)
        {
            throw new ArgumentException("The test clock only moves in whole seconds.", nameof(by));
        }

        return Execute(
            "UPDATE philmart.Sys_TestClock SET Enabled = 1, OffsetSeconds = OffsetSeconds + @seconds WHERE ID = 1",
            new SqlParameter("@seconds", (long)by.TotalSeconds));
    }

    public Task Reset()
    {
        return Execute("UPDATE philmart.Sys_TestClock SET Enabled = 0, FrozenAt = NULL, OffsetSeconds = 0 WHERE ID = 1");
    }

    public async Task<DateTimeOffset> Now()
    {
        using (var conn = new SqlConnection(connectionString))
        {
            await conn.OpenAsync();

            using (var cmd = new SqlCommand("SELECT philmart.ServerNow()", conn))
            {
                object? result = await cmd.ExecuteScalarAsync();
                return (DateTimeOffset)result!;
            }
        }
    }

    private async Task Execute(string sql, params SqlParameter[] parameters)
    {
        using (var conn = new SqlConnection(connectionString))
        {
            await conn.OpenAsync();

            using (var cmd = new SqlCommand(sql, conn))
            {
                cmd.Parameters.AddRange(parameters);

                int rows = await cmd.ExecuteNonQueryAsync();
                if (rows != 1)
                {
                    throw new InvalidOperationException("Sys_TestClock has no row. Has 001_foundation been run on this database?");
                }
            }
        }
    }
}
