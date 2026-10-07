using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Application.Abstractions;
using Philmart.Application.Account;
using Philmart.Application.Admin;
using Philmart.Application.Auctions;
using Philmart.Application.Auth;
using Philmart.Application.Commitments;
using Philmart.Application.Registration;
using Philmart.Application.ShopUsers;
using Philmart.Application.Items;
using Philmart.Application.Marketplace;
using Philmart.Application.Support;
using Philmart.Domain.Abstractions;
using Philmart.Infrastructure.Email;
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

        // A factory, so each service method opens its own context. It's scoped
        // because the interceptor carries the current request's user.
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
        }, ServiceLifetime.Scoped);

        services.AddScoped<IServerClock, ServerClock>();
        services.AddScoped<IAuditWriter, AuditWriter>();
        services.AddScoped<IItemService, ItemService>();
        services.AddScoped<IMarketplaceService, MarketplaceService>();
        services.AddScoped<IAdminOversightService, AdminOversightService>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IRegistrationService, RegistrationService>();
        services.AddScoped<ICommitmentService, CommitmentService>();
        services.AddScoped<IShopUserService, ShopUserService>();
        services.AddScoped<IAuctionService, AuctionService>();
        services.AddScoped<IAuctionCloser, AuctionCloser>();
        services.AddScoped<ISupportService, SupportService>();
        services.AddScoped<IBuyerListService, BuyerListService>();
        services.AddScoped<IEmailDispatcher, EmailDispatcher>();
        services.AddSingleton<IEmailSender, SmtpEmailSender>();

        return services;
    }
}
