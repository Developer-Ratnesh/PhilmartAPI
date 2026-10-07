using Microsoft.EntityFrameworkCore;
using Philmart.Infrastructure.Persistence;

namespace Philmart.IntegrationTests.Support;

// Needs a database that database/migrate.sh has been run on. CI sets this up.
// Locally, set PHILMART_TEST_CONNECTION to a scratch database, not one you
// care about. The tests move its clock.
public class DatabaseFixture : IAsyncLifetime
{
    public DatabaseFixture()
    {
        string? connectionString = Environment.GetEnvironmentVariable("PHILMART_TEST_CONNECTION");
        if (string.IsNullOrEmpty(connectionString))
        {
            throw new InvalidOperationException("PHILMART_TEST_CONNECTION isn't set. Point it at a migrated test database.");
        }

        ConnectionString = connectionString;
        Clock = new TestClock(connectionString);
        Data = new TestData(connectionString);
        Api = new ApiFactory(connectionString);
    }

    public string ConnectionString { get; }

    public TestClock Clock { get; }

    public TestData Data { get; }

    public ApiFactory Api { get; }

    public async Task InitializeAsync()
    {
        await Clock.Reset();
        await Data.EnsureReferenceData();
    }

    public async Task DisposeAsync()
    {
        await Clock.Reset();
        await Api.DisposeAsync();
    }

    public IDbContextFactory<PhilmartContext> ContextFactory()
    {
        var options = new DbContextOptionsBuilder<PhilmartContext>()
            .UseSqlServer(ConnectionString)
            .Options;

        return new TestContextFactory(options);
    }
}

// no tenancy interceptor here, the tests connect as the migrator
public class TestContextFactory(DbContextOptions<PhilmartContext> options) : IDbContextFactory<PhilmartContext>
{
    public PhilmartContext CreateDbContext()
    {
        return new PhilmartContext(options);
    }
}

[CollectionDefinition("Database", DisableParallelization = true)]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
}
