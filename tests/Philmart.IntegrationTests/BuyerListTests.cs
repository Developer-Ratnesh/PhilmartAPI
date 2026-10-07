using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// SCR-PUB-008 Recently Viewed and SCR-PUB-009 Saved Items (BR-02)
[Collection("Database")]
public class BuyerListTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "SCR-PUB-009")]
    public async Task Saved_items_belong_to_one_buyer()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 1500);

        var a = await db.Data.CreateBuyer();
        var b = await db.Data.CreateBuyer();
        var asA = db.Api.As(await db.Api.SignIn(a.Email, "", "buyer"));
        var asB = db.Api.As(await db.Api.SignIn(b.Email, "", "buyer"));

        Assert.Equal(HttpStatusCode.NoContent, (await asA.PutAsync("/api/account/saved/" + listing, null)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await asA.PutAsync("/api/account/saved/" + listing, null)).StatusCode);

        var saved = await asA.GetFromJsonAsync<JsonElement>("/api/account/saved");
        Assert.Equal(1, saved.GetProperty("totalCount").GetInt32());
        var row = saved.GetProperty("items")[0];
        Assert.Equal(listing, row.GetProperty("listingID").GetGuid());
        Assert.Equal("available", row.GetProperty("status").GetString());
        Assert.Equal(1500, row.GetProperty("priceMinor").GetInt64());

        var other = await asB.GetFromJsonAsync<JsonElement>("/api/account/saved");
        Assert.Equal(0, other.GetProperty("totalCount").GetInt32());

        // B removing it only touches B's own list
        await asB.DeleteAsync("/api/account/saved/" + listing);
        Assert.True((await asA.GetFromJsonAsync<JsonElement>("/api/account/saved/" + listing)).GetProperty("saved").GetBoolean());

        // and at the database, B's session can't see A's rows at all
        using (var conn = await db.Data.Open("Buy_Buyer", null, b.Id))
        using (var cmd = new SqlCommand("SELECT COUNT(*) FROM philmart.Buy_SavedItem WHERE BuyerID = @a", conn))
        {
            cmd.Parameters.Add(TestData.P("@a", a.Id));
            Assert.Equal(0, (int)(await cmd.ExecuteScalarAsync())!);
        }
    }

    [Fact]
    [Trait("BR", "SCR-PUB-009")]
    public async Task Remove_keeps_the_history_and_saving_again_brings_it_back()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(2));
        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));

        await client.PutAsync("/api/account/saved/" + listing, null);
        var first = await client.GetFromJsonAsync<JsonElement>("/api/account/saved");
        Assert.Equal("auction_open", first.GetProperty("items")[0].GetProperty("status").GetString());

        await client.DeleteAsync("/api/account/saved/" + listing);
        Assert.Equal(0, (await client.GetFromJsonAsync<JsonElement>("/api/account/saved")).GetProperty("totalCount").GetInt32());

        await client.PutAsync("/api/account/saved/" + listing, null);
        Assert.Equal(1, (await client.GetFromJsonAsync<JsonElement>("/api/account/saved")).GetProperty("totalCount").GetInt32());

        Assert.Equal(2, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_SavedItem WHERE BuyerID = @b", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("BR", "SCR-PUB-009")]
    public async Task Saved_items_can_be_searched_by_title_or_item_number()
    {
        var shop = await db.Data.CreateShop();
        Guid one = await db.Data.CreateFixedPrice(shop, 1000);
        Guid two = await db.Data.CreateFixedPrice(shop, 2000);
        await db.Data.Execute(@"UPDATE i SET Title = N'Cape triangular 1853' FROM philmart.Item_Item i
                                JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", one));

        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));
        await client.PutAsync("/api/account/saved/" + one, null);
        await client.PutAsync("/api/account/saved/" + two, null);

        var found = await client.GetFromJsonAsync<JsonElement>("/api/account/saved?search=triangular");
        Assert.Equal(1, found.GetProperty("totalCount").GetInt32());
        Assert.Equal(one, found.GetProperty("items")[0].GetProperty("listingID").GetGuid());

        string number = (await db.Data.Scalar<string>(@"SELECT i.Reference FROM philmart.Item_Item i
                                                         JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l", TestData.P("@l", two)))!;
        var byNumber = await client.GetFromJsonAsync<JsonElement>("/api/account/saved?search=" + Uri.EscapeDataString(number));
        Assert.Equal(two, byNumber.GetProperty("items")[0].GetProperty("listingID").GetGuid());
    }

    [Fact]
    [Trait("BR", "SCR-PUB-008")]
    public async Task Recently_viewed_puts_the_latest_first()
    {
        var shop = await db.Data.CreateShop();
        Guid one = await db.Data.CreateFixedPrice(shop, 1000);
        Guid two = await db.Data.CreateFixedPrice(shop, 2000);
        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));

        await client.PutAsync("/api/account/recent/" + one, null);
        await db.Clock.Advance(TimeSpan.FromMinutes(1));
        await client.PutAsync("/api/account/recent/" + two, null);
        await db.Clock.Advance(TimeSpan.FromMinutes(1));
        await client.PutAsync("/api/account/recent/" + one, null);

        try
        {
            var recent = await client.GetFromJsonAsync<JsonElement>("/api/account/recent");
            Assert.Equal(2, recent.GetProperty("totalCount").GetInt32());
            Assert.Equal(one, recent.GetProperty("items")[0].GetProperty("listingID").GetGuid());
            Assert.Equal(two, recent.GetProperty("items")[1].GetProperty("listingID").GetGuid());

            await client.DeleteAsync("/api/account/recent/" + two);
            var after = await client.GetFromJsonAsync<JsonElement>("/api/account/recent");
            Assert.Equal(1, after.GetProperty("totalCount").GetInt32());
        }
        finally
        {
            await db.Clock.Reset();
        }
    }

    [Fact]
    [Trait("BR", "SCR-PUB-008")]
    public async Task Only_buyers_have_these_lists_and_only_for_public_listings()
    {
        var shop = await db.Data.CreateShop();
        Guid stock = await db.Data.CreateItem(shop);

        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().GetAsync("/api/account/saved")).StatusCode);

        string shopToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        Assert.Equal(HttpStatusCode.Forbidden, (await db.Api.As(shopToken).GetAsync("/api/account/recent")).StatusCode);

        // a listing id that the public can't see is treated as not there
        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsync("/api/account/saved/" + Guid.NewGuid(), null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsync("/api/account/recent/" + stock, null)).StatusCode);
    }
}
