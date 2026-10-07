using Philmart.Infrastructure.Services;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
public class TestClockTests(DatabaseFixture database) : IAsyncLifetime
{
    private static readonly DateTimeOffset Morning = new DateTimeOffset(2026, 10, 1, 9, 0, 0, TimeSpan.Zero);

    public Task InitializeAsync()
    {
        return database.Clock.Reset();
    }

    // reset after as well, a failed test shouldn't leave the clock frozen
    public Task DisposeAsync()
    {
        return database.Clock.Reset();
    }

    [Fact]
    public async Task Frozen_clock_stays_put()
    {
        await database.Clock.FreezeAt(Morning);
        Assert.Equal(Morning, await database.Clock.Now());

        await Task.Delay(1100);
        Assert.Equal(Morning, await database.Clock.Now());
    }

    [Fact]
    public async Task Advance_moves_it_by_exactly_that_much()
    {
        await database.Clock.FreezeAt(Morning);

        await database.Clock.Advance(TimeSpan.FromDays(90));
        await database.Clock.Advance(TimeSpan.FromMinutes(2));

        Assert.Equal(Morning.AddDays(90).AddMinutes(2), await database.Clock.Now());
    }

    // This is the one that matters. If ServerClock ever stops going through
    // ServerNow(), none of the timing tests mean anything.
    [Fact]
    public async Task ServerClock_follows_the_test_clock()
    {
        await database.Clock.FreezeAt(Morning);

        var clock = new ServerClock(database.ContextFactory());

        Assert.Equal(Morning, await clock.Now());
    }

    [Fact]
    public async Task Reset_goes_back_to_real_time()
    {
        await database.Clock.FreezeAt(new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero));
        await database.Clock.Reset();

        DateTimeOffset now = await database.Clock.Now();

        Assert.True(now.Year > 2000, "still frozen after reset: " + now);
    }

    [Fact]
    public async Task Half_seconds_are_rejected()
    {
        await Assert.ThrowsAsync<ArgumentException>(() => database.Clock.Advance(TimeSpan.FromMilliseconds(500)));
    }
}
