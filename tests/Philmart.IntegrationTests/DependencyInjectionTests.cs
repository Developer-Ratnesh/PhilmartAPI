using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Infrastructure;
using Philmart.Infrastructure.Persistence;

namespace Philmart.IntegrationTests;

public class DependencyInjectionTests
{
    // The context factory used to be a singleton and every database call came
    // back 500. Doesn't open a connection, so no database needed.
    [Fact]
    public void Context_factory_resolves_inside_a_request()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "ConnectionStrings:Philmart", "Server=unused;Database=unused;Trusted_Connection=True" }
            })
            .Build();

        var services = new ServiceCollection();
        services.AddScoped<ITenantContext, AnonymousTenant>();
        services.AddPhilmartInfrastructure(config);

        using (var provider = services.BuildServiceProvider(new ServiceProviderOptions { ValidateScopes = true }))
        using (var scope = provider.CreateScope())
        {
            var factory = scope.ServiceProvider.GetRequiredService<IDbContextFactory<PhilmartContext>>();

            using (var ctx = factory.CreateDbContext())
            {
                Assert.NotNull(ctx);
            }
        }
    }

    private class AnonymousTenant : ITenantContext
    {
        public Guid? ActorId { get; set; }

        public Guid? ShopId { get; set; }

        public string ActorKind { get; set; } = PhilmartConstants.ActorKind.Anonymous;

        public bool IsPlatformAdmin { get; set; }

        public bool IsShopUser { get; set; }

        public bool IsBuyer { get; set; }

        public IReadOnlyCollection<string> Permissions { get; set; } = new List<string>();

        public bool Has(string permission)
        {
            return false;
        }
    }
}
