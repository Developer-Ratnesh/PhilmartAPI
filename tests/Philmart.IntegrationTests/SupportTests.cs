using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

[Collection("Database")]
public class SupportTests(DatabaseFixture db)
{
    [Fact]
    [Trait("BR", "BR-02-R07")]
    public async Task Visitor_gets_a_reference_and_the_request_is_kept_as_sent()
    {
        var response = await db.Api.CreateClient().PostAsJsonAsync("/api/support", new
        {
            category = "buying",
            subject = "Question about bidding",
            relatedReference = "PH-1234",
            message = "How does soft close work?",
            contactName = "Visitor",
            contactEmail = "visitor@test.local"
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        string reference = body.GetProperty("reference").GetString()!;
        Assert.Matches(@"^SUP-\d{4}-\d{5}$", reference);

        Assert.Equal("visitor@test.local", await db.Data.Scalar<string>(
            "SELECT ContactEmail FROM philmart.Sys_SupportRequest WHERE Reference = @r", TestData.P("@r", reference)));

        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'Sys_SupportRequest.submitted' AND AfterValue LIKE @r",
            TestData.P("@r", "%" + reference + "%")));

        // the record is the authoritative copy, so it can't be rewritten or removed
        var edit = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sys_SupportRequest SET Message = N'changed' WHERE Reference = @r", TestData.P("@r", reference)));
        Assert.Equal(50042, edit.Number);

        var delete = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "DELETE FROM philmart.Sys_SupportRequest WHERE Reference = @r", TestData.P("@r", reference)));
        Assert.Equal(50042, delete.Number);

        // closing it is allowed, that's the only thing that moves
        await db.Data.Execute("UPDATE philmart.Sys_SupportRequest SET Status = 'closed', ClosedAt = philmart.ServerNow() WHERE Reference = @r",
            TestData.P("@r", reference));
    }

    [Fact]
    [Trait("BR", "BR-02-R07")]
    public async Task Signed_in_buyer_is_recognised_without_typing_their_details()
    {
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, "", "buyer");

        var response = await db.Api.As(token).PostAsJsonAsync("/api/support", new
        {
            category = "account",
            subject = "Change my email",
            message = "I'd like to use a different address."
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();

        Assert.Equal(buyer.Id, await db.Data.Scalar<Guid>(
            "SELECT BuyerID FROM philmart.Sys_SupportRequest WHERE Reference = @r", TestData.P("@r", body.GetProperty("reference").GetString()!)));
    }

    [Fact]
    [Trait("BR", "BR-02-R07")]
    public async Task Incomplete_requests_are_turned_away()
    {
        var client = db.Api.CreateClient();

        var noContact = await client.PostAsJsonAsync("/api/support", new { category = "other", subject = "Hi", message = "Hello" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, noContact.StatusCode);

        var badCategory = await client.PostAsJsonAsync("/api/support", new
        {
            category = "refunds",
            subject = "Hi",
            message = "Hello",
            contactName = "V",
            contactEmail = "v@test.local"
        });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, badCategory.StatusCode);

        var noMessage = await client.PostAsJsonAsync("/api/support", new
        {
            category = "other",
            subject = "Hi",
            message = "  ",
            contactName = "V",
            contactEmail = "v@test.local"
        });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, noMessage.StatusCode);
    }

    [Fact]
    [Trait("BR", "BR-02-R07")]
    public async Task Categories_come_from_reference_data()
    {
        var categories = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/support/categories");
        var values = categories.EnumerateArray().Select(x => x.GetProperty("value").GetString()).ToList();

        Assert.Contains("account", values);
        Assert.Contains("other", values);
        Assert.All(categories.EnumerateArray(), x => Assert.False(string.IsNullOrEmpty(x.GetProperty("label").GetString())));
    }
}
