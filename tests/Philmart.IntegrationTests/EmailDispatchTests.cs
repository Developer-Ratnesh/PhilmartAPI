using Microsoft.Extensions.Logging.Abstractions;
using Philmart.Application.Abstractions;
using Philmart.Infrastructure.Email;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
public class EmailDispatchTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "BR-01-R02")]
    public async Task Queued_email_goes_out_once_and_is_marked_sent()
    {
        string to = "send-" + Guid.NewGuid().ToString("N") + "@test.local";
        Guid id = await Queue(to);

        var sender = new FakeSender();
        var dispatcher = new EmailDispatcher(db.ContextFactory(), sender, NullLogger<EmailDispatcher>.Instance);

        await dispatcher.SendQueued(10000);
        await dispatcher.SendQueued(10000);

        Assert.Equal(1, sender.Sent.Count(x => x == to));
        Assert.Equal("sent", await db.Data.Scalar<string>("SELECT DeliveryState FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE ID = @id AND SentAt IS NOT NULL", TestData.P("@id", id)));
    }

    [Fact]
    [Trait("BR", "BR-01-R02")]
    public async Task A_failing_address_is_retried_spaced_out_then_given_up_on()
    {
        await db.Clock.FreezeAt(DateTimeOffset.UtcNow);
        try
        {
            string to = "bounce-" + Guid.NewGuid().ToString("N") + "@test.local";
            Guid id = await Queue(to);

            var sender = new FakeSender { FailFor = to };
            var dispatcher = new EmailDispatcher(db.ContextFactory(), sender, NullLogger<EmailDispatcher>.Instance);

            await dispatcher.SendQueued(10000);
            Assert.Equal("queued", await State(id));
            Assert.Equal(1, await Attempts(id));

            // not again straight away: the next try waits
            await dispatcher.SendQueued(10000);
            Assert.Equal(1, await Attempts(id));

            // then 1, 5, 30 and 120 minutes after it was queued
            foreach (int minutes in new[] { 1, 5, 30, 120 })
            {
                await db.Clock.FreezeAt((await QueuedAt(id)).AddMinutes(minutes));
                await dispatcher.SendQueued(10000);
            }

            Assert.Equal(EmailDispatcher.MaxAttempts, await Attempts(id));
            Assert.Equal("failed", await State(id));
            Assert.NotNull(await db.Data.Scalar<string>("SELECT FailureDetail FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id)));

            // nothing more happens to it after that
            await db.Clock.Advance(TimeSpan.FromDays(1));
            await dispatcher.SendQueued(10000);
            Assert.Equal(EmailDispatcher.MaxAttempts, sender.Sent.Count(x => x == to));
        }
        finally
        {
            await db.Clock.Reset();
        }
    }

    // E.7 / S.5: the host answered 'Sender is throttled'. That's the server, not
    // the address, so one attempt is used and the rest of the batch waits.
    [Fact]
    [Trait("BR", "BR-01-R02")]
    public async Task A_throttled_mail_server_uses_one_attempt_not_the_whole_queue()
    {
        for (int i = 0; i < 3; i++)
        {
            await Queue("throttle-" + Guid.NewGuid().ToString("N") + "@test.local");
        }

        long before = await db.Data.Scalar<long>("SELECT ISNULL(SUM(CAST(Attempts AS BIGINT)), 0) FROM philmart.Sys_EmailMessage");

        var sender = new FakeSender { Throttled = true };
        var dispatcher = new EmailDispatcher(db.ContextFactory(), sender, NullLogger<EmailDispatcher>.Instance);
        Assert.Equal(0, await dispatcher.SendQueued(10000));

        Assert.Single(sender.Sent);
        Assert.Equal(before + 1, await db.Data.Scalar<long>("SELECT ISNULL(SUM(CAST(Attempts AS BIGINT)), 0) FROM philmart.Sys_EmailMessage"));
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE ToAddress LIKE 'throttle-%' AND DeliveryState = 'failed'"));

        // once the host lets us send again, they go (past the 1-minute wait
        // for the one that used its attempt)
        sender.Throttled = false;
        await db.Clock.FreezeAt(DateTimeOffset.UtcNow.AddMinutes(2));
        try
        {
            await dispatcher.SendQueued(10000);
        }
        finally
        {
            await db.Clock.Reset();
        }

        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE ToAddress LIKE 'throttle-%' AND DeliveryState <> 'sent'"));
    }

    private Task<int> Attempts(Guid id)
    {
        return db.Data.Scalar<int>("SELECT Attempts FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id));
    }

    private Task<DateTimeOffset> QueuedAt(Guid id)
    {
        return db.Data.Scalar<DateTimeOffset>("SELECT QueuedAt FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id));
    }

    [Fact]
    public async Task Nothing_is_sent_while_email_isnt_set_up()
    {
        string to = "unset-" + Guid.NewGuid().ToString("N") + "@test.local";
        Guid id = await Queue(to);

        var sender = new FakeSender { Configured = false };
        var dispatcher = new EmailDispatcher(db.ContextFactory(), sender, NullLogger<EmailDispatcher>.Instance);

        Assert.Equal(0, await dispatcher.SendQueued(10000));
        Assert.Equal("queued", await State(id));
    }

    private async Task<Guid> Queue(string to)
    {
        Guid id = Guid.NewGuid();
        await db.Data.Execute(@"INSERT INTO philmart.Sys_EmailMessage (ID, TemplateCode, ToAddress, Subject, Body)
                                VALUES (@id, 'EML-020', @to, N'Welcome', N'Welcome to PHILMART')",
            TestData.P("@id", id), TestData.P("@to", to));
        return id;
    }

    private Task<string?> State(Guid id)
    {
        return db.Data.Scalar<string>("SELECT DeliveryState FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id));
    }

    private class FakeSender : IEmailSender
    {
        public List<string> Sent { get; } = new List<string>();

        public string? FailFor { get; set; }

        public bool Configured { get; set; } = true;

        public bool Throttled { get; set; }

        public bool IsConfigured
        {
            get { return Configured; }
        }

        public Task Send(string to, string subject, string body, CancellationToken cancellationToken = default)
        {
            Sent.Add(to);

            if (Throttled)
            {
                throw new System.Net.Mail.SmtpException(System.Net.Mail.SmtpStatusCode.ServiceNotAvailable, "Sender is throttled");
            }

            if (to == FailFor)
            {
                throw new InvalidOperationException("mailbox unavailable");
            }

            return Task.CompletedTask;
        }
    }
}
