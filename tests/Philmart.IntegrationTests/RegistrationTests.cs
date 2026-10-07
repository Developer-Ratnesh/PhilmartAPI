using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
[Trait("BR", "BR-01")]
public class RegistrationTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "BR-01-R01")]
    [Trait("BR", "BR-01-R02")]
    [Trait("BR", "BR-01-R03")]
    public async Task Four_steps_and_the_welcome_email_only_at_the_end()
    {
        string email = NewEmail();

        // SCR-PUB-014.1: email, then the 4-digit PIN from EML-019
        var start = await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        Assert.Equal(HttpStatusCode.OK, start.StatusCode);
        string challenge = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        Guid buyerId = (await db.Data.Scalar<Guid>("SELECT ID FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email)));
        Assert.Equal(1, await EmailCount(buyerId, "EML-019"));
        Assert.Contains(KnownPins.Pin, await db.Data.Scalar<string>(
            "SELECT Body FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = 'EML-019'", TestData.P("@b", buyerId)));

        // D035: no way on without the right PIN
        var wrong = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = "0000" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, wrong.StatusCode);

        var verify = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.OK, verify.StatusCode);
        string token = (await verify.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("token").GetString()!;
        var client = db.Api.As(token);

        // D036: verifying is not registering, no welcome yet
        Assert.Equal(0, await EmailCount(buyerId, "EML-020"));
        Assert.Null(await db.Data.Scalar<DateTimeOffset?>("SELECT RegistrationCompletedAt FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));

        // a buyer who hasn't finished can't commit to anything
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 1000);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Buy(token, listing)).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await client.PutAsJsonAsync("/api/register/personal", Personal())).StatusCode);

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

        var address = await client.PutAsJsonAsync("/api/register/address",
            new { addressLine1 = "2 Test Road", city = "Durban", postalCode = "4001", countryCode = "ZA", shippingPreferences = prefs, outbidAlerts = true });
        Assert.Equal(HttpStatusCode.NoContent, address.StatusCode);

        var docs = await client.GetFromJsonAsync<JsonElement>("/api/register/legal");
        var versionIds = docs.EnumerateArray().Select(x => x.GetProperty("versionID").GetGuid()).ToList();
        Assert.Equal(3, versionIds.Count);

        var accept = await client.PostAsJsonAsync("/api/register/accept", new { versionIDs = versionIds });
        Assert.Equal(HttpStatusCode.NoContent, accept.StatusCode);

        Assert.NotNull(await db.Data.Scalar<DateTimeOffset?>("SELECT RegistrationCompletedAt FROM philmart.Buy_Buyer WHERE ID = @b", TestData.P("@b", buyerId)));
        Assert.Equal(1, await EmailCount(buyerId, "EML-020"));
    }

    [Fact]
    [Trait("BR", "BR-01-R04")]
    [Trait("BR", "BR-01-R05")]
    [Trait("BR", "BR-01-R10")]
    public async Task Acceptance_is_stored_by_version_and_never_overwritten()
    {
        var buyer = await db.Data.CreateBuyer();

        int rows = await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b", TestData.P("@b", buyer.Id));
        Assert.Equal(3, rows);

        var ex = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sys_LegalAcceptance SET DocumentVersion = 'changed' WHERE BuyerID = @b", TestData.P("@b", buyer.Id)));
        Assert.Contains("append-only", ex.Message);
    }

    [Fact]
    [Trait("BR", "BR-01-R04")]
    public async Task Accepting_an_old_version_is_refused()
    {
        string token = await RegisterAndVerify(NewEmail());
        Guid buyerId = (await db.Api.As(token).GetFromJsonAsync<JsonElement>("/api/auth/me")).GetProperty("actorID").GetGuid();

        await db.Data.Execute("UPDATE philmart.Buy_Buyer SET RegistrationStep = 4 WHERE ID = @b", TestData.P("@b", buyerId));

        var accept = await db.Api.As(token).PostAsJsonAsync("/api/register/accept", new { versionIDs = new[] { Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid() } });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, accept.StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-01-R09")]
    public async Task Sign_in_pin_works_only_for_a_registered_email_and_only_a_few_tries()
    {
        var buyer = await db.Data.CreateBuyer();

        // unknown email: same answer, but the challenge can never pass
        var unknown = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = NewEmail() });
        Assert.Equal(HttpStatusCode.OK, unknown.StatusCode);
        string dead = (await unknown.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge = dead, pin = KnownPins.Pin })).StatusCode);

        var real = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = buyer.Email });
        string challenge = (await real.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        // five wrong guesses and even the right PIN is refused
        for (int i = 0; i < 5; i++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge, pin = "000" + i })).StatusCode);
        }

        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge, pin = KnownPins.Pin })).StatusCode);

        // a fresh PIN works
        Assert.False(string.IsNullOrEmpty(await db.Api.SignIn(buyer.Email, "", "buyer")));
    }

    [Fact]
    [Trait("BR", "BR-01-R07")]
    [Trait("Decision", "D039")]
    public async Task Identity_is_read_only_once_registered()
    {
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var api = await db.Api.As(token).PutAsJsonAsync("/api/register/personal", Personal());
        Assert.Equal(HttpStatusCode.UnprocessableEntity, api.StatusCode);

        // and the database refuses it even if the API check went missing
        var ex = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Buy_Buyer SET IdentificationNumber = '1111111111111' WHERE ID = @b", TestData.P("@b", buyer.Id)));
        Assert.Contains("D039", ex.Message);
    }

    [Fact]
    [Trait("BR", "BR-01-R08")]
    [Trait("Decision", "D040")]
    public async Task Only_the_outbid_alert_can_be_switched_off()
    {
        var buyer = await db.Data.CreateBuyer();

        await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "INSERT INTO philmart.Buy_CommunicationPreference (BuyerID, EmailCode, Enabled) VALUES (@b, 'EML-001', 0)", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("BR", "BR-01-R09")]
    public async Task Superseded_terms_block_commitments_until_accepted_again()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 5000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        // publish a new Buyer Terms version. Buyers created after this accept it.
        string version = "t-" + Guid.NewGuid().ToString("N").Substring(0, 8);
        await db.Data.Execute(@"
            UPDATE philmart.Sys_LegalDocumentVersion SET SupersededAt = philmart.ServerNow()
            WHERE DocumentCode = 'LEGAL-BUY-001' AND PublishedAt IS NOT NULL AND SupersededAt IS NULL;
            INSERT INTO philmart.Sys_LegalDocumentVersion (DocumentCode, Version, Body, ContentSha256, IsDraft, PublishedAt)
            VALUES ('LEGAL-BUY-001', @v, N'New terms', REPLICATE('a', 64), 0, philmart.ServerNow());", TestData.P("@v", version));

        var me = await db.Api.As(token).GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.Contains("LEGAL-BUY-001", me.GetProperty("pendingAcceptances").EnumerateArray().Select(x => x.GetString()));

        var buy = await Buy(token, listing);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, buy.StatusCode);

        // renewing adds rows, the old acceptance stays
        var docs = await db.Api.As(token).GetFromJsonAsync<JsonElement>("/api/register/legal");
        var renew = await db.Api.As(token).PostAsJsonAsync("/api/register/accept",
            new { versionIDs = docs.EnumerateArray().Select(x => x.GetProperty("versionID").GetGuid()).ToList() });
        Assert.Equal(HttpStatusCode.NoContent, renew.StatusCode);

        Assert.Equal(6, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b", TestData.P("@b", buyer.Id)));
        Assert.Equal(HttpStatusCode.OK, (await Buy(token, listing)).StatusCode);
    }

    private async Task<string> RegisterAndVerify(string email)
    {
        var start = await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        string challenge = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        var verify = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin });
        verify.EnsureSuccessStatusCode();
        return (await verify.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("token").GetString()!;
    }

    private static string NewEmail()
    {
        return "reg-" + Guid.NewGuid().ToString("N").Substring(0, 10) + "@test.local";
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

    private Task<int> EmailCount(Guid buyerId, string code)
    {
        return db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE BuyerID = @b AND TemplateCode = @c",
            TestData.P("@b", buyerId), TestData.P("@c", code));
    }

    private static object Personal()
    {
        return new { fullName = "Reg Tester", mobile = "0820000001", identificationType = "sa_id", identificationNumber = "8501015800084", dateOfBirth = "1985-01-01" };
    }
}
