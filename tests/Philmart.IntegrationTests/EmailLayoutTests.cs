using Microsoft.Extensions.Configuration;
using Philmart.Infrastructure.Email;

namespace Philmart.IntegrationTests;

// No database needed. Writes real emails to a folder and reads them back.
public class EmailLayoutTests
{
    [Fact]
    public void Body_text_is_escaped_and_laid_out()
    {
        string html = EmailLayout.Html("Your <PIN>", "Your sign-in PIN is 4321. It expires in 10 minutes.\n\nOpen https://philmart.test/x?a=1&b=2 now.\n<script>alert(1)</script>",
            "https://site.test/brand/philmart-email-logo.png");

        Assert.Contains("src=\"https://site.test/brand/philmart-email-logo.png\"", html);
        Assert.Contains("Your &lt;PIN&gt;", html);
        Assert.Contains("&lt;script&gt;", html);
        Assert.DoesNotContain("<script>", html);
        Assert.Contains(">4321</span>", html);
        Assert.Contains("href=\"https://philmart.test/x?a=1&amp;b=2\"", html);
        Assert.Contains("South Africa&rsquo;s Philatelic Marketplace", html);
    }

    [Fact]
    public async Task Every_email_goes_out_with_both_versions_and_no_attachment()
    {
        string folder = Path.Combine(Path.GetTempPath(), "philmart-mail-" + Guid.NewGuid().ToString("N"));

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Email:PickupDirectory", folder },
                { "Email:From", "noreply@philmart.test" },
                { "Web:BaseUrl", "https://site.test/" }
            })
            .Build();

        var sender = new SmtpEmailSender(config);
        Assert.True(sender.IsConfigured);

        await sender.Send("buyer@philmart.test", "Your PHILMART sign-in PIN", "Your sign-in PIN is 1234. It expires in 10 minutes.");

        try
        {
            string eml = await File.ReadAllTextAsync(Directory.GetFiles(folder, "*.eml").Single());

            Assert.Contains("multipart/alternative", eml);
            Assert.Contains("text/plain", eml);
            Assert.Contains("text/html", eml);
            Assert.Contains("From: \"PHILMART\" <noreply@philmart.test>", eml);
            Assert.Matches(@"Message-ID: <[0-9a-f]{32}@philmart\.test>", eml);

            // an attached image makes site4now's relay bounce the whole email
            Assert.DoesNotContain("image/png", eml);
            Assert.DoesNotContain("Content-ID", eml);
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }
}
