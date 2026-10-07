using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// BR-08-R08 and clause 9.1: these try to cross from one Shop into another and
// fail the build if any attempt gets through. A failure here is Critical.
[Collection("Database")]
[Trait("BR", "BR-08")]
public class ShopIsolationTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "BR-08-R06")]
    [Trait("BR", "BR-08-R08")]
    public async Task Another_shops_users_are_invisible_and_untouchable_through_the_api()
    {
        var a = await db.Data.CreateShop();
        var b = await db.Data.CreateShop();
        var staffA = await db.Data.AddShopUser(a, "item.view");
        string tokenB = await db.Api.SignIn(b.AdminEmail, TestData.Password, "shop");
        var client = db.Api.As(tokenB);

        var list = await client.GetFromJsonAsync<JsonElement>("/api/shop/users");
        Assert.DoesNotContain(staffA.Id, list.EnumerateArray().Select(x => x.GetProperty("id").GetGuid()));

        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsJsonAsync("/api/shop/users/" + staffA.Id + "/permissions", new { permissions = new[] { "item.manage" } })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsync("/api/shop/users/" + staffA.Id + "/disable", null)).StatusCode);

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Shop_UserPermission WHERE ShopUserID = @u", TestData.P("@u", staffA.Id)));
        Assert.Null(await db.Data.Scalar<DateTimeOffset?>("SELECT DisabledAt FROM philmart.Shop_User WHERE ID = @u", TestData.P("@u", staffA.Id)));
    }

    [Fact]
    [Trait("BR", "BR-08-R06")]
    [Trait("BR", "BR-08-R08")]
    public async Task Another_shops_auctions_cant_be_seen_or_cancelled()
    {
        var a = await db.Data.CreateShop();
        var b = await db.Data.CreateShop();
        Guid auctionA = await db.Data.CreateAuction(a, DateTimeOffset.UtcNow.AddDays(1));
        string tokenB = await db.Api.SignIn(b.AdminEmail, TestData.Password, "shop");
        var client = db.Api.As(tokenB);

        var list = await client.GetFromJsonAsync<JsonElement>("/api/shop/auctions");
        Assert.DoesNotContain(auctionA, list.EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()));

        var cancel = await client.PostAsJsonAsync("/api/shop/auctions/" + auctionA + "/cancel", new { reason = "not mine" });
        Assert.Equal(HttpStatusCode.NotFound, cancel.StatusCode);
        Assert.Equal("live", await db.Data.Scalar<string>("SELECT State FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", auctionA)));

        // can't list someone else's stock either
        Guid itemA = await db.Data.CreateItem(a);
        var create = await client.PostAsJsonAsync("/api/shop/auctions",
            new { itemID = itemA, startingPriceMinor = 1000, bidIncrementMinor = 100, startsAt = DateTimeOffset.UtcNow.AddHours(1), endsAt = DateTimeOffset.UtcNow.AddDays(1) });
        Assert.Equal(HttpStatusCode.NotFound, create.StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-08-R07")]
    public async Task Row_level_security_holds_even_without_the_api()
    {
        var a = await db.Data.CreateShop();
        var b = await db.Data.CreateShop();
        Guid itemA = await db.Data.CreateItem(a);

        using (var conn = await db.Data.Open("Shop_User", b.ID, b.AdminID))
        {
            using (var read = new SqlCommand("SELECT COUNT(*) FROM philmart.Shop_User WHERE ShopID = @a", conn))
            {
                read.Parameters.Add(TestData.P("@a", a.ID));
                Assert.Equal(0, (int)(await read.ExecuteScalarAsync())!);
            }

            using (var update = new SqlCommand("UPDATE philmart.Item_Item SET Title = N'hijacked' WHERE ID = @i", conn))
            {
                update.Parameters.Add(TestData.P("@i", itemA));
                Assert.Equal(0, await update.ExecuteNonQueryAsync());
            }

            // planting a row in Shop A from Shop B's session
            using (var insert = new SqlCommand(@"INSERT INTO philmart.Item_Item (ShopID, Reference, Title, ReadyToListSince)
                                                 VALUES (@a, 'PLANTED', N'planted', philmart.ServerNow())", conn))
            {
                insert.Parameters.Add(TestData.P("@a", a.ID));
                await Assert.ThrowsAsync<SqlException>(() => insert.ExecuteNonQueryAsync());
            }
        }

        Assert.NotEqual("hijacked", await db.Data.Scalar<string>("SELECT Title FROM philmart.Item_Item WHERE ID = @i", TestData.P("@i", itemA)));
    }

    [Fact]
    [Trait("BR", "BR-08-R06")]
    public async Task A_token_for_one_shop_cant_be_bent_to_another()
    {
        var a = await db.Data.CreateShop();
        var b = await db.Data.CreateShop();
        string tokenB = await db.Api.SignIn(b.AdminEmail, TestData.Password, "shop");

        // a shop id in the query or a header is ignored, the token decides
        var client = db.Api.As(tokenB);
        client.DefaultRequestHeaders.Add("X-Shop-Id", a.ID.ToString());
        var list = await client.GetFromJsonAsync<JsonElement>("/api/shop/users?shopId=" + a.ID);

        Assert.All(list.EnumerateArray(), x => Assert.NotEqual(a.AdminEmail, x.GetProperty("email").GetString()));
    }

    [Fact]
    [Trait("BR", "BR-08-R05")]
    [Trait("Decision", "D049")]
    public async Task Disabled_user_loses_access_at_once_and_keeps_their_history()
    {
        var shop = await db.Data.CreateShop();
        var staff = await db.Data.AddShopUser(shop, "auction.manage");
        string staffToken = await db.Api.SignIn(staff.Email, TestData.Password, "shop");
        string adminToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        Assert.Equal(HttpStatusCode.OK, (await db.Api.As(staffToken).GetAsync("/api/shop/auctions")).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await db.Api.As(adminToken).PostAsync("/api/shop/users/" + staff.Id + "/disable", null)).StatusCode);

        // same token, still in date, refused
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.As(staffToken).GetAsync("/api/shop/auctions")).StatusCode);

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Shop_User WHERE ID = @u", TestData.P("@u", staff.Id)));
        Assert.True(await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE EntityID = @u AND Action = 'Shop_User.disabled'",
            TestData.P("@u", staff.Id.ToString())) == 1);
    }

    [Fact]
    [Trait("BR", "BR-08-R02")]
    [Trait("BR", "BR-08-R04")]
    [Trait("Decision", "D050")]
    [Trait("Decision", "D051")]
    public async Task Permissions_go_straight_onto_one_user()
    {
        var shop = await db.Data.CreateShop();
        var one = await db.Data.AddShopUser(shop, "item.view");
        var two = await db.Data.AddShopUser(shop, "item.view");
        string adminToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        var set = await db.Api.As(adminToken).PutAsJsonAsync("/api/shop/users/" + one.Id + "/permissions", new { permissions = new[] { "auction.manage" } });
        Assert.Equal(HttpStatusCode.NoContent, set.StatusCode);

        Assert.Equal("auction.manage", await db.Data.Scalar<string>("SELECT PermissionCode FROM philmart.Shop_UserPermission WHERE ShopUserID = @u", TestData.P("@u", one.Id)));
        Assert.Equal("item.view", await db.Data.Scalar<string>("SELECT PermissionCode FROM philmart.Shop_UserPermission WHERE ShopUserID = @u", TestData.P("@u", two.Id)));

        // and it's live on the next request, no new login needed
        string oneToken = await db.Api.SignIn(one.Email, TestData.Password, "shop");
        Assert.Equal(HttpStatusCode.OK, (await db.Api.As(oneToken).GetAsync("/api/shop/auctions")).StatusCode);

        // D050: there is no role layer
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM sys.tables WHERE name LIKE '%Role%'"));
    }

    [Fact]
    [Trait("BR", "BR-08-R03")]
    public async Task Shop_administrator_holds_every_permission()
    {
        var shop = await db.Data.CreateShop();
        string token = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        var me = await db.Api.As(token).GetFromJsonAsync<JsonElement>("/api/auth/me");
        int all = await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_Permission");

        Assert.Equal(all, me.GetProperty("permissions").GetArrayLength());
    }

    [Fact]
    [Trait("BR", "BR-08-R01")]
    public async Task Admin_only_permissions_cant_be_handed_out()
    {
        var shop = await db.Data.CreateShop();
        var staff = await db.Data.AddShopUser(shop);
        string adminToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        var set = await db.Api.As(adminToken).PutAsJsonAsync("/api/shop/users/" + staff.Id + "/permissions", new { permissions = new[] { "shop.users.manage" } });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, set.StatusCode);

        string staffToken = await db.Api.SignIn(staff.Email, TestData.Password, "shop");
        Assert.Equal(HttpStatusCode.Forbidden, (await db.Api.As(staffToken).GetAsync("/api/shop/users")).StatusCode);
    }
}
