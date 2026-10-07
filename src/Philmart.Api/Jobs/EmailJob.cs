using Philmart.Application.Abstractions;

namespace Philmart.Api.Jobs;

public class EmailJob(IServiceScopeFactory scopes, IEmailSender sender, IConfiguration configuration, ILogger<EmailJob> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!sender.IsConfigured)
        {
            logger.LogWarning("Email:Host isn't set. Emails stay queued in Sys_EmailMessage until it is.");
            return;
        }

        int seconds = configuration.GetValue("Jobs:EmailSendSeconds", 10);
        logger.LogInformation("Email job running every {Seconds}s", seconds);

        using (var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds)))
        {
            do
            {
                try
                {
                    using (var scope = scopes.CreateScope())
                    {
                        var dispatcher = scope.ServiceProvider.GetRequiredService<IEmailDispatcher>();
                        int sent = await dispatcher.SendQueued(50, stoppingToken);

                        if (sent > 0)
                        {
                            logger.LogInformation("Sent {Count} emails", sent);
                        }
                    }
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogError(ex, "Email send run failed");
                }
            }
            while (await timer.WaitForNextTickAsync(stoppingToken));
        }
    }
}
