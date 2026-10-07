using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Philmart.Infrastructure.Email;

// Every PHILMART email goes out in this one layout: logo, the message, and the
// same footer. Callers write plain text, this turns it into the HTML version.
// The logo is linked from the website, not attached. site4now's mail relay
// bounces any email with an embedded image.
// Colours are written out because mail apps ignore CSS variables and most
// ignore <style> blocks too.
public static class EmailLayout
{
    public const string LogoPath = "/brand/philmart-email-logo.png";

    private const string Navy = "#10294f";
    private const string Gold = "#d9a227";
    private const string Ivory = "#faf8f2";
    private const string Ink = "#1f2a3d";
    private const string Muted = "#6b7789";

    private static readonly Regex Link = new Regex(@"https?://[^\s<]+", RegexOptions.Compiled);
    private static readonly Regex Pin = new Regex(@"(PIN is )(\d{4})", RegexOptions.Compiled);

    public static string Html(string subject, string body, string logoUrl)
    {
        var html = new StringBuilder();

        html.Append("<!DOCTYPE html><html lang=\"en-ZA\"><head><meta charset=\"utf-8\">");
        html.Append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        html.Append("<title>").Append(WebUtility.HtmlEncode(subject)).Append("</title></head>");
        html.Append("<body style=\"margin:0;padding:0;background:").Append(Ivory).Append(";\">");

        html.Append("<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"background:").Append(Ivory).Append(";\"><tr><td align=\"center\" style=\"padding:24px 12px;\">");
        html.Append("<table role=\"presentation\" width=\"600\" cellpadding=\"0\" cellspacing=\"0\" style=\"max-width:600px;width:100%;background:#ffffff;border:1px solid #e3ddcc;border-radius:6px;\">");

        html.Append("<tr><td style=\"padding:24px 32px 16px 32px;border-bottom:3px solid ").Append(Gold).Append(";\">");
        html.Append("<img src=\"").Append(WebUtility.HtmlEncode(logoUrl)).Append("\" width=\"240\" height=\"80\" alt=\"PHILMART\" style=\"display:block;border:0;\">");
        html.Append("</td></tr>");

        html.Append("<tr><td style=\"padding:28px 32px 8px 32px;font-family:Georgia,'Times New Roman',serif;font-size:22px;font-weight:bold;color:").Append(Navy).Append(";\">");
        html.Append(WebUtility.HtmlEncode(subject));
        html.Append("</td></tr>");

        html.Append("<tr><td style=\"padding:8px 32px 28px 32px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.6;color:").Append(Ink).Append(";\">");
        foreach (string paragraph in Paragraphs(body))
        {
            html.Append("<p style=\"margin:0 0 16px 0;\">").Append(Format(paragraph)).Append("</p>");
        }
        html.Append("</td></tr>");

        html.Append("<tr><td style=\"padding:16px 32px;background:").Append(Navy).Append(";border-radius:0 0 6px 6px;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.5;color:#ffffff;\">");
        html.Append("<strong style=\"color:").Append(Gold).Append(";\">PHILMART</strong> &middot; South Africa&rsquo;s Philatelic Marketplace &amp; Auction House<br>");
        html.Append("<span style=\"color:#c9d3e3;\">This email was sent automatically, please don&rsquo;t reply to it. All values are in ZAR.</span>");
        html.Append("</td></tr>");

        html.Append("</table>");
        html.Append("<p style=\"margin:16px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:").Append(Muted).Append(";\">&copy; PHILMART</p>");
        html.Append("</td></tr></table></body></html>");

        return html.ToString();
    }

    // the plain version gets the same footer, for mail apps that don't show HTML
    public static string Text(string body)
    {
        return body.TrimEnd() + "\n\n--\nPHILMART - South Africa's Philatelic Marketplace & Auction House\n" +
               "This email was sent automatically, please don't reply to it.\n";
    }

    private static IEnumerable<string> Paragraphs(string body)
    {
        string normal = body.Replace("\r\n", "\n").Trim();
        return Regex.Split(normal, @"\n\s*\n").Where(x => x.Trim().Length > 0);
    }

    private static string Format(string paragraph)
    {
        string encoded = WebUtility.HtmlEncode(paragraph.Trim());

        // encoding leaves URLs readable, so links can be found after it
        encoded = Link.Replace(encoded, m =>
            "<a href=\"" + m.Value + "\" style=\"color:" + Navy + ";font-weight:bold;\">" + m.Value + "</a>");

        // the PIN is what the reader came for, so make it hard to miss
        encoded = Pin.Replace(encoded, m =>
            m.Groups[1].Value + "<span style=\"display:inline-block;padding:4px 12px;margin:0 2px;background:" + Ivory +
            ";border:1px solid " + Gold + ";border-radius:4px;font-size:22px;font-weight:bold;letter-spacing:6px;color:" + Navy + ";\">" +
            m.Groups[2].Value + "</span>");

        return encoded.Replace("\n", "<br>");
    }
}
