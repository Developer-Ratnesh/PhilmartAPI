using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Philmart.Infrastructure.Persistence;

// Puts an email in the queue. Something else does the sending. The database
// rejects retired templates, so a wrong code fails here.
public static class EmailSql
{
    public static async Task Queue(
        PhilmartContext context,
        string templateCode,
        string to,
        Guid? buyerId,
        Guid? shopId,
        string subject,
        string body,
        object? data = null,
        CancellationToken cancellationToken = default)
    {
        // The client hasn't given us the email wording yet. Once they do, theirs is used.
        var template = await context.Database
            .SqlQuery<TemplateText>($"SELECT SubjectTemplate, BodyTemplate FROM philmart.Sys_EmailTemplate WHERE Code = {templateCode}")
            .FirstOrDefaultAsync(cancellationToken);

        var values = data == null
            ? new Dictionary<string, string>()
            : JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(JsonSerializer.Serialize(data))!
                .ToDictionary(x => x.Key, x => x.Value.ToString());

        if (template != null && !string.IsNullOrWhiteSpace(template.SubjectTemplate) && !string.IsNullOrWhiteSpace(template.BodyTemplate))
        {
            subject = Fill(template.SubjectTemplate, values);
            body = Fill(template.BodyTemplate, values);
        }

        string? json = data == null ? null : JsonSerializer.Serialize(data);

        await context.Database.ExecuteSqlAsync(
            $@"INSERT INTO philmart.Sys_EmailMessage (TemplateCode, ShopID, ToAddress, BuyerID, Subject, Body, Context)
               VALUES ({templateCode}, {shopId}, {to}, {buyerId}, {subject}, {body}, {json})",
            cancellationToken);
    }

    private static string Fill(string text, Dictionary<string, string> values)
    {
        foreach (var x in values)
        {
            text = text.Replace("{{" + x.Key + "}}", x.Value);
        }

        return text;
    }

    private class TemplateText
    {
        public string? SubjectTemplate { get; set; }

        public string? BodyTemplate { get; set; }
    }
}
