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

    // V24-AUC-02: the Shop opens the zero-bid confirmation, a Buyer bids, then
    // the Shop confirms. The administrator holds cancel_with_bids, so without
    // the check this would silently become the exceptional route.
    [Fact]
    [Trait("BR", "BR-13-R07")]
    [Trait("Decision", "D016")]
    [Trait("Query", "V24-AUC-02")]
    public async Task A_cancellation_confirmed_before_a_bid_arrived_is_refused()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddDays(1));
        string adminToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        var admin = db.Api.As(adminToken);

        var seen = await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions");
        int seenBids = seen.EnumerateArray().Single(x => x.GetProperty("listingID").GetGuid() == auction).GetProperty("bidCount").GetInt32();
        Assert.Equal(0, seenBids);

        var buyer = (await BuyerRows(1))[0];
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyer.Token, auction, 10000, "stale")).StatusCode);

        var cancel = await admin.PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "no longer needed", expectedBidCount = seenBids });
        Assert.Equal(HttpStatusCode.Conflict, cancel.StatusCode);

        // nothing partial: still live, bid kept, item still listed, no audit, no email
        Assert.Equal("live", await State(auction));
        Assert.Equal(1, await BidCount(auction));
        Assert.Equal("listed", await db.Data.Scalar<string>(
            "SELECT i.State FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", auction)));
        Assert.Equal(0, await CancelAudits(auction));
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-015'", TestData.P("@b", buyer.Id)));

        // the bidder still leads
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyer.Token, auction, 10500, "still-open")).StatusCode);
    }

    // V24-AUC-02, the true race: cancel and bid sent together. Either order is
    // fine, but the end state has to match exactly one of them.
    [Fact]
    [Trait("BR", "BR-13-R07")]
    [Trait("Decision", "D016")]
    [Trait("Query", "V24-AUC-02")]
    public async Task A_cancellation_racing_a_bid_ends_in_one_consistent_state()
    {
        for (int round = 0; round < 5; round++)
        {
            var shop = await db.Data.CreateShop();
            Guid auction = await db.Data.CreateAuction(shop, start.AddDays(1));
            var admin = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));
            var buyer = (await BuyerRows(1))[0];

            var cancelTask = admin.PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "race", expectedBidCount = 0 });
            var bidTask = Bid(buyer.Token, auction, 10000, "race-cancel-" + round);
            var cancel = await cancelTask;
            var bid = await bidTask;

            if (cancel.StatusCode == HttpStatusCode.NoContent)
            {
                Assert.NotEqual(HttpStatusCode.OK, bid.StatusCode);
                Assert.Equal("cancelled", await State(auction));
                Assert.Equal(0, await BidCount(auction));
                Assert.Equal(1, await CancelAudits(auction));
            }
            else
            {
                Assert.Equal(HttpStatusCode.Conflict, cancel.StatusCode);
                Assert.Equal(HttpStatusCode.OK, bid.StatusCode);
                Assert.Equal("live", await State(auction));
                Assert.Equal(1, await BidCount(auction));
                Assert.Equal(0, await CancelAudits(auction));
            }
        }
    }

    // V24-AUC-03: the same cancellation sent several times at once
    [Fact]
    [Trait("BR", "BR-13-R07")]
    [Trait("Decision", "D012")]
    [Trait("Query", "V24-AUC-03")]
    public async Task Duplicate_cancellations_at_once_cancel_once()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddDays(1));
        var admin = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));

        var results = await Task.WhenAll(Enumerable.Range(0, 6).Select(_ =>
            admin.PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "duplicate click", expectedBidCount = 0 })));

        Assert.Equal(1, results.Count(x => x.StatusCode == HttpStatusCode.NoContent));
        Assert.All(results.Where(x => x.StatusCode != HttpStatusCode.NoContent), x => Assert.Equal(HttpStatusCode.UnprocessableEntity, x.StatusCode));
        Assert.Equal("cancelled", await State(auction));
        Assert.Equal(1, await CancelAudits(auction));
        Assert.Equal("ready_to_list", await db.Data.Scalar<string>(
            "SELECT i.State FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", auction)));

        // and a late repeat changes nothing
        var late = await admin.PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "late repeat" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, late.StatusCode);
        Assert.Equal("duplicate click", await db.Data.Scalar<string>("SELECT CancellationReason FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", auction)));
        Assert.Equal(1, await CancelAudits(auction));
    }

    // V24-AUC-03, exceptional route: duplicates must not send EML-015 twice
    [Fact]
    [Trait("BR", "BR-13-R07")]
    [Trait("Decision", "D016")]
    [Trait("Query", "V24-AUC-03")]
    public async Task Duplicate_exceptional_cancellations_notify_each_bidder_once()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddDays(1));
        var buyers = await BuyerRows(2);
        await Bid(buyers[0].Token, auction, 10000, "dup-a");
        await Bid(buyers[1].Token, auction, 10500, "dup-b");
        var admin = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));

        var results = await Task.WhenAll(Enumerable.Range(0, 6).Select(_ =>
            admin.PostAsJsonAsync("/api/shop/auctions/" + auction + "/cancel", new { reason = "Found damaged", itemMissingOrDamaged = true, expectedBidCount = 2 })));

        Assert.Equal(1, results.Count(x => x.StatusCode == HttpStatusCode.NoContent));
        Assert.Equal("cancelled", await State(auction));
        Assert.Equal(2, await BidCount(auction));
        Assert.Equal(1, await CancelAudits(auction));
        foreach (var b in buyers)
        {
            Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-015'", TestData.P("@b", b.Id)));
        }
    }

    // V49-AUC-08: the Shop's list, the Auction Management screen, the public
    // item page and the sale all tell the same story, live and after the close
    [Fact]
    [Trait("BR", "BR-13-R04")]
    [Trait("BR", "BR-13-R08")]
    [Trait("Query", "V49-AUC-08")]
    public async Task Auction_management_agrees_with_every_other_view()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(30), startMinor: 10000, incrementMinor: 500);
        var buyers = await BuyerRows(2);
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyers[0].Token, auction, 10000, "m1")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyers[1].Token, auction, 10500, "m2")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bid(buyers[0].Token, auction, 11500, "m3")).StatusCode);

        var admin = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));

        var listRow = (await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions"))
            .EnumerateArray().Single(x => x.GetProperty("listingID").GetGuid() == auction);
        var detail = await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions/" + auction);
        var publicView = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + auction);

        // current price and bid count
        Assert.Equal(11500, listRow.GetProperty("currentBidMinor").GetInt64());
        Assert.Equal(11500, detail.GetProperty("currentBidMinor").GetInt64());
        Assert.Equal(11500, publicView.GetProperty("currentBidMinor").GetInt64());
        Assert.Equal(3, listRow.GetProperty("bidCount").GetInt32());
        Assert.Equal(3, detail.GetProperty("bidCount").GetInt32());
        Assert.Equal(3, publicView.GetProperty("bids").GetArrayLength());
        Assert.Equal(3, await BidCount(auction));
        Assert.Equal("live", detail.GetProperty("state").GetString());
        Assert.Equal(listRow.GetProperty("endsAt").GetDateTimeOffset(), detail.GetProperty("endsAt").GetDateTimeOffset());

        // ranking: highest first, one leader, same bidder number for the same buyer
        var bids = detail.GetProperty("bids").EnumerateArray().ToList();
        Assert.Equal(new long[] { 11500, 10500, 10000 }, bids.Select(x => x.GetProperty("amountMinor").GetInt64()));
        Assert.Equal(new[] { 1, 2, 3 }, bids.Select(x => x.GetProperty("rank").GetInt32()));
        Assert.Single(bids, x => x.GetProperty("leading").GetBoolean());
        Assert.True(bids[0].GetProperty("leading").GetBoolean());
        Assert.Equal(bids[0].GetProperty("bidder").GetString(), bids[2].GetProperty("bidder").GetString());
        Assert.NotEqual(bids[0].GetProperty("bidder").GetString(), bids[1].GetProperty("bidder").GetString());

        // the same sequence numbers as the public bid history, and no buyer identity
        Assert.Equal(
            publicView.GetProperty("bids").EnumerateArray().Select(x => x.GetProperty("sequenceNo").GetInt64()).OrderBy(x => x),
            bids.Select(x => x.GetProperty("sequenceNo").GetInt64()).OrderBy(x => x));
        string raw = detail.GetRawText();
        Assert.DoesNotContain(buyers[0].Id.ToString(), raw, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("@test.local", raw, StringComparison.OrdinalIgnoreCase);

        // activity: opened, then one entry per bid in order
        var activity = detail.GetProperty("activity").EnumerateArray().Select(x => x.GetProperty("action").GetString()).ToList();
        Assert.Equal(new[] { "auction.live", "bid.placed", "bid.placed", "bid.placed" }, activity);

        // close it and look again
        await db.Clock.Advance(TimeSpan.FromMinutes(31));
        await Sweep();

        listRow = (await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions"))
            .EnumerateArray().Single(x => x.GetProperty("listingID").GetGuid() == auction);
        detail = await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions/" + auction);

        Assert.Equal("sold", listRow.GetProperty("state").GetString());
        Assert.Equal("sold", detail.GetProperty("state").GetString());
        Assert.Equal(11500, listRow.GetProperty("soldPriceMinor").GetInt64());
        Assert.Equal(11500, detail.GetProperty("soldPriceMinor").GetInt64());
        Assert.Equal(11500, await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(buyers[0].Id, await db.Data.Scalar<Guid>("SELECT BuyerID FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));

        bids = detail.GetProperty("bids").EnumerateArray().ToList();
        Assert.True(bids[0].GetProperty("winning").GetBoolean());
        Assert.Single(bids, x => x.GetProperty("winning").GetBoolean());
        Assert.Equal("auction.closed", detail.GetProperty("activity").EnumerateArray().Last().GetProperty("action").GetString());
        Assert.Contains("R 115.00", detail.GetProperty("activity").EnumerateArray().Last().GetProperty("description").GetString());
    }

    // V49-AUC-08 for the other outcomes: unsold and cancelled show up the same everywhere
    [Fact]
    [Trait("BR", "BR-13-R06")]
    [Trait("BR", "BR-13-R07")]
    [Trait("Query", "V49-AUC-08")]
    public async Task Auction_management_shows_unsold_and_cancelled_outcomes()
    {
        var shop = await db.Data.CreateShop();
        Guid unsold = await db.Data.CreateAuction(shop, start.AddMinutes(10));
        Guid cancelled = await db.Data.CreateAuction(shop, start.AddDays(1));
        var admin = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));

        Assert.Equal(HttpStatusCode.NoContent,
            (await admin.PostAsJsonAsync("/api/shop/auctions/" + cancelled + "/cancel", new { reason = "Withdrawn by owner", expectedBidCount = 0 })).StatusCode);

        await db.Clock.Advance(TimeSpan.FromMinutes(11));
        await Sweep();

        var u = await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions/" + unsold);
        Assert.Equal("unsold", u.GetProperty("state").GetString());
        Assert.Equal("ready_to_list", u.GetProperty("itemState").GetString());
        Assert.Equal(0, u.GetProperty("bidCount").GetInt32());
        Assert.Equal("auction.closed", u.GetProperty("activity").EnumerateArray().Last().GetProperty("action").GetString());

        var c = await admin.GetFromJsonAsync<JsonElement>("/api/shop/auctions/" + cancelled);
        Assert.Equal("cancelled", c.GetProperty("state").GetString());
        Assert.Equal("Withdrawn by owner", c.GetProperty("cancellationReason").GetString());
        var last = c.GetProperty("activity").EnumerateArray().Last();
        Assert.Equal("auction.cancelled", last.GetProperty("action").GetString());
        Assert.Equal("Withdrawn by owner", last.GetProperty("reason").GetString());
    }

    private Task<int> CancelAudits(Guid listing)
    {
        return db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE EntityID = @l AND Action IN ('auction.cancelled', 'auction.cancelled_with_bids')",
            TestData.P("@l", listing.ToString()));
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
