using Philmart.Application.Auctions;

namespace Philmart.Api.Jobs;

// Opens auctions that are due and closes ones that have ended. The first run at
// startup catches up on anything missed while the server was down. Closing a
// few seconds late is fine, the database refuses bids after the end time anyway.
public class AuctionJob(IServiceScopeFactory scopes, IConfiguration configuration, ILogger<AuctionJob> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        int seconds = configuration.GetValue("Jobs:AuctionSweepSeconds", 5);
        logger.LogInformation("Auction job running every {Seconds}s", seconds);

        using (var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds)))
        {
            do
            {
                try
                {
                    using (var scope = scopes.CreateScope())
                    {
                        var closer = scope.ServiceProvider.GetRequiredService<IAuctionCloser>();
                        var result = await closer.Sweep(stoppingToken);

                        if (result.Opened + result.Sold + result.Unsold > 0)
                        {
                            logger.LogInformation("Auctions: {Opened} opened, {Sold} sold, {Unsold} unsold", result.Opened, result.Sold, result.Unsold);
                        }
                    }
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // database down or similar, keep going and try next tick
                    logger.LogError(ex, "Auction sweep failed");
                }
            }
            while (await timer.WaitForNextTickAsync(stoppingToken));
        }
    }
}
