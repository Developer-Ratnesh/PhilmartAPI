using System.Net;
using System.Net.Mail;
using System.Net.Mime;
using System.Text;
using Microsoft.Extensions.Configuration;
using Philmart.Application.Abstractions;

namespace Philmart.Infrastructure.Email;

public class SmtpEmailSender(IConfiguration configuration) : IEmailSender
{
    // Email:PickupDirectory writes each email to a .eml file instead of sending
    // it. Handy for testing, never set it on a live server.
    public bool IsConfigured
    {
        get { return !string.IsNullOrWhiteSpace(configuration["Email:Host"]) || !string.IsNullOrWhiteSpace(configuration["Email:PickupDirectory"]); }
    }

    public async Task Send(string to, string subject, string body, CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            throw new InvalidOperationException("Email:Host isn't set, so there's no way to send email.");
        }

        string from = configuration["Email:From"] ?? throw new InvalidOperationException("Email:From isn't set.");

        string site = (configuration["Web:BaseUrl"] ?? "http://localhost:3000").TrimEnd('/');

        using (var message = new MailMessage())
        {
            message.From = new MailAddress(from, configuration["Email:FromName"] ?? "PHILMART");
            message.To.Add(to);

            // SmtpClient doesn't add a Message-ID, and mail without one tends to land in spam
            message.Headers.Add("Message-ID", "<" + Guid.NewGuid().ToString("N") + "@" + message.From.Host + ">");
            message.Subject = subject;
            message.SubjectEncoding = Encoding.UTF8;

            // plain text first, mail apps show the last version they can handle
            var plain = AlternateView.CreateAlternateViewFromString(EmailLayout.Text(body), Encoding.UTF8, MediaTypeNames.Text.Plain);
            var html = AlternateView.CreateAlternateViewFromString(EmailLayout.Html(subject, body, site + EmailLayout.LogoPath), Encoding.UTF8, MediaTypeNames.Text.Html);

            message.AlternateViews.Add(plain);
            message.AlternateViews.Add(html);

            using (var client = CreateClient())
            {
                await client.SendMailAsync(message, cancellationToken);
            }
        }
    }

    private SmtpClient CreateClient()
    {
        string? pickup = configuration["Email:PickupDirectory"];
        if (!string.IsNullOrWhiteSpace(pickup))
        {
            Directory.CreateDirectory(pickup);
            var local = new SmtpClient();
            local.DeliveryMethod = SmtpDeliveryMethod.SpecifiedPickupDirectory;
            local.PickupDirectoryLocation = Path.GetFullPath(pickup);
            return local;
        }

        var client = new SmtpClient(configuration["Email:Host"], configuration.GetValue("Email:Port", 587));
        client.EnableSsl = configuration.GetValue("Email:EnableSsl", true);

        string? user = configuration["Email:UserName"];
        if (!string.IsNullOrEmpty(user))
        {
            client.Credentials = new NetworkCredential(user, configuration["Email:Password"]);
        }

        return client;
    }
}
