using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Philmart.Application.Abstractions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Email;

// The email.dispatch job. The queued row is the record, sending is just output,
// so a failed send leaves the row there with the reason and tries again.
public class EmailDispatcher(
    IDbContextFactory<PhilmartContext> contextFactory,
    IEmailSender sender,
    ILogger<EmailDispatcher> logger) : IEmailDispatcher
{
    public const int MaxAttempts = 5;

    public async Task<int> SendQueued(int batchSize, CancellationToken cancellationToken = default)
    {
        if (!sender.IsConfigured)
        {
            return 0;
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(null, cancellationToken);

            // Claim first by bumping Attempts, so a second server running the same
            // job can't pick up the same rows. READPAST skips ones already claimed.
            // OUTPUT has to go INTO a table because Sys_EmailMessage has a trigger.
            // A pooled connection can still be Serializable from bidding, and
            // READPAST isn't allowed there, so set the level here.
            var batch = await context.Database
                .SqlQuery<QueuedEmail>($@"SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

                                         DECLARE @claimed TABLE (ID UNIQUEIDENTIFIER, ToAddress NVARCHAR(256), Subject NVARCHAR(400), Body NVARCHAR(MAX), Attempts INT);

                                         UPDATE TOP ({batchSize}) philmart.Sys_EmailMessage WITH (ROWLOCK, READPAST)
                                         SET Attempts = Attempts + 1
                                         OUTPUT inserted.ID, inserted.ToAddress, inserted.Subject, inserted.Body, inserted.Attempts INTO @claimed
                                         WHERE DeliveryState = 'queued' AND Attempts < {MaxAttempts};

                                         SELECT ID, ToAddress, Subject, Body, Attempts FROM @claimed")
                .ToListAsync(cancellationToken);

            int sent = 0;

            foreach (var email in batch)
            {
                try
                {
                    await sender.Send(email.ToAddress, email.Subject, email.Body, cancellationToken);

                    await context.Database.ExecuteSqlAsync(
                        $@"UPDATE philmart.Sys_EmailMessage
                           SET DeliveryState = 'sent', SentAt = philmart.ServerNow(), FailureCode = NULL, FailureDetail = NULL
                           WHERE ID = {email.ID}",
                        cancellationToken);

                    sent++;
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    string state = email.Attempts >= MaxAttempts ? "failed" : "queued";
                    string detail = ex.Message.Length > 1000 ? ex.Message.Substring(0, 1000) : ex.Message;

                    await context.Database.ExecuteSqlAsync(
                        $@"UPDATE philmart.Sys_EmailMessage
                           SET DeliveryState = {state}, FailureCode = {ex.GetType().Name}, FailureDetail = {detail}
                           WHERE ID = {email.ID}",
                        cancellationToken);

                    logger.LogWarning(ex, "Email {EmailID} to {To} failed, attempt {Attempt}", email.ID, email.ToAddress, email.Attempts);
                }
            }

            return sent;
        }
    }

    private class QueuedEmail
    {
        public Guid ID { get; set; }

        public string ToAddress { get; set; } = null!;

        public string Subject { get; set; } = null!;

        public string Body { get; set; } = null!;

        public int Attempts { get; set; }
    }
}
