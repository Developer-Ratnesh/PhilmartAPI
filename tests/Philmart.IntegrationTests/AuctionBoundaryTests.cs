using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Application.Auctions;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// Client review N11, N13, N14, N15 and N23: the edges of the close, on the
// test clock so the timing is exact to the second.
[Collection("Database")]
[Trait("BR", "BR-13")]
public class AuctionBoundaryTests(DatabaseFixture db) : IAsyncLifetime
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
    [Trait("Review", "N13")]
    [Trait("Review", "N11")]
    [Trait("BR", "BR-13-R02")]
    public async Task One_second_before_the_close_counts_and_at_the_close_it_does_not()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(10));
        var tokens = await Buyers(2);

        await db.Clock.Advance(TimeSpan.FromMinutes(10) - TimeSpan.FromSeconds(1));
        Assert.Equal(HttpStatusCode.OK, (await Bid(tokens[0], auction, 10000, "edge")).StatusCode);

        // exactly the server's close time: closed, whatever the browser thinks
        await db.Clock.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Bid(tokens[1], auction, 10500, "at-close")).StatusCode);

        // a late API call after that, with the job not yet swept, is still refused
        await db.Clock.Advance(TimeSpan.FromSeconds(30));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Bid(tokens[1], auction, 11000, "after-close")).StatusCode);

        Assert.Equal(1, await BidCount(auction));
    }

    [Fact]
    [Trait("Review", "N14")]
    [Trait("BR", "BR-13-R03")]
    public async Task Each_qualifying_late_bid_extends_the_close_again()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(10), softCloseSeconds: 120);
        var tokens = await Buyers(2);

        // just before the close, then just before each new close
        TimeSpan elapsed = TimeSpan.FromMinutes(10) - TimeSpan.FromSeconds(30);
        await db.Clock.Advance(elapsed);
        long amount = 10000;
        var ends = new List<DateTimeOffset>();

        for (int i = 0; i < 3; i++)
        {
            var bid = await Bid(tokens[i % 2], auction, amount, "late-" + i);
            Assert.Equal(HttpStatusCode.OK, bid.StatusCode);
            Assert.True((await bid.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("extendedClose").GetBoolean());

            DateTimeOffset end = await db.Data.Scalar<DateTimeOffset>("SELECT EndsAt FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", auction));
            Assert.Equal(start + elapsed + TimeSpan.FromSeconds(120), end);
            ends.Add(end);

            // move to 30 seconds before the new close
            await db.Clock.Advance(TimeSpan.FromSeconds(90));
            elapsed += TimeSpan.FromSeconds(90);
            amount += 500;
        }

        Assert.True(ends[0] < ends[1] && ends[1] < ends[2]);
        Assert.Equal(3, await db.Data.Scalar<int>("SELECT ExtensionCount FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", auction)));

        // a bid well before the window does not extend
        var shop2 = await db.Data.CreateShop();
        Guid early = await db.Data.CreateAuction(shop2, start + elapsed + TimeSpan.FromHours(1), softCloseSeconds: 120);
        var earlyBid = await Bid(tokens[0], early, 10000, "early");
        Assert.False((await earlyBid.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("extendedClose").GetBoolean());
    }

    [Fact]
    [Trait("Review", "N15")]
    [Trait("Review", "N23")]
    [Trait("BR", "BR-13-R05")]
    public async Task Closing_again_after_recovery_changes_nothing()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, start.AddMinutes(5));
        var tokens = await Buyers(2);
        Assert.Equal(HttpStatusCode.OK, (await Bid(tokens[0], auction, 10000, "a")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bid(tokens[1], auction, 10500, "b")).StatusCode);

        // the server was down over the close; it comes back an hour later
        await db.Clock.Advance(TimeSpan.FromHours(1));
        await Sweep();

        Guid winner = await db.Data.Scalar<Guid>("SELECT BuyerID FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction));
        long price = await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction));

        // a restart sweeps again, several times, in parallel
        await Task.WhenAll(Sweep(), Sweep(), Sweep());

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(winner, await db.Data.Scalar<Guid>("SELECT BuyerID FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(price, await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE TemplateCode = 'EML-012' AND BuyerID = @b", TestData.P("@b", winner)));
        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'auction.closed' AND EntityID = @l", TestData.P("@l", auction.ToString())));
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
        var result = new List<string>();
        for (int i = 0; i < count; i++)
        {
            var buyer = await db.Data.CreateBuyer();
            result.Add(await db.Api.SignIn(buyer.Email, TestData.Password, "buyer"));
        }

        return result;
    }

    private Task<int> BidCount(Guid listing)
    {
        return db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_Bid WHERE ListingID = @l", TestData.P("@l", listing));
    }
}
