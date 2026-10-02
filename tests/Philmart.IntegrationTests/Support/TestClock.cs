using Microsoft.Data.SqlClient;

namespace Philmart.IntegrationTests.Support;

// Deterministic test clock (task T06). Drives the single row in
// philmart.Sys_TestClock, which philmart.ServerNow() reads, so every rule that
// takes its time from the database moves when the test says so.
//
//   await clock.FreezeAt(new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero));
//   await clock.Advance(TimeSpan.FromDays(90));   // D063 expiry is now due
//
// The clock is one row for the whole database, so tests that use it run in
// the "Database" collection, which xunit never runs in parallel.
public class TestClock(string connectionString)
{
    public Task FreezeAt(DateTimeOffset instant)
    {
        return Execute(
            "UPDATE philmart.Sys_TestClock SET Enabled = 1, FrozenAt = @at, OffsetSeconds = 0 WHERE ID = 1;",
            new SqlParameter("@at", instant));
    }

    // Moves the clock by whole seconds, the resolution of OffsetSeconds.
    // Works whether the clock is frozen or running.
    public Task Advance(TimeSpan by)
    {
        if (by.Ticks % TimeSpan.TicksPerSecond != 0)
        {
            throw new ArgumentException("The test clock moves in whole seconds.", nameof(by));
        }

        return Execute(
            "UPDATE philmart.Sys_TestClock SET Enabled = 1, OffsetSeconds = OffsetSeconds + @seconds WHERE ID = 1;",
            new SqlParameter("@seconds", (long)by.TotalSeconds));
    }

    // Back to real server time. Call it from DisposeAsync so a failed test
    // never leaves a frozen clock behind for the next one.
    public Task Reset()
    {
        return Execute("UPDATE philmart.Sys_TestClock SET Enabled = 0, FrozenAt = NULL, OffsetSeconds = 0 WHERE ID = 1;");
    }

    public async Task<DateTimeOffset> Now()
    {
        using (var connection = new SqlConnection(connectionString))
        {
            await connection.OpenAsync();

            using (var cmd = new SqlCommand("SELECT philmart.ServerNow();", connection))
            {
                return (DateTimeOffset)(await cmd.ExecuteScalarAsync())!;
            }
        }
    }

    private async Task Execute(string sql, params SqlParameter[] parameters)
    {
        using (var connection = new SqlConnection(connectionString))
        {
            await connection.OpenAsync();

            using (var cmd = new SqlCommand(sql, connection))
            {
                cmd.Parameters.AddRange(parameters);

                if (await cmd.ExecuteNonQueryAsync() != 1)
                {
                    throw new InvalidOperationException("philmart.Sys_TestClock must hold exactly one row. Was migration 001 applied?");
                }
            }
        }
    }
}
