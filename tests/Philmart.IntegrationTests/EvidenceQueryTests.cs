using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// The client's 16 outstanding M2 evidence queries of 22 October 2026. Each
// test carries the matrix ID as a trait, so `dotnet test --filter "Query=V38-REG-02"`
// runs the evidence for one row. The auction rows (V24-AUC-02/03/08,
// V49-AUC-08/09) are in AuctionTests and ShopIsolationTests next to the tests
// they extend.
[Collection("Database")]
public class EvidenceQueryTests(DatabaseFixture db)
{
    // ---- V38-REG-02: registration PIN, invalid, expired, reused ----

    [Fact]
    [Trait("Query", "V38-REG-02")]
    [Trait("BR", "BR-01-R02")]
    public async Task An_expired_registration_pin_is_refused_and_the_same_pin_in_time_is_not()
    {
        string email = Email("expiry");
        await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        Guid buyerId = await db.Data.Scalar<Guid>("SELECT ID FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email));

        // Sealed exactly as the API seals one, with the same PIN, for the same
        // buyer. The only difference between the two is the expiry.
        ForgetLatest(email);
        string expired = Seal(email, buyerId, DateTimeOffset.UtcNow.AddSeconds(-1));
        var late = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = expired, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, late.StatusCode);
        Assert.Null(await db.Data.Scalar<DateTimeOffset?>("SELECT EmailVerifiedAt FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));

        ForgetLatest(email);
        string inTime = Seal(email, buyerId, DateTimeOffset.UtcNow.AddMinutes(5));
        var ok = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = inTime, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Assert.NotNull(await db.Data.Scalar<DateTimeOffset?>("SELECT EmailVerifiedAt FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));
    }

    [Fact]
    [Trait("Query", "V38-REG-02")]
    [Trait("BR", "BR-01-R02")]
    public async Task A_registration_pin_stops_after_five_wrong_tries_and_cannot_be_reused()
    {
        string email = Email("tries");
        string challenge = await StartRegistration(email);

        for (int i = 0; i < 5; i++)
        {
            var wrong = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = "0000" });
            Assert.Equal(HttpStatusCode.UnprocessableEntity, wrong.StatusCode);
        }

        // the right PIN is now refused too: no session, no progress
        var blocked = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, blocked.StatusCode);
        Assert.DoesNotContain("token", await blocked.Content.ReadAsStringAsync());
        Assert.Equal((byte)1, await db.Data.Scalar<byte>("SELECT RegistrationStep FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email)));

        // a new PIN works once, and only once
        string fresh = await StartRegistration(email);
        Assert.Equal(HttpStatusCode.OK, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = fresh, pin = KnownPins.Pin })).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = fresh, pin = KnownPins.Pin })).StatusCode);
    }

    [Fact]
    [Trait("Query", "V38-REG-02")]
    [Trait("BR", "BR-01-R02")]
    public async Task A_resent_registration_pin_replaces_the_old_one_and_sign_in_pins_dont_register()
    {
        string email = Email("resend");
        string old = await StartRegistration(email);
        string fresh = await StartRegistration(email);

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = old, pin = KnownPins.Pin })).StatusCode);

        // a sign-in challenge can't be used on the registration step
        var buyer = await db.Data.CreateBuyer();
        var signIn = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = buyer.Email });
        string signInChallenge = (await signIn.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = signInChallenge, pin = KnownPins.Pin })).StatusCode);

        // nor a tampered one
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = fresh + "x", pin = KnownPins.Pin })).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge = fresh, pin = KnownPins.Pin })).StatusCode);
    }

    // ---- V38-REG-04: physical address required and persisted ----

    [Fact]
    [Trait("Query", "V38-REG-04")]
    [Trait("BR", "BR-01-R06")]
    public async Task Registration_refuses_an_incomplete_physical_address_and_saves_a_complete_one()
    {
        string email = Email("address");
        var client = await RegisterToStep3(email);
        var prefs = await AllMethods(client);
        Guid buyerId = await db.Data.Scalar<Guid>("SELECT ID FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email));

        object Address(string line1, string city, string? province, string? postal, string? country) =>
            new { addressLine1 = line1, city, province, postalCode = postal, countryCode = country, shippingPreferences = prefs, outbidAlerts = true };

        var bad = new (string Why, object Body)[]
        {
            ("no line 1", Address("", "Cape Town", "Western Cape", "8001", "ZA")),
            ("blank line 1", Address("   ", "Cape Town", "Western Cape", "8001", "ZA")),
            ("no city", Address("5 Main Road", "", "Western Cape", "8001", "ZA")),
            ("no province", Address("5 Main Road", "Cape Town", null, "8001", "ZA")),
            ("no postal code", Address("5 Main Road", "Cape Town", "Western Cape", "", "ZA")),
            ("no country", Address("5 Main Road", "Cape Town", "Western Cape", "8001", "")),
            ("postal code not 4 digits", Address("5 Main Road", "Cape Town", "Western Cape", "80A1", "ZA")),
            ("unknown province", Address("5 Main Road", "Cape Town", "Atlantis", "8001", "ZA")),
            ("bad country code", Address("5 Main Road", "Cape Town", "Western Cape", "8001", "South Africa")),
        };

        foreach (var (why, body) in bad)
        {
            var response = await client.PutAsJsonAsync("/api/register/address", body);
            Assert.True(response.StatusCode == HttpStatusCode.UnprocessableEntity, why + " was accepted (" + response.StatusCode + ")");
            string message = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("detail").GetString() ?? "";
            Assert.False(string.IsNullOrWhiteSpace(message), why + " had no message");
        }

        // nothing saved and the buyer didn't move on
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Address WHERE BuyerID = @b", TestData.P("@b", buyerId)));
        Assert.Equal((byte)3, await db.Data.Scalar<byte>("SELECT RegistrationStep FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));

        var good = await client.PutAsJsonAsync("/api/register/address", Address(" 5 Main Road ", "Cape Town", "Western Cape", "8001", "ZA"));
        Assert.Equal(HttpStatusCode.NoContent, good.StatusCode);

        // saved to this buyer, trimmed, and only once
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Address WHERE BuyerID = @b AND ArchivedAt IS NULL", TestData.P("@b", buyerId)));
        Assert.Equal("5 Main Road", await db.Data.Scalar<string>("SELECT AddressLine1 FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", buyerId)));
        Assert.Equal("Western Cape", await db.Data.Scalar<string>("SELECT Province FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", buyerId)));
        Assert.Equal("8001", await db.Data.Scalar<string>("SELECT PostalCode FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", buyerId)));
        Assert.Equal((byte)4, await db.Data.Scalar<byte>("SELECT RegistrationStep FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));

        // the profile applies the same rule
        var profile = await client.PutAsJsonAsync("/api/account/profile/address", Address("5 Main Road", "Cape Town", null, "8001", "ZA"));
        Assert.NotEqual(HttpStatusCode.NoContent, profile.StatusCode);
    }

    // ---- V38-REG-06: account creation idempotence ----

    [Fact]
    [Trait("Query", "V38-REG-06")]
    [Trait("BR", "BR-01-R01")]
    public async Task Create_account_sent_at_once_makes_one_buyer()
    {
        string email = Email("concurrent");

        var starts = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ =>
            db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email })));

        Assert.All(starts, x => Assert.Equal(HttpStatusCode.OK, x.StatusCode));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email)));
        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'Buy_Buyer.registration_started' AND EntityID = (SELECT CAST(ID AS VARCHAR(80)) FROM philmart.Buy_Buyer WHERE Email = @e)",
            TestData.P("@e", email)));
    }

    [Fact]
    [Trait("Query", "V38-REG-06")]
    [Trait("BR", "BR-01-R03")]
    [Trait("BR", "BR-01-R05")]
    public async Task Final_create_account_sent_twice_records_one_acceptance_and_one_welcome()
    {
        string email = Email("double-accept");
        var client = await RegisterToStep3(email);
        Assert.Equal(HttpStatusCode.NoContent, (await client.PutAsJsonAsync("/api/register/address",
            new { addressLine1 = "5 Main Road", city = "Cape Town", province = "Western Cape", postalCode = "8001", countryCode = "ZA", shippingPreferences = await AllMethods(client), outbidAlerts = true })).StatusCode);
        Guid buyerId = await db.Data.Scalar<Guid>("SELECT ID FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email));

        var docs = await client.GetFromJsonAsync<JsonElement>("/api/register/legal");
        var body = new { versionIDs = docs.EnumerateArray().Select(x => x.GetProperty("versionID").GetGuid()).ToList() };
        int documents = body.versionIDs.Count;

        // three at once, then a late retry
        var results = await Task.WhenAll(Enumerable.Range(0, 3).Select(_ => client.PostAsJsonAsync("/api/register/accept", body)));
        Assert.All(results, x => Assert.Equal(HttpStatusCode.NoContent, x.StatusCode));
        Assert.Equal(HttpStatusCode.NoContent, (await client.PostAsJsonAsync("/api/register/accept", body)).StatusCode);

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email)));
        Assert.Equal(documents, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b", TestData.P("@b", buyerId)));
        Assert.Equal(documents, await db.Data.Scalar<int>("SELECT COUNT(DISTINCT VersionID) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b", TestData.P("@b", buyerId)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-020'", TestData.P("@b", buyerId)));
        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE EntityID = @b AND Action = 'Buy_Buyer.registration_completed'", TestData.P("@b", buyerId.ToString())));
        Assert.Equal(0, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE EntityID = @b AND Action = 'Buy_Buyer.legal_renewed'", TestData.P("@b", buyerId.ToString())));
    }

    // ---- V38-PRF-02: identity and transaction history can't be changed ----

    [Fact]
    [Trait("Query", "V38-PRF-02")]
    [Trait("BR", "BR-01-R07")]
    [Trait("Decision", "D039")]
    [Trait("Decision", "D042")]
    public async Task A_buyer_cannot_change_identity_another_buyer_or_a_past_sale_through_the_profile()
    {
        var a = await db.Data.CreateBuyer();
        var b = await db.Data.CreateBuyer();
        string tokenA = await db.Api.SignIn(a.Email, TestData.Password, "buyer");
        var asA = db.Api.As(tokenA);

        // A has a past purchase, delivered to the address A had then
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 2500);
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid courier = detail.GetProperty("deliveryOptions").EnumerateArray().First(x => x.GetProperty("code").GetString() == "TEST_COURIER").GetProperty("id").GetGuid();
        var buy = await asA.PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = detail.GetProperty("commitment").GetProperty("versionID").GetGuid(), deliveryMethodID = courier, idempotencyKey = Guid.NewGuid().ToString() });
        Assert.Equal(HttpStatusCode.OK, buy.StatusCode);
        Guid sale = (await buy.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("saleTransactionID").GetGuid();

        // the profile calls carry B's ID and identity fields. They're ignored:
        // the API only ever acts on the signed-in buyer, and identity isn't editable.
        var address = await asA.PutAsJsonAsync("/api/account/profile/address", new
        {
            buyerId = b.Id,
            id = b.Id,
            email = b.Email,
            fullName = "Someone Else",
            identificationNumber = "8001015009087",
            dateOfBirth = "1980-01-01",
            addressLine1 = "7 Changed Street",
            city = "Pretoria",
            province = "Gauteng",
            postalCode = "0002",
            countryCode = "ZA",
            shippingPreferences = Array.Empty<object>(),
        });
        Assert.Equal(HttpStatusCode.NoContent, address.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await asA.PutAsJsonAsync("/api/account/profile/mobile", new { buyerId = b.Id, mobile = "+27 82 555 0199" })).StatusCode);

        // A's contact details changed (allowed)
        Assert.Equal("7 Changed Street", await db.Data.Scalar<string>("SELECT AddressLine1 FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", a.Id)));
        Assert.Equal("+27 82 555 0199", await db.Data.Scalar<string>("SELECT Mobile FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", a.Id)));

        // A's identity didn't
        Assert.Equal("Test Buyer", await db.Data.Scalar<string>("SELECT FullName FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", a.Id)));
        Assert.Equal("9001015800085", await db.Data.Scalar<string>("SELECT IdentificationNumber FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", a.Id)));
        Assert.Equal(a.Email, await db.Data.Scalar<string>("SELECT Email FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", a.Id)));

        // B untouched
        Assert.Equal("1 Buyer Road", await db.Data.Scalar<string>("SELECT AddressLine1 FROM philmart.Buy_Address WHERE BuyerID = @b AND IsDefault = 1", TestData.P("@b", b.Id)));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Address WHERE BuyerID = @b", TestData.P("@b", b.Id)));
        Assert.Equal("0820000000", await db.Data.Scalar<string>("SELECT Mobile FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", b.Id)));

        // the past sale still shows who bought it, for what, delivered where
        Assert.Equal(a.Id, await db.Data.Scalar<Guid>("SELECT BuyerID FROM philmart.Sale_Transaction WHERE ID = @s", TestData.P("@s", sale)));
        Assert.Equal(2500, await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ID = @s", TestData.P("@s", sale)));
        Assert.Equal("1 Buyer Road", await db.Data.Scalar<string>("SELECT AddressLine1 FROM philmart.Sale_FulfilmentSnapshot WHERE SaleTransactionID = @s", TestData.P("@s", sale)));

        // the old address is archived, not rewritten
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Buy_Address WHERE BuyerID = @b AND AddressLine1 = N'1 Buyer Road' AND ArchivedAt IS NOT NULL", TestData.P("@b", a.Id)));
    }

    // ---- V41-MKT-02: combined search and filters ----

    [Fact]
    [Trait("Query", "V41-MKT-02")]
    [Trait("BR", "BR-02-R02")]
    [Trait("BR", "BR-02-R03")]
    public async Task Filters_combine_and_counts_match_the_results()
    {
        var shop = await db.Data.CreateShop();
        var other = await db.Data.CreateShop();
        var types = await TwoIds("Sys_ClassificationType");
        var formats = await TwoIds("Sys_ClassificationFormat");
        string tag = "Combo" + Guid.NewGuid().ToString("N")[..8];

        // every type x format x selling method in one Shop, plus a decoy in another Shop
        var expected = new Dictionary<Guid, (Guid Type, Guid Format, string Method, string Title)>();
        int n = 0;
        foreach (Guid t in types)
        {
            foreach (Guid f in formats)
            {
                foreach (string method in new[] { "fixed_price", "auction" })
                {
                    string title = tag + " " + (n % 2 == 0 ? "Penny Black" : "Mafeking Siege") + " " + n++;
                    Guid id = method == "fixed_price" ? await db.Data.CreateFixedPrice(shop, 1000 + n) : await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(3));
                    await Classify(id, t, f, title);
                    expected[id] = (t, f, method, title);
                }
            }
        }

        Guid decoy = await db.Data.CreateFixedPrice(other, 999);
        await Classify(decoy, types[0], formats[0], tag + " Penny Black decoy");

        var client = db.Api.CreateClient();

        // one filter at a time, then all together
        var cases = new (string Query, Func<(Guid Type, Guid Format, string Method, string Title), bool> Match)[]
        {
            ("shopId=" + shop.ID, _ => true),
            ("shopId=" + shop.ID + "&typeId=" + types[0], x => x.Type == types[0]),
            ("shopId=" + shop.ID + "&typeId=" + types[0] + "&formatId=" + formats[1], x => x.Type == types[0] && x.Format == formats[1]),
            ("shopId=" + shop.ID + "&typeId=" + types[0] + "&formatId=" + formats[1] + "&sellingMethod=auction", x => x.Type == types[0] && x.Format == formats[1] && x.Method == "auction"),
            ("shopId=" + shop.ID + "&sellingMethod=fixed_price&query=" + Uri.EscapeDataString("Penny Black"), x => x.Method == "fixed_price" && x.Title.Contains("Penny Black")),
        };

        foreach (var (query, match) in cases)
        {
            var want = expected.Where(x => match(x.Value)).Select(x => x.Key).OrderBy(x => x).ToList();
            var got = await AllPages(client, "/api/marketplace/items?" + query, 3);

            Assert.True(want.SequenceEqual(got.Ids.OrderBy(x => x)), query + ": wrong listings");
            Assert.True(got.Total == want.Count, query + ": count " + got.Total + " but " + want.Count + " listings");
            Assert.DoesNotContain(decoy, got.Ids);
        }

        // the search term with filters across Shops still finds the decoy only when its Shop isn't filtered out
        var everywhere = await AllPages(client, "/api/marketplace/items?typeId=" + types[0] + "&formatId=" + formats[0] + "&query=" + Uri.EscapeDataString(tag + " Penny Black"), 50);
        Assert.Contains(decoy, everywhere.Ids);
        Assert.All(everywhere.Ids, id => Assert.True(id == decoy || expected[id].Type == types[0] && expected[id].Format == formats[0]));

        // zero results: a count of 0, no items and no pages, not an error
        var none = await client.GetFromJsonAsync<JsonElement>("/api/marketplace/items?shopId=" + shop.ID + "&typeId=" + types[0] + "&query=nothing-matches-" + tag);
        Assert.Equal(0, none.GetProperty("totalCount").GetInt32());
        Assert.Equal(0, none.GetProperty("items").GetArrayLength());

        // clearing the filters brings everything back
        var cleared = await AllPages(client, "/api/marketplace/items?shopId=" + shop.ID, 5);
        Assert.Equal(expected.Count, cleared.Total);
        Assert.Equal(expected.Keys.OrderBy(x => x), cleared.Ids.OrderBy(x => x));
    }

    // ---- V41-MKT-04: pagination and state parity ----

    [Fact]
    [Trait("Query", "V41-MKT-04")]
    [Trait("BR", "BR-02-R02")]
    public async Task Every_page_boundary_gives_each_listing_once_in_every_sort()
    {
        var shop = await db.Data.CreateShop();
        var ids = new List<Guid>();

        // ties on purpose: same listed time, same price, same end, the cases
        // where an order without a tie-breaker repeats or skips across pages
        for (int i = 0; i < 15; i++)
        {
            ids.Add(await db.Data.CreateFixedPrice(shop, 1000));
        }

        DateTimeOffset end = DateTimeOffset.UtcNow.AddDays(5);
        end = end.AddTicks(-(end.Ticks % TimeSpan.TicksPerSecond));
        for (int i = 0; i < 8; i++)
        {
            ids.Add(await db.Data.CreateAuction(shop, end, startMinor: 1000));
        }

        await db.Data.Execute("UPDATE philmart.List_Listing SET ListedAt = '2026-10-01T09:00:00+02:00' WHERE ShopID = @s", TestData.P("@s", shop.ID));

        var client = db.Api.CreateClient();
        foreach (string sort in new[] { "newest", "ending", "price_asc", "price_desc" })
        {
            foreach (int pageSize in new[] { 5, 10, 23 })
            {
                var first = await AllPages(client, "/api/marketplace/items?shopId=" + shop.ID + "&sort=" + sort, pageSize);
                var second = await AllPages(client, "/api/marketplace/items?shopId=" + shop.ID + "&sort=" + sort, pageSize);

                string label = sort + " / " + pageSize + " per page";
                Assert.True(first.Ids.Count == 23, label + ": " + first.Ids.Count + " rows over all pages");
                Assert.True(first.Ids.Distinct().Count() == 23, label + ": a listing appeared on two pages");
                Assert.True(ids.OrderBy(x => x).SequenceEqual(first.Ids.OrderBy(x => x)), label + ": a listing was skipped");
                Assert.True(first.Total == 23, label + ": total " + first.Total);
                Assert.True(first.Pages == (int)Math.Ceiling(23.0 / pageSize), label + ": pages " + first.Pages);
                Assert.True(first.Ids.SequenceEqual(second.Ids), label + ": order changed between two identical requests");
            }
        }

        // the storefront is the same query for one Shop, so it pages the same way
        var storefront = await AllPages(client, "/api/marketplace/shops/" + shop.ID + "/items?", 10);
        Assert.Equal(ids.OrderBy(x => x), storefront.Ids.OrderBy(x => x));
    }

    // ---- helpers ----

    private static string Email(string what)
    {
        return what + "-" + Guid.NewGuid().ToString("N") + "@test.local";
    }

    private async Task<string> StartRegistration(string email)
    {
        var start = await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        Assert.Equal(HttpStatusCode.OK, start.StatusCode);
        return (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;
    }

    private async Task<HttpClient> RegisterToStep3(string email)
    {
        string challenge = await StartRegistration(email);
        var verify = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin });
        string token = (await verify.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("token").GetString()!;
        var client = db.Api.As(token);

        var personal = await client.PutAsJsonAsync("/api/register/personal",
            new { fullName = "Query Buyer", mobile = "0821234567", identificationType = "sa_id", identificationNumber = "9001015800085", dateOfBirth = "1990-01-01" });
        Assert.Equal(HttpStatusCode.NoContent, personal.StatusCode);
        return client;
    }

    private static async Task<List<object>> AllMethods(HttpClient client)
    {
        var options = await client.GetFromJsonAsync<JsonElement>("/api/register/delivery-options");
        var prefs = new List<object>();
        foreach (var m in options.EnumerateArray())
        {
            if (m.GetProperty("requiresPickupPoint").GetBoolean())
            {
                prefs.Add(new { deliveryMethodID = m.GetProperty("id").GetGuid(), available = true, pickupPointID = m.GetProperty("pickupPoints")[0].GetProperty("id").GetGuid() });
            }
            else
            {
                prefs.Add(new { deliveryMethodID = m.GetProperty("id").GetGuid(), available = true, useAddress = true });
            }
        }

        return prefs;
    }

    // what PinChallenges.Create seals, made here so only the expiry differs
    private string Seal(string email, Guid buyerId, DateTimeOffset expires)
    {
        var protector = db.Api.Services.GetRequiredService<IDataProtectionProvider>()
            .CreateProtector("Philmart.BuyerPin").ToTimeLimitedDataProtector();
        string nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        string hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(nonce + ":" + KnownPins.Pin)));

        string payload = JsonSerializer.Serialize(new { Purpose = "registration", Email = email.ToLowerInvariant(), BuyerID = buyerId, Nonce = nonce, PinHash = hash });
        return protector.Protect(payload, expires);
    }

    // the API remembers the newest PIN per address; clear it so the sealed one is judged on expiry alone
    private void ForgetLatest(string email)
    {
        db.Api.Services.GetRequiredService<IMemoryCache>().Remove("pin-latest:registration:" + email.ToLowerInvariant());
    }

    private async Task<List<Guid>> TwoIds(string table)
    {
        var result = new List<Guid>();
        using (var conn = await db.Data.Open())
        using (var cmd = new Microsoft.Data.SqlClient.SqlCommand("SELECT TOP 2 ID FROM philmart." + table + " WHERE Active = 1 ORDER BY Code", conn))
        using (var reader = await cmd.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
            {
                result.Add(reader.GetGuid(0));
            }
        }

        Assert.True(result.Count == 2, table + " needs two active rows for this test");
        return result;
    }

    private Task Classify(Guid listing, Guid type, Guid format, string title)
    {
        return db.Data.Execute(@"UPDATE i SET TypeID = @t, FormatID = @f, Title = @title
                                 FROM philmart.Item_Item i JOIN philmart.List_Listing l ON l.ItemID = i.ID WHERE l.ID = @l",
            TestData.P("@t", type), TestData.P("@f", format), TestData.P("@title", title), TestData.P("@l", listing));
    }

    private static async Task<(List<Guid> Ids, int Total, int Pages)> AllPages(HttpClient client, string url, int pageSize)
    {
        var ids = new List<Guid>();
        int total = -1;
        int pages = 1;

        for (int page = 1; page <= pages; page++)
        {
            var result = await client.GetFromJsonAsync<JsonElement>(url + "&page=" + page + "&pageSize=" + pageSize);
            int thisTotal = result.GetProperty("totalCount").GetInt32();
            Assert.True(total == -1 || total == thisTotal, "the total changed from page to page");
            total = thisTotal;
            pages = result.GetProperty("totalPages").GetInt32();

            var items = result.GetProperty("items").EnumerateArray().ToList();
            Assert.True(page < pages ? items.Count == pageSize : items.Count <= pageSize, "page " + page + " has " + items.Count + " rows");
            ids.AddRange(items.Select(x => x.GetProperty("listingID").GetGuid()));
        }

        return (ids, total, pages == 0 ? 0 : pages);
    }
}
