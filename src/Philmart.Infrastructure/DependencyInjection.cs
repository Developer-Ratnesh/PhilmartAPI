using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Application.Items;
using Philmart.Application.Marketplace;
using Philmart.Domain.Abstractions;
using Philmart.Infrastructure.Persistence;
using Philmart.Infrastructure.Services;
using Philmart.Infrastructure.Tenancy;

namespace Philmart.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddPhilmartInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddScoped<SessionContextInterceptor>();

        // factory not a shared context, each service method opens its own
        services.AddDbContextFactory<PhilmartContext>((provider, options) =>
        {
            string? connectionString = configuration.GetConnectionString("Philmart");

            options.UseSqlServer(connectionString, sql =>
            {
                // 1205 is the deadlock victim, bidding hits it under load
                sql.EnableRetryOnFailure(
                    5,
                    TimeSpan.FromSeconds(5),
                    new[] { 1205 });

                sql.CommandTimeout(60);
            });

            options.AddInterceptors(provider.GetRequiredService<SessionContextInterceptor>());

            options.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
        });

        services.AddScoped<IServerClock, ServerClock>();
        services.AddScoped<IAuditWriter, AuditWriter>();
        services.AddScoped<IItemService, ItemService>();
        services.AddScoped<IMarketplaceService, MarketplaceService>();

        return services;
    }
}
