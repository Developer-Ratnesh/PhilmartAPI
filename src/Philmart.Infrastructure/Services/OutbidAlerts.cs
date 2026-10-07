using Microsoft.EntityFrameworkCore;
using Philmart.Domain.Constants;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

// D068: EML-013 to the bidder who just lost the lead. At most one every 4
// hours and 3 in 24 hours, per buyer per auction. This only ever decides
// whether an email goes. It never touches the bid.
internal static class OutbidAlerts
{
    public static async Task Send(PhilmartContext context, Guid listingId, Guid shopId, Guid buyerId, string itemTitle, CancellationToken cancellationToken)
    {
        // D040: the one email a buyer can switch off. No row means they never touched it.
        bool optedOut = await context.Database
            .SqlQuery<int>($@"SELECT COUNT(*) AS Value FROM philmart.Buy_CommunicationPreference
                              WHERE BuyerID = {buyerId} AND EmailCode = {PhilmartConstants.Email.OutbidAlert} AND Enabled = 0")
            .FirstAsync(cancellationToken) > 0;

        if (optedOut)
        {
            return;
        }

        var recent = await context.Database
            .SqlQuery<DateTimeOffset>($@"SELECT SentAt AS Value FROM philmart.List_OutbidAlertLog
                                        WHERE BuyerID = {buyerId} AND ListingID = {listingId} AND Suppressed = 0
                                          AND SentAt > DATEADD(HOUR, -24, philmart.ServerNow())")
            .ToListAsync(cancellationToken);

        var now = await context.Database
            .SqlQuery<DateTimeOffset>($"SELECT philmart.ServerNow() AS Value")
            .FirstAsync(cancellationToken);

        string? suppressReason = null;

        if (recent.Count >= PhilmartConstants.Thresholds.OutbidAlertMaxPer24Hours)
        {
            suppressReason = "3 alerts in 24 hours";
        }
        else if (recent.Any(x => x > now.AddHours(-PhilmartConstants.Thresholds.OutbidAlertCooldownHours)))
        {
            suppressReason = "4 hour cooldown";
        }

        // suppressed ones are logged too, so the throttle can be checked later
        await context.Database.ExecuteSqlAsync(
            $@"INSERT INTO philmart.List_OutbidAlertLog (ListingID, ShopID, BuyerID, Suppressed, SuppressReason)
               VALUES ({listingId}, {shopId}, {buyerId}, {suppressReason != null}, {suppressReason})",
            cancellationToken);

        if (suppressReason != null)
        {
            return;
        }

        string email = await context.Database
            .SqlQuery<string>($"SELECT Email AS Value FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
            .FirstAsync(cancellationToken);

        await EmailSql.Queue(context, PhilmartConstants.Email.OutbidAlert, email, buyerId, shopId,
            "You've been outbid on " + itemTitle,
            "Someone has placed a higher bid on " + itemTitle + ". If you'd like to stay in, place a new bid before the auction closes.\n",
            new { item = itemTitle, listingId },
            cancellationToken);
    }
}
