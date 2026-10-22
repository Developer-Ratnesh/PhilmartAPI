using System.Net.Mail;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Philmart.Application.Abstractions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Email;

// The email.dispatch job. The queued row is the record, sending is just output,
// so a failed send leaves the row there with the reason and tries again.
// Retries are spaced out from when the email was queued (at once, then 1, 5,
// 30 and 120 minutes), so a mail host that throttles us for a while (known
// issue KI-02, 'Sender is throttled') doesn't use up all five attempts at once.
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
                                         WHERE DeliveryState = 'queued' AND Attempts < {MaxAttempts}
                                           AND philmart.ServerNow() >= DATEADD(MINUTE, CASE Attempts WHEN 0 THEN 0 WHEN 1 THEN 1 WHEN 2 THEN 5 WHEN 3 THEN 30 ELSE 120 END, QueuedAt);

                                         SELECT ID, ToAddress, Subject, Body, Attempts FROM @claimed")
                .ToListAsync(cancellationToken);

            int sent = 0;

            for (int i = 0; i < batch.Count; i++)
            {
                var email = batch[i];

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

                    // The mail server refused us, not this one address (throttled,
                    // down, login failed). The rest would fail the same way, so give
                    // their attempt back and leave them for the next run.
                    if (ex is SmtpException && ex is not SmtpFailedRecipientException)
                    {
                        var rest = batch.Skip(i + 1).Select(x => x.ID).ToList();
                        foreach (Guid id in rest)
                        {
                            await context.Database.ExecuteSqlAsync(
                                $"UPDATE philmart.Sys_EmailMessage SET Attempts = Attempts - 1 WHERE ID = {id} AND DeliveryState = 'queued'",
                                cancellationToken);
                        }

                        break;
                    }
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
