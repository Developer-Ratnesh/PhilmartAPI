using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// SCR-PUB-006 buyer profile and preferences, SCR-SHP-002 Shop dashboard and
// the marketplace filters (M2 checklist L.6-L.8, M.3, S.6/S.8)
[Collection("Database")]
public class ProfileAndDashboardTests(DatabaseFixture db)
{
    // M2 checklist R.6/B.4: the preferred method from the profile is what the
    // item page pre-selects, even when it isn't the Shop's first method
    [Fact]
    [Trait("BR", "D009")]
    public async Task The_preferred_shipping_method_is_saved_and_offered_as_the_default()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 5000);
        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));

        var options = (await client.GetFromJsonAsync<JsonElement>("/api/register/delivery-options")).EnumerateArray().ToList();
        Guid last = options[^1].GetProperty("id").GetGuid();

        List<object> Prefs(params Guid[] preferred) => options.Select(m => (object)new
        {
            deliveryMethodID = m.GetProperty("id").GetGuid(),
            available = true,
            pickupPointID = m.GetProperty("requiresPickupPoint").GetBoolean() ? m.GetProperty("pickupPoints")[0].GetProperty("id").GetGuid() : (Guid?)null,
            useAddress = !m.GetProperty("requiresPickupPoint").GetBoolean(),
            preferred = preferred.Contains(m.GetProperty("id").GetGuid()),
        }).ToList();

        object Body(List<object> prefs) => new { addressLine1 = "2 New Road", city = "Durban", province = "KwaZulu-Natal", postalCode = "4001", countryCode = "ZA", shippingPreferences = prefs };

        // only one may be preferred
        Guid first = options[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PutAsJsonAsync("/api/account/profile/address", Body(Prefs(first, last)))).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await client.PutAsJsonAsync("/api/account/profile/address", Body(Prefs(last)))).StatusCode);

        var profile = await client.GetFromJsonAsync<JsonElement>("/api/account/profile");
        Assert.Equal(last, profile.GetProperty("shippingPreferences").EnumerateArray().Single(x => x.GetProperty("preferred").GetBoolean()).GetProperty("deliveryMethodID").GetGuid());

        var defaults = await client.GetFromJsonAsync<JsonElement>("/api/listings/" + listing + "/purchase-defaults");
        var preferredOffered = defaults.EnumerateArray().Where(x => x.GetProperty("preferred").GetBoolean()).Select(x => x.GetProperty("deliveryMethodID").GetGuid()).ToList();
        Assert.True(preferredOffered.Count == 0 || preferredOffered.SequenceEqual(new[] { last }));

        // switching it moves the flag, it doesn't add a second one
        Assert.Equal(HttpStatusCode.NoContent, (await client.PutAsJsonAsync("/api/account/profile/address", Body(Prefs(first)))).StatusCode);
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_ShippingPreference WHERE BuyerID = @b AND IsPreferred = 1", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("BR", "D039")]
    public async Task Profile_shows_identity_but_only_mobile_and_address_change()
    {
        var buyer = await db.Data.CreateBuyer();
        var client = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));

        var profile = await client.GetFromJsonAsync<JsonElement>("/api/account/profile");
        Assert.Equal("9001015800085", profile.GetProperty("identificationNumber").GetString());
        Assert.Equal("1990-01-01", profile.GetProperty("dateOfBirth").GetString());
        Assert.Equal("1 Buyer Road", profile.GetProperty("address").GetProperty("addressLine1").GetString());

        Assert.Equal(HttpStatusCode.NoContent, (await client.PutAsJsonAsync("/api/account/profile/mobile", new { mobile = "+27 82 555 0101" })).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PutAsJsonAsync("/api/account/profile/mobile", new { mobile = "call me" })).StatusCode);

        var address = await client.PutAsJsonAsync("/api/account/profile/address",
            new { addressLine1 = "2 New Road", city = "Durban", province = "KwaZulu-Natal", postalCode = "4001", countryCode = "ZA", shippingPreferences = Array.Empty<object>() });
        Assert.Equal(HttpStatusCode.NoContent, address.StatusCode);

        var after = await client.GetFromJsonAsync<JsonElement>("/api/account/profile");
        Assert.Equal("+27 82 555 0101", after.GetProperty("mobile").GetString());
        Assert.Equal("2 New Road", after.GetProperty("address").GetProperty("addressLine1").GetString());
        Assert.Equal("Test Buyer", after.GetProperty("fullName").GetString());

        // D042: the old address is archived, not deleted
        Assert.Equal(2, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Address WHERE BuyerID = @b", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("BR", "D040")]
    public async Task Only_the_outbid_alert_can_be_switched_off_and_only_for_yourself()
    {
        var a = await db.Data.CreateBuyer();
        var b = await db.Data.CreateBuyer();
        var asA = db.Api.As(await db.Api.SignIn(a.Email, "", "buyer"));
        var asB = db.Api.As(await db.Api.SignIn(b.Email, "", "buyer"));

        Assert.True((await asA.GetFromJsonAsync<JsonElement>("/api/account/preferences")).GetProperty("outbidAlerts").GetBoolean());

        Assert.Equal(HttpStatusCode.NoContent, (await asA.PutAsJsonAsync("/api/account/preferences", new { outbidAlerts = false })).StatusCode);

        Assert.False((await asA.GetFromJsonAsync<JsonElement>("/api/account/preferences")).GetProperty("outbidAlerts").GetBoolean());
        Assert.True((await asB.GetFromJsonAsync<JsonElement>("/api/account/preferences")).GetProperty("outbidAlerts").GetBoolean());
        Assert.False(await db.Data.Scalar<bool>("SELECT Enabled FROM philmart.Buy_CommunicationPreference WHERE BuyerID = @b AND EmailCode = 'EML-013'", TestData.P("@b", a.Id)));
    }

    [Fact]
    [Trait("BR", "BR-01-R05")]
    public async Task Accepted_terms_list_only_the_buyers_own_acceptances()
    {
        var a = await db.Data.CreateBuyer();
        var b = await db.Data.CreateBuyer();
        var asA = db.Api.As(await db.Api.SignIn(a.Email, "", "buyer"));

        var legal = await asA.GetFromJsonAsync<JsonElement>("/api/account/legal");
        int expected = await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b", TestData.P("@b", a.Id));

        Assert.True(expected > 0);
        Assert.Equal(expected, legal.GetArrayLength());
        Assert.All(legal.EnumerateArray(), x => Assert.Equal("registration", x.GetProperty("context").GetString()));

        var shop = await db.Data.CreateShop();
        var asShop = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));
        Assert.Equal(HttpStatusCode.Forbidden, (await asShop.GetAsync("/api/account/legal")).StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-08-R08")]
    public async Task Dashboard_counts_one_shop_and_hides_what_the_user_cant_see()
    {
        var a = await db.Data.CreateShop();
        var b = await db.Data.CreateShop();
        await db.Data.CreateItem(a);
        await db.Data.CreateFixedPrice(a, 2500);
        await db.Data.CreateAuction(a, DateTimeOffset.UtcNow.AddDays(1));
        await db.Data.CreateItem(b);
        await db.Data.CreateItem(b);
        await db.Data.CreateFixedPrice(b, 900);

        var asA = db.Api.As(await db.Api.SignIn(a.AdminEmail, TestData.Password, "shop"));
        var dashboard = await asA.GetFromJsonAsync<JsonElement>("/api/shop/dashboard");

        Assert.Equal(1, dashboard.GetProperty("readyToList").GetInt32());
        Assert.Equal(1, dashboard.GetProperty("activeFixedPrice").GetInt32());
        Assert.Equal(1, dashboard.GetProperty("activeAuctions").GetInt32());
        Assert.Equal(1, dashboard.GetProperty("auctions").GetArrayLength());
        Assert.NotEqual(JsonValueKind.Null, dashboard.GetProperty("salesValueThisYearMinor").ValueKind);

        // a user with only item.view sees stock but not sales, listings or users
        var staff = await db.Data.AddShopUser(a, "item.view");
        var asStaff = db.Api.As(await db.Api.SignIn(staff.Email, TestData.Password, "shop"));
        var limited = await asStaff.GetFromJsonAsync<JsonElement>("/api/shop/dashboard");

        Assert.Equal(1, limited.GetProperty("readyToList").GetInt32());
        Assert.Equal(JsonValueKind.Null, limited.GetProperty("activeFixedPrice").ValueKind);
        Assert.Equal(JsonValueKind.Null, limited.GetProperty("salesValueThisYearMinor").ValueKind);
        Assert.Equal(JsonValueKind.Null, limited.GetProperty("activeUsers").ValueKind);
        Assert.Equal(JsonValueKind.Null, limited.GetProperty("auctions").ValueKind);

        var buyer = await db.Data.CreateBuyer();
        var asBuyer = db.Api.As(await db.Api.SignIn(buyer.Email, "", "buyer"));
        Assert.Equal(HttpStatusCode.Forbidden, (await asBuyer.GetAsync("/api/shop/dashboard")).StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-02")]
    public async Task Shop_filter_and_shop_list_only_cover_active_shops()
    {
        var a = await db.Data.CreateShop();
        var closed = await db.Data.CreateShop("deactivated");
        Guid listing = await db.Data.CreateFixedPrice(a, 1200);

        var client = db.Api.As(null);

        var shops = await client.GetFromJsonAsync<JsonElement>("/api/marketplace/shops");
        var ids = shops.EnumerateArray().Select(x => x.GetProperty("id").GetGuid()).ToList();
        Assert.Contains(a.ID, ids);
        Assert.DoesNotContain(closed.ID, ids);

        var filtered = await client.GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=100&shopId=" + a.ID);
        var listings = filtered.GetProperty("items").EnumerateArray().ToList();
        Assert.Contains(listing, listings.Select(x => x.GetProperty("listingID").GetGuid()));
        Assert.All(listings, x => Assert.Equal(a.ID, x.GetProperty("shopID").GetGuid()));
    }

    [Fact]
    [Trait("BR", "D031")]
    [Trait("BR", "D032")]
    public async Task Admin_deactivates_a_shop_with_a_reason_and_it_stops_selling()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 800);
        var admin = db.Api.As(await db.Api.SignIn(await db.Data.CreatePlatformAdmin(), TestData.Password, "admin"));

        // D031: never without a reason
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await admin.PostAsJsonAsync("/api/admin/shops/" + shop.ID + "/deactivate", new { reason = " " })).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await admin.PostAsJsonAsync("/api/admin/shops/" + shop.ID + "/deactivate", new { reason = "Fees overdue after warnings" })).StatusCode);
        Assert.Equal("deactivated", await db.Data.Scalar<string>("SELECT Status FROM philmart.Shop_Shop WHERE ID = @s", TestData.P("@s", shop.ID)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE EntityID = @s AND Action = 'Shop_Shop.deactivated' AND Reason IS NOT NULL", TestData.P("@s", shop.ID.ToString())));

        var anonymous = db.Api.As(null);
        var items = await anonymous.GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=100&shopId=" + shop.ID);
        Assert.DoesNotContain(listing, items.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()));

        // a second deactivate is refused, reactivating brings it back
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await admin.PostAsJsonAsync("/api/admin/shops/" + shop.ID + "/deactivate", new { reason = "again" })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await admin.PostAsJsonAsync("/api/admin/shops/" + shop.ID + "/reactivate", new { reason = "Fees paid" })).StatusCode);
        Assert.Equal("active", await db.Data.Scalar<string>("SELECT Status FROM philmart.Shop_Shop WHERE ID = @s", TestData.P("@s", shop.ID)));

        // and nobody but a platform admin can do it
        var asShop = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));
        Assert.Equal(HttpStatusCode.Forbidden, (await asShop.PostAsJsonAsync("/api/admin/shops/" + shop.ID + "/deactivate", new { reason = "mine" })).StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-02")]
    public async Task A_region_filter_finds_items_in_the_countries_under_it()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 700);

        Guid country = await db.Data.Scalar<Guid>("SELECT TOP 1 ID FROM philmart.Sys_ClassificationAreaCountry WHERE ParentID IS NOT NULL ORDER BY Code");
        Guid region = await db.Data.Scalar<Guid>("SELECT ParentID FROM philmart.Sys_ClassificationAreaCountry WHERE ID = @c", TestData.P("@c", country));
        await db.Data.Scalar<int>(@"UPDATE i SET AreaCountryID = @c FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l; SELECT @@ROWCOUNT",
            TestData.P("@c", country), TestData.P("@l", listing));

        var client = db.Api.As(null);
        foreach (Guid area in new[] { country, region })
        {
            var result = await client.GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=100&areaCountryId=" + area);
            Assert.Contains(listing, result.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()));
        }
    }
}
