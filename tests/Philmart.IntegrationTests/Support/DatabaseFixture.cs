using Microsoft.EntityFrameworkCore;
using Philmart.Infrastructure.Persistence;

namespace Philmart.IntegrationTests.Support;

// A migrated PHILMART database. CI starts SQL Server and runs
// database/migrate.sh before the tests; locally, point the variable at any
// database you have migrated the same way:
//
//   PHILMART_TEST_CONNECTION="Server=localhost;Database=PhilmartTest;Trusted_Connection=True;TrustServerCertificate=True"
//
// Never point it at a database whose data you care about: tests move the clock.
public class DatabaseFixture
{
    public const string ConnectionVariable = "PHILMART_TEST_CONNECTION";

    public DatabaseFixture()
    {
        ConnectionString = Environment.GetEnvironmentVariable(ConnectionVariable)
            ?? throw new InvalidOperationException(
                $"{ConnectionVariable} is not set. Integration tests need a database migrated with database/migrate.sh.");

        Clock = new TestClock(ConnectionString);
    }

    public string ConnectionString { get; }

    public TestClock Clock { get; }

    public IDbContextFactory<PhilmartContext> ContextFactory()
    {
        var options = new DbContextOptionsBuilder<PhilmartContext>()
            .UseSqlServer(ConnectionString)
            .Options;

        return new PlainContextFactory(options);
    }
}

// Plain factory without the API's tenancy interceptor: these tests act as the
// migrator, not as a Shop user.
internal class PlainContextFactory(DbContextOptions<PhilmartContext> options) : IDbContextFactory<PhilmartContext>
{
    public PhilmartContext CreateDbContext() => new(options);
}

[CollectionDefinition("Database", DisableParallelization = true)]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
}
