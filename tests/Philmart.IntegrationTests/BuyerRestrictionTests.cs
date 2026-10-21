using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
[Trait("BR", "BR-03")]
public class BuyerRestrictionTests(DatabaseFixture db)
{
    [Fact]
    [Trait("Decision", "D044")]
    public async Task A_shop_restriction_blocks_buy_now_at_that_shop_until_lifted()
    {
        var shop = await db.Data.CreateShop();
        var other = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 5000);
        Guid elsewhere = await db.Data.CreateFixedPrice(other, 5000);
        var buyer = await db.Data.CreateBuyer();
        string buyerToken = await db.Api.SignIn(buyer.Email, "", "buyer");
        var asShop = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));

        // a reason is required
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await asShop.PostAsJsonAsync("/api/shop/restrictions", new { email = buyer.Email, reason = " " })).StatusCode);

        var restrict = await asShop.PostAsJsonAsync("/api/shop/restrictions", new { email = buyer.Email, reason = "Unpaid invoices" });
        Assert.Equal(HttpStatusCode.OK, restrict.StatusCode);
        Guid id = (await restrict.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Buy(buyerToken, listing)).StatusCode);

        // only this Shop: the buyer can still buy elsewhere, and the other Shop doesn't see it
        Assert.Equal(HttpStatusCode.OK, (await Buy(buyerToken, elsewhere)).StatusCode);
        var asOther = db.Api.As(await db.Api.SignIn(other.AdminEmail, TestData.Password, "shop"));
        var seen = await asOther.GetFromJsonAsync<JsonElement>("/api/shop/restrictions");
        Assert.DoesNotContain(seen.EnumerateArray(), x => x.GetProperty("id").GetGuid() == id);
        Assert.Equal(HttpStatusCode.NotFound, (await asOther.PostAsJsonAsync("/api/shop/restrictions/" + id + "/lift", new { reason = "x" })).StatusCode);

        var lift = await asShop.PostAsJsonAsync("/api/shop/restrictions/" + id + "/lift", new { reason = "Paid up" });
        Assert.Equal(HttpStatusCode.NoContent, lift.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Buy(buyerToken, listing)).StatusCode);
    }

    [Fact]
    [Trait("Decision", "D045")]
    public async Task A_platform_restriction_blocks_every_shop_and_only_philmart_lifts_it()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 5000);
        var buyer = await db.Data.CreateBuyer();
        string buyerToken = await db.Api.SignIn(buyer.Email, "", "buyer");
        var asAdmin = db.Api.As(await db.Api.SignIn(await db.Data.CreatePlatformAdmin(), TestData.Password, "admin"));

        var restrict = await asAdmin.PostAsJsonAsync("/api/admin/restrictions", new { email = buyer.Email, reason = "Fraud check" });
        Assert.Equal(HttpStatusCode.OK, restrict.StatusCode);
        Guid id = (await restrict.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Buy(buyerToken, listing)).StatusCode);

        // a staff member without buyer.restrict can't use it at all
        var staff = await db.Data.AddShopUser(shop, "item.view");
        var asStaff = db.Api.As(await db.Api.SignIn(staff.Email, TestData.Password, "shop"));
        Assert.Equal(HttpStatusCode.Forbidden, (await asStaff.GetAsync("/api/shop/restrictions")).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent,
            (await asAdmin.PostAsJsonAsync("/api/admin/restrictions/" + id + "/lift", new { reason = "Cleared" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Buy(buyerToken, listing)).StatusCode);
    }

    private async Task<HttpResponseMessage> Buy(string token, Guid listing)
    {
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid commitment = detail.GetProperty("commitment").GetProperty("versionID").GetGuid();
        Guid method = detail.GetProperty("deliveryOptions").EnumerateArray()
            .First(x => x.GetProperty("code").GetString() == "TEST_COURIER").GetProperty("id").GetGuid();

        return await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = commitment, deliveryMethodID = method, idempotencyKey = Guid.NewGuid().ToString() });
    }
}
