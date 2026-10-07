using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
public class MarketplaceAndCommitmentTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "BR-02-R04")]
    public async Task Only_live_listings_of_active_shops_are_public()
    {
        var shop = await db.Data.CreateShop();
        Guid live = await db.Data.CreateFixedPrice(shop, 1000);
        Guid stock = await db.Data.CreateItem(shop);

        var closed = await db.Data.CreateShop("deactivated");
        Guid hidden = await db.Data.CreateFixedPrice(closed, 1000);

        var page = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=100&shopId=" + shop.ID);
        var ids = page.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()).ToList();
        Assert.Contains(live, ids);

        var other = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=100&shopId=" + closed.ID);
        Assert.DoesNotContain(hidden, other.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()));

        // and at the database: an anonymous session can't see Ready to List stock
        using (var conn = await db.Data.Open("anonymous"))
        using (var cmd = new SqlCommand("SELECT COUNT(*) FROM philmart.Item_Item WHERE ID = @i", conn))
        {
            cmd.Parameters.Add(TestData.P("@i", stock));
            Assert.Equal(0, (int)(await cmd.ExecuteScalarAsync())!);
        }
    }

    [Fact]
    [Trait("BR", "BR-03-R01")]
    [Trait("BR", "BR-03-R07")]
    public async Task Item_detail_has_what_the_buyer_needs()
    {
        var shop = await db.Data.CreateShop();
        Guid fixedPrice = await db.Data.CreateFixedPrice(shop, 2500);
        Guid auction = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1));

        var a = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + fixedPrice);
        Assert.Equal("LEGAL-DEC-001", a.GetProperty("commitment").GetProperty("code").GetString());
        Assert.Equal(shop.ID, a.GetProperty("shopID").GetGuid());
        Assert.True(a.GetProperty("deliveryOptions").GetArrayLength() >= 2);

        var b = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + auction);
        Assert.Equal("LEGAL-DEC-002", b.GetProperty("commitment").GetProperty("code").GetString());
        Assert.Equal(10000, b.GetProperty("nextMinimumBidMinor").GetInt64());
    }

    [Fact]
    [Trait("BR", "BR-03-R03")]
    [Trait("BR", "BR-03-R04")]
    [Trait("BR", "BR-03-R05")]
    [Trait("Decision", "D042")]
    [Trait("Decision", "D038")]
    public async Task Buy_now_snapshots_delivery_and_leaves_the_profile_alone()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var buy = await Buy(token, listing, new { addressLine1 = "99 Override Lane", city = "Pretoria", countryCode = "ZA" });
        Assert.Equal(HttpStatusCode.OK, buy.StatusCode);
        Guid sale = (await buy.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("saleTransactionID").GetGuid();

        Assert.Equal("99 Override Lane", await db.Data.Scalar<string>(
            "SELECT AddressLine1 FROM philmart.Sale_FulfilmentSnapshot WHERE SaleTransactionID = @s", TestData.P("@s", sale)));

        // D038: the override was for this purchase only
        Assert.Equal("1 Buyer Road", await db.Data.Scalar<string>(
            "SELECT AddressLine1 FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", buyer.Id)));

        // D042: later changes can't reach the snapshot
        var ex = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sale_FulfilmentSnapshot SET City = N'Elsewhere' WHERE SaleTransactionID = @s", TestData.P("@s", sale)));
        Assert.Contains("D042", ex.Message);

        Assert.Equal("sold", await db.Data.Scalar<string>("SELECT State FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", listing)));
    }

    [Fact]
    public async Task Buy_now_twice_is_one_sale_and_a_second_buyer_loses()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var first = await db.Data.CreateBuyer();
        var second = await db.Data.CreateBuyer();
        string t1 = await db.Api.SignIn(first.Email, TestData.Password, "buyer");
        string t2 = await db.Api.SignIn(second.Email, TestData.Password, "buyer");

        var results = await Task.WhenAll(Buy(t1, listing), Buy(t1, listing), Buy(t2, listing));

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
        Assert.Contains(results, x => x.StatusCode == HttpStatusCode.OK);
    }

    [Fact]
    [Trait("BR", "BR-03-R02")]
    public async Task Commitment_wording_must_be_the_version_shown()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid method = CourierId(detail);

        var buy = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = Guid.NewGuid(), deliveryMethodID = method, idempotencyKey = "x" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, buy.StatusCode);
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
    }

    [Fact]
    [Trait("BR", "BR-03-R08")]
    [Trait("Decision", "D044")]
    public async Task Restricted_buyer_is_refused_at_the_commitment_point()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        Guid auction = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1));
        var buyer = await db.Data.CreateBuyer();
        await db.Data.Restrict(buyer.Id, shop.ID);
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Buy(token, listing)).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Bid(token, auction, 10000, "r1")).StatusCode);

        // straight at the procedure, with the API out of the way
        var ex = await Assert.ThrowsAsync<SqlException>(async () =>
        {
            using (var conn = await db.Data.Open())
            using (var cmd = new SqlCommand("DECLARE @id UNIQUEIDENTIFIER; EXEC philmart.P_List_Bid_Place @l, @b, 10000, 'direct', @id OUTPUT", conn))
            {
                cmd.Parameters.Add(TestData.P("@l", auction));
                cmd.Parameters.Add(TestData.P("@b", buyer.Id));
                await cmd.ExecuteNonQueryAsync();
            }
        });
        Assert.Equal(50035, ex.Number);
    }

    [Fact]
    [Trait("BR", "BR-03-R06")]
    [Trait("BR", "BR-13-R12")]
    [Trait("Decision", "D062")]
    public async Task Nothing_can_be_listed_below_the_seller_minimum()
    {
        var shop = await db.Data.CreateShop();
        Guid item = await db.Data.CreateItem(shop, "listed", sellerMinimum: 50000);

        var ex = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            @"INSERT INTO philmart.List_Listing (ShopID, ItemID, ListingType, State, Reference, PriceMinor, ListedAt, ExpiresAt)
              VALUES (@s, @i, 'fixed_price', 'live', 'LOW-1', 49999, philmart.ServerNow(), DATEADD(DAY, 10, philmart.ServerNow()))",
            TestData.P("@s", shop.ID), TestData.P("@i", item)));
        Assert.Equal(50030, ex.Number);
    }

    [Fact]
    [Trait("BR", "BR-02-R05")]
    [Trait("Decision", "D032")]
    public async Task Deactivated_shop_takes_no_new_purchases()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        await db.Data.Execute("UPDATE philmart.Shop_Shop SET Status = 'deactivated', DeactivationReason = N'test', DeactivatedAt = philmart.ServerNow() WHERE ID = @s",
            TestData.P("@s", shop.ID));

        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Buy(token, listing)).StatusCode);
    }

    [Fact]
    public async Task A_visitor_or_shop_user_cannot_buy()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        string shopToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().PostAsJsonAsync("/api/listings/" + listing + "/buy", new { })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Buy(shopToken, listing)).StatusCode);
    }

    private async Task<HttpResponseMessage> Buy(string token, Guid listing, object? address = null)
    {
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid commitment = detail.GetProperty("commitment").GetProperty("versionID").GetGuid();

        return await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = commitment, deliveryMethodID = CourierId(detail), address, idempotencyKey = Guid.NewGuid().ToString() });
    }

    private async Task<HttpResponseMessage> Bid(string token, Guid listing, long amount, string key)
    {
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid commitment = detail.GetProperty("commitment").GetProperty("versionID").GetGuid();

        return await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/bids",
            new { commitmentVersionID = commitment, amountMinor = amount, idempotencyKey = key });
    }

    private static Guid CourierId(JsonElement detail)
    {
        return detail.GetProperty("deliveryOptions").EnumerateArray()
            .First(x => x.GetProperty("code").GetString() == "TEST_COURIER").GetProperty("id").GetGuid();
    }
}
