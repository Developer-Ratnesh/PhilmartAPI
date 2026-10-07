using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Philmart.Application.Abstractions;
using Philmart.Application.Support;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class SupportService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IEmailSender emailSender,
    ILogger<SupportService> logger) : ISupportService
{
    public async Task<List<SupportCategoryDTO>> GetCategories(CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            return await context.Database
                .SqlQuery<SupportCategoryDTO>($@"SELECT Value, ISNULL(Note, Value) AS Label FROM philmart.Sys_EnumValue
                                                WHERE EnumName = 'support_category' ORDER BY SortOrder")
                .ToListAsync(cancellationToken);
        }
    }

    public async Task<SupportReceiptDTO> Submit(SupportRequest request, CancellationToken cancellationToken = default)
    {
        string category = (request.Category ?? "").Trim();
        string subject = (request.Subject ?? "").Trim();
        string message = (request.Message ?? "").Trim();
        string? related = string.IsNullOrWhiteSpace(request.RelatedReference) ? null : request.RelatedReference.Trim();

        if (subject.Length == 0 || message.Length == 0)
        {
            throw new BusinessRuleViolationException("Please give your request a subject and a message.");
        }

        if (subject.Length > 400 || message.Length > 4000 || (related != null && related.Length > 60))
        {
            throw new BusinessRuleViolationException("That's too long. Keep the subject under 400 characters and the message under 4,000.");
        }

        Submitted saved;

        using (var context = contextFactory.CreateDbContext())
        {
            saved = await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                Guid? buyerId = tenant.IsBuyer ? tenant.ActorId : null;

                // the request has no Shop, and a visitor has no session to speak of
                await context.UseSystemSession(buyerId, cancellationToken);

                int known = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Sys_EnumValue WHERE EnumName = 'support_category' AND Value = {category}")
                    .SingleAsync(cancellationToken);

                if (known == 0)
                {
                    throw new BusinessRuleViolationException("Choose a category for your request.");
                }

                string name;
                string email;

                if (buyerId != null)
                {
                    var buyer = await context.Database
                        .SqlQuery<Contact>($"SELECT ISNULL(FullName, Email) AS Name, Email FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
                        .SingleAsync(cancellationToken);

                    name = buyer.Name;
                    email = buyer.Email;
                }
                else
                {
                    name = (request.ContactName ?? "").Trim();
                    email = (request.ContactEmail ?? "").Trim();

                    if (name.Length == 0 || email.Length == 0 || !email.Contains('@'))
                    {
                        throw new BusinessRuleViolationException("Tell us your name and an email address we can reply to.");
                    }

                    if (name.Length > 200 || email.Length > 256)
                    {
                        throw new BusinessRuleViolationException("Your name or email address is too long.");
                    }
                }

                // not composed (no First/Single), NEXT VALUE FOR isn't allowed in a subquery
                var stamps = await context.Database
                    .SqlQuery<Stamp>($"SELECT NEXT VALUE FOR philmart.SEQ_Sys_SupportRequest AS Number, philmart.ServerNow() AS Now")
                    .ToListAsync(cancellationToken);
                var stamp = stamps[0];

                string reference = "SUP-" + stamp.Now.Year + "-" + stamp.Number.ToString("D5");
                Guid id = Guid.NewGuid();

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sys_SupportRequest
                           (ID, Reference, Category, Subject, RelatedReference, Message, BuyerID, ContactName, ContactEmail, SubmittedAt)
                       VALUES ({id}, {reference}, {category}, {subject}, {related}, {message}, {buyerId}, {name}, {email}, {stamp.Now})",
                    cancellationToken);

                string actorKind = buyerId != null ? PhilmartConstants.ActorKind.Buyer : PhilmartConstants.ActorKind.Anonymous;
                await AuditSql.Add(context, buyerId, actorKind, null, "Sys_SupportRequest", id.ToString(),
                    "Sys_SupportRequest.submitted", new { Reference = reference, Category = category }, cancellationToken: cancellationToken);

                var result = new Submitted();
                result.Receipt = new SupportReceiptDTO { Reference = reference, SubmittedAt = stamp.Now };
                result.Name = name;
                result.Email = email;
                return result;
            }, cancellationToken);
        }

        await SendCopy(saved.Email, saved.Name, saved.Receipt.Reference, subject, cancellationToken);

        return saved.Receipt;
    }

    // The record is what counts, the email is only a copy (SCR-PUB-015), so a
    // failed send mustn't lose the request.
    private async Task SendCopy(string email, string name, string reference, string subject, CancellationToken cancellationToken)
    {
        if (!emailSender.IsConfigured)
        {
            return;
        }

        try
        {
            await emailSender.Send(email, "PHILMART support request " + reference,
                "Hello " + name + ",\n\n" +
                "We've received your support request \"" + subject + "\". Your reference is " + reference + ".\n\n" +
                "A support request doesn't pause any payment, invoice, delivery or auction deadline.\n",
                cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Couldn't email the copy of support request {Reference}", reference);
        }
    }

    private class Contact
    {
        public string Name { get; set; } = null!;

        public string Email { get; set; } = null!;
    }

    private class Submitted
    {
        public SupportReceiptDTO Receipt { get; set; } = null!;

        public string Name { get; set; } = null!;

        public string Email { get; set; } = null!;
    }

    private class Stamp
    {
        public int Number { get; set; }

        public DateTimeOffset Now { get; set; }
    }
}
