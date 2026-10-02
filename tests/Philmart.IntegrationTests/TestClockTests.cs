using Philmart.Infrastructure.Services;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// T06: the harness itself, and proof that the application's IServerClock
// follows it. If ServerClock ever stops reading philmart.ServerNow() these fail.
[Collection("Database")]
public class TestClockTests(DatabaseFixture database) : IAsyncLifetime
{
    private static readonly DateTimeOffset Morning = new(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);

    public Task InitializeAsync() => database.Clock.Reset();

    public Task DisposeAsync() => database.Clock.Reset();

    [Fact]
    public async Task Frozen_clock_returns_exactly_the_frozen_time()
    {
        await database.Clock.FreezeAt(Morning);

        Assert.Equal(Morning, await database.Clock.Now());

        // frozen means frozen, not "close to"
        await Task.Delay(1100);
        Assert.Equal(Morning, await database.Clock.Now());
    }

    [Fact]
    public async Task Advance_moves_a_frozen_clock_by_exactly_that_much()
    {
        await database.Clock.FreezeAt(Morning);

        await database.Clock.Advance(TimeSpan.FromDays(90));
        await database.Clock.Advance(TimeSpan.FromMinutes(2));

        Assert.Equal(Morning.AddDays(90).AddMinutes(2), await database.Clock.Now());
    }

    [Fact]
    public async Task Application_clock_reads_the_test_clock()
    {
        await database.Clock.FreezeAt(Morning);

        var serverClock = new ServerClock(database.ContextFactory());

        Assert.Equal(Morning, await serverClock.Now());
    }

    [Fact]
    public async Task Reset_goes_back_to_real_server_time()
    {
        var longAgo = new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero);
        await database.Clock.FreezeAt(longAgo);
        await database.Clock.Reset();

        var now = await database.Clock.Now();

        Assert.True(now.Year > 2000, $"Expected real time after reset, got {now:O}");
    }

    [Fact]
    public async Task Clock_moves_in_whole_seconds()
    {
        await Assert.ThrowsAsync<ArgumentException>(() => database.Clock.Advance(TimeSpan.FromMilliseconds(500)));
    }
}
