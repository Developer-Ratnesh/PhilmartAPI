using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Application.Auctions;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// Clause 9.2 and BR-13-R05. Every timing case runs on the test clock, so
// nothing here waits for real time to pass.
[Collection("Database")]
[Trait("BR", "BR-13")]
public class AuctionTests(DatabaseFixture db) : IAsyncLifetime
{
    private DateTimeOffset start;

    public async Task InitializeAsync()
    {
        await db.Clock.Reset();
        start = DateTimeOffset.UtcNow;
        start = start.AddTicks(-(start.Ticks % TimeSpan.TicksPerSecond));
        await db.Clock.FreezeAt(start);
    }

    public Task DisposeAsync()
    {
        return db.Clock.Reset();
    }

    [Fact]
    [Trait("BR", "BR-13-R04")]
    [Trait("BR", "BR-13-R05")]
    public async Task Simultaneous_bids_at_the_same_amount_produce_one_bid()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(30));
        var tokens = await Buyers(8);

        var results = await Task.WhenAll(tokens.Select((t, i) => Bid(t, auction, 10000, "same-" + i)));

        Assert.Equal(1, results.Count(x => x.StatusCode == HttpStatusCode.OK));
        Assert.Equal(1, await BidCount(auction));
    }

    [Fact]
    [Trait("BR", "BR-13-R04")]
    [Trait("BR", "BR-13-R05")]
    public async Task Racing_bids_keep_a_clean_order()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(30));
        var tokens = await Buyers(8);

        await Task.WhenAll(tokens.Select((t, i) => Bid(t, auction, 10000 + i * 500, "race-" + i)));

        // whatever got in: sequence 1..n with no gaps, each higher than the one before
        var bids = await Bids(auction);
        Assert.NotEmpty(bids);
        Assert.Equal(Enumerable.Range(1, bids.Count).Select(x => (long)x), bids.Select(x => x.Seq));
        for (int i = 1; i < bids.Count; i++)
        {
            Assert.True(bids[i].Amount >= bids[i - 1].Amount + 500, "bid " + bids[i].Seq + " didn't beat the one before it by the increment");
        }
    }

    [Fact]
    [Trait("BR", "BR-13-R05")]
    public async Task Duplicate_submission_records_one_bid()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(30));
        string token = (await Buyers(1))[0];

        var results = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => Bid(token, auction, 10000, "double-click")));

        Assert.All(results, x => Assert.Equal(HttpStatusCode.OK, x.StatusCode));
        var ids = new List<Guid>();
        foreach (var r in results)
        {
            ids.Add((await r.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("bidID").GetGuid());
        }

        Assert.Single(ids.Distinct());
        Assert.Equal(1, await BidCount(auction));
    }

    [Fact]
    [Trait("BR", "BR-13-R02")]
    [Trait("BR", "BR-13-R03")]
    [Trait("BR", "BR-13-R05")]
    public async Task Last_second_bid_extends_the_close_and_after_the_end_nothing_gets_in()
    {
        var shop = await db.Data.CreateShop();
        DateTimeOffset ends = start.AddMinutes(10);
        Guid auction = await db.Data.CreateAuction(shop, ends, softCloseSeconds: 120);
        var tokens = await Buyers(2);

        await db.Clock.Advance(TimeSpan.FromMinutes(10) - TimeSpan.FromSeconds(1));

        var late = await Bid(tokens[0], auction, 10000, "late");
        Assert.Equal(HttpStatusCode.OK, late.StatusCode);
        var body = await late.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.GetProperty("extendedClose").GetBoolean());

        // extension counts from the bid, on database time
        DateTimeOffset newEnd = (await db.Data.Scalar<DateTimeOffset>("SELECT EndsAt FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", auction)));
        Assert.Equal(ends.AddSeconds(-1).AddSeconds(120), newEnd);

        await db.Clock.Advance(TimeSpan.FromSeconds(121));

        var tooLate = await Bid(tokens[1], auction, 10500, "too-late");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, tooLate.StatusCode);
        Assert.Equal(1, await BidCount(auction));
    }

    [Fact]
    [Trait("BR", "BR-13-R01")]
    [Trait("BR", "BR-13-R08")]
    [Trait("BR", "BR-13-R13")]
    public async Task Close_picks_the_highest_bid_and_writes_one_sale()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(5));
        var buyers = await BuyerRows(2);

        Assert.Equal(HttpStatusCode.OK, (await Bid(buyers[0].Token, auction, 10000, "a")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyers[1].Token, auction, 12000, "b")).StatusCode);

        await db.Clock.Advance(TimeSpan.FromMinutes(6));
        await Sweep();

        Assert.Equal("sold", await State(auction));
        Assert.Equal(buyers[1].Id, await db.Data.Scalar<Guid>("SELECT BuyerID FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(12000L, await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal("sold_fulfilment_pending", await db.Data.Scalar<string>(
            "SELECT i.State FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", auction)));

        // D056: the winner hears, EML-014 to the Shop is retired
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-012'", TestData.P("@b", buyers[1].Id)));
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE TemplateCode = 'EML-014'"));
    }

    [Fact]
    [Trait("BR", "BR-13-R05")]
    public async Task Several_closers_at_once_agree_on_one_outcome()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(5));
        var buyers = await BuyerRows(1);
        await Bid(buyers[0].Token, auction, 10000, "only");

        await db.Clock.Advance(TimeSpan.FromMinutes(6));
        await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => Sweep()));

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_Bid WHERE ListingID = @l AND IsWinning = 1", TestData.P("@l", auction)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-012'", TestData.P("@b", buyers[0].Id)));
    }

    [Fact]
    [Trait("BR", "BR-13-R05")]
    [Trait("BR", "BR-13-R06")]
    [Trait("Decision", "D012")]
    public async Task After_an_outage_one_sweep_closes_everything_correctly()
    {
        var shop = await db.Data.CreateShop();
        Guid withBid = await db.Data.CreateAuction(shop, start.AddMinutes(5));
        Guid noBid = await db.Data.CreateAuction(shop, start.AddMinutes(6));
        Guid underReserve = await db.Data.CreateAuction(shop, start.AddMinutes(7), reserveMinor: 50000);
        var buyers = await BuyerRows(1);
        await Bid(buyers[0].Token, withBid, 10000, "w");
        await Bid(buyers[0].Token, underReserve, 10000, "u");

        // the service was down for an hour, nothing closed
        await db.Clock.Advance(TimeSpan.FromHours(1));
        await Sweep();

        Assert.Equal("sold", await State(withBid));
        Assert.Equal("unsold", await State(noBid));
        Assert.Equal("unsold", await State(underReserve));

        // D012: unsold item goes back to Ready to List, the listing is history
        Assert.Equal("ready_to_list", await db.Data.Scalar<string>(
            "SELECT i.State FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", noBid)));

        var ex = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.List_Listing SET State = 'live' WHERE ID = @l", TestData.P("@l", noBid)));
        Assert.Equal(50024, ex.Number);

        // running it again changes nothing
        await Sweep();
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", withBid)));
    }

    [Fact]
    [Trait("BR", "BR-13-R01")]
    [Trait("Decision", "D064")]
    public async Task Auction_must_start_in_the_future_and_opens_on_time()
    {
        var shop = await db.Data.CreateShop();
        Guid item = await db.Data.CreateItem(shop);
        string token = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        var client = db.Api.As(token);

        var past = await client.PostAsJsonAsync("/api/shop/auctions",
            new { itemID = item, startingPriceMinor = 1000, bidIncrementMinor = 100, startsAt = start.AddMinutes(-1), endsAt = start.AddHours(1) });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, past.StatusCode);

        var backwards = await client.PostAsJsonAsync("/api/shop/auctions",
            new { itemID = item, startingPriceMinor = 1000, bidIncrementMinor = 100, startsAt = start.AddHours(2), endsAt = start.AddHours(1) });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, backwards.StatusCode);

        var ok = await client.PostAsJsonAsync("/api/shop/auctions",
            new { itemID = item, startingPriceMinor = 1000, bidIncrementMinor = 100, startsAt = start.AddMinutes(10), endsAt = start.AddHours(1) });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Guid listing = await ok.Content.ReadFromJsonAsync<Guid>();

        await Sweep();
        Assert.Equal("scheduled", await State(listing));

        await db.Clock.Advance(TimeSpan.FromMinutes(10));
        await Sweep();
        Assert.Equal("live", await State(listing));
    }

    [Fact]
    [Trait("BR", "BR-13-R07")]
    [Trait("BR", "BR-13-R10")]
    [Trait("Decision", "D016")]
    public async Task Cancelling_with_bids_is_exceptional_and_keeps_the_bids()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddDays(1));
        var staff = await db.Data.AddShopUser(shop, "auction.manage");
        var buyers = await BuyerRows(1);
        await Bid(buyers[0].Token, auction, 10000, "c");

        string staffToken = await db.Api.SignIn(staff.Email, TestData.Password, "shop");
        var refused = await db.Api.As(staffToken).PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "damaged" });
        Assert.Equal(HttpStatusCode.Forbidden, refused.StatusCode);

        string adminToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        var noReason = await db.Api.As(adminToken).PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = " " });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, noReason.StatusCode);

        var cancel = await db.Api.As(adminToken).PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "Found damaged", itemMissingOrDamaged = true });
        Assert.Equal(HttpStatusCode.NoContent, cancel.StatusCode);

        Assert.Equal("cancelled", await State(auction));
        Assert.Equal(1, await BidCount(auction));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-015'", TestData.P("@b", buyers[0].Id)));
        Assert.Equal("Found damaged", await db.Data.Scalar<string>(
            "SELECT Reason FROM philmart.Sys_AuditEvent WHERE EntityID = @l AND Action = 'auction.cancelled_with_bids'", TestData.P("@l", auction.ToString())));
        Assert.Equal("missing_damaged", await db.Data.Scalar<string>(
            "SELECT i.State FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", auction)));
    }

    [Fact]
    [Trait("BR", "BR-13-R09")]
    [Trait("Decision", "D068")]
    public async Task Outbid_emails_are_throttled_but_bids_never_are()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddDays(2), startMinor: 1000, incrementMinor: 100);
        var a = (await BuyerRows(1))[0];
        var b = (await BuyerRows(1))[0];

        long amount = 1000;
        for (int round = 0; round < 3; round++)
        {
            Assert.Equal(HttpStatusCode.OK, (await Bid(a.Token, auction, amount, "a" + round)).StatusCode);
            amount += 100;
            Assert.Equal(HttpStatusCode.OK, (await Bid(b.Token, auction, amount, "b" + round)).StatusCode);
            amount += 100;
        }

        // three outbids inside four hours: one email, two suppressed
        Assert.Equal(1, await OutbidEmails(a.Id));
        Assert.Equal(2, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_OutbidAlertLog WHERE BuyerID = @b AND Suppressed = 1", TestData.P("@b", a.Id)));
        Assert.Equal(6, await BidCount(auction));

        // after the cooldown the next one goes
        await db.Clock.Advance(TimeSpan.FromHours(4) + TimeSpan.FromMinutes(1));
        await Bid(a.Token, auction, amount, "a-later");
        await Bid(b.Token, auction, amount + 100, "b-later");
        Assert.Equal(2, await OutbidEmails(a.Id));
    }

    private Task<int> OutbidEmails(Guid buyerId)
    {
        return db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-013'", TestData.P("@b", buyerId));
    }

    private async Task Sweep()
    {
        using (var scope = db.Api.Services.CreateScope())
        {
            await scope.ServiceProvider.GetRequiredService<IAuctionCloser>().Sweep();
        }
    }

    private async Task<HttpResponseMessage> Bid(string token, Guid listing, long amount, string key)
    {
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid commitment = detail.GetProperty("commitment").GetProperty("versionID").GetGuid();

        return await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/bids",
            new { commitmentVersionID = commitment, amountMinor = amount, idempotencyKey = key + "-" + listing });
    }

    private async Task<List<string>> Buyers(int count)
    {
        return (await BuyerRows(count)).Select(x => x.Token).ToList();
    }

    private async Task<List<(Guid Id, string Token)>> BuyerRows(int count)
    {
        var result = new List<(Guid, string)>();
        for (int i = 0; i < count; i++)
        {
            var buyer = await db.Data.CreateBuyer();
            result.Add((buyer.Id, await db.Api.SignIn(buyer.Email, TestData.Password, "buyer")));
        }

        return result;
    }

    private Task<string?> State(Guid listing)
    {
        return db.Data.Scalar<string>("SELECT State FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", listing));
    }

    private Task<int> BidCount(Guid listing)
    {
        return db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_Bid WHERE ListingID = @l", TestData.P("@l", listing));
    }

    private async Task<List<(long Seq, long Amount)>> Bids(Guid listing)
    {
        var result = new List<(long, long)>();

        using (var conn = await db.Data.Open())
        using (var cmd = new SqlCommand("SELECT SequenceNo, AmountMinor FROM philmart.List_Bid WHERE ListingID = @l ORDER BY SequenceNo", conn))
        {
            cmd.Parameters.Add(TestData.P("@l", listing));
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    result.Add((reader.GetInt64(0), reader.GetInt64(1)));
                }
            }
        }

        return result;
    }
}
