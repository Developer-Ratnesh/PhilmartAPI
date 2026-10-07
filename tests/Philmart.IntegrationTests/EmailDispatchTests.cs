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
    public async Task A_failing_address_is_retried_then_given_up_on()
    {
        string to = "bounce-" + Guid.NewGuid().ToString("N") + "@test.local";
        Guid id = await Queue(to);

        var sender = new FakeSender { FailFor = to };
        var dispatcher = new EmailDispatcher(db.ContextFactory(), sender, NullLogger<EmailDispatcher>.Instance);

        await dispatcher.SendQueued(10000);
        Assert.Equal("queued", await State(id));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT Attempts FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id)));

        for (int i = 1; i < EmailDispatcher.MaxAttempts; i++)
        {
            await dispatcher.SendQueued(10000);
        }

        Assert.Equal("failed", await State(id));
        Assert.NotNull(await db.Data.Scalar<string>("SELECT FailureDetail FROM philmart.Sys_EmailMessage WHERE ID = @id", TestData.P("@id", id)));

        // nothing more happens to it after that
        await dispatcher.SendQueued(10000);
        Assert.Equal(EmailDispatcher.MaxAttempts, sender.Sent.Count(x => x == to));
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

        public bool IsConfigured
        {
            get { return Configured; }
        }

        public Task Send(string to, string subject, string body, CancellationToken cancellationToken = default)
        {
            Sent.Add(to);

            if (to == FailFor)
            {
                throw new InvalidOperationException("mailbox unavailable");
            }

            return Task.CompletedTask;
        }
    }
}
