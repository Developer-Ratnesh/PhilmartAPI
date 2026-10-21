using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// The client's independent review of 21 October 2026: the extra tests N01-N30
// (Attachment A) and the interim findings B01-B14 (Attachment B). Each test
// carries its review ID as a trait, so `dotnet test --filter "Review=N03"`
// runs the evidence for one of them.
[Collection("Database")]
public class ClientReviewTests(DatabaseFixture db)
{
    [Fact]
    [Trait("Review", "N01")]
    [Trait("BR", "BR-01-R09")]
    public async Task One_client_cannot_spray_pin_requests_across_many_addresses()
    {
        // a small limit so the test doesn't need hundreds of requests
        using (var limited = db.Api.WithWebHostBuilder(b => b.UseSetting("Auth:PinRequestsPer10Minutes", "3")))
        {
            var client = limited.CreateClient();
            var codes = new List<HttpStatusCode>();

            for (int i = 0; i < 5; i++)
            {
                var response = await client.PostAsJsonAsync("/api/auth/buyer/pin", new { email = "spray-" + Guid.NewGuid().ToString("N") + "@test.local" });
                codes.Add(response.StatusCode);
            }

            Assert.Equal(new[] { HttpStatusCode.OK, HttpStatusCode.OK, HttpStatusCode.OK }, codes.Take(3));
            Assert.All(codes.Skip(3), x => Assert.Equal(HttpStatusCode.TooManyRequests, x));

            // the registration PIN shares the same limit
            var register = await client.PostAsJsonAsync("/api/register", new { email = "spray-reg-" + Guid.NewGuid().ToString("N") + "@test.local" });
            Assert.Equal(HttpStatusCode.TooManyRequests, register.StatusCode);
        }
    }

    [Fact]
    [Trait("Review", "N02")]
    [Trait("BR", "BR-01-R09")]
    public async Task A_pin_that_signed_someone_in_cannot_be_used_again()
    {
        var buyer = await db.Data.CreateBuyer();

        var pin = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = buyer.Email });
        string challenge = (await pin.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        var first = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        var again = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge, pin = KnownPins.Pin });
        Assert.Equal(HttpStatusCode.Unauthorized, again.StatusCode);
    }

    [Fact]
    [Trait("Review", "N02")]
    [Trait("BR", "BR-01-R09")]
    public async Task A_resent_pin_replaces_the_earlier_one()
    {
        var buyer = await db.Data.CreateBuyer();

        var first = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = buyer.Email });
        string old = (await first.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;
        var second = await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = buyer.Email });
        string fresh = (await second.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        // checklist L.5: only the newest PIN works, even straight at the API
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge = old, pin = KnownPins.Pin })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge = fresh, pin = KnownPins.Pin })).StatusCode);
    }

    [Fact]
    [Trait("Review", "N02")]
    [Trait("BR", "BR-01-R02")]
    public async Task A_registration_pin_cannot_be_used_twice()
    {
        string email = "reuse-" + Guid.NewGuid().ToString("N") + "@test.local";
        var start = await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        string challenge = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;

        Assert.Equal(HttpStatusCode.OK, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin })).StatusCode);
        Assert.NotEqual(HttpStatusCode.OK, (await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin })).StatusCode);
    }

    [Fact]
    [Trait("Review", "N03")]
    public async Task A_signed_out_token_is_refused_by_the_api()
    {
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        var client = db.Api.As(token);

        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/account/saved")).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await client.PostAsync("/api/auth/logout", null)).StatusCode);

        // the same token, still inside its lifetime, no longer works anywhere
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/account/saved")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/auth/me")).StatusCode);

        // a fresh sign-in is unaffected
        string again = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        Assert.Equal(HttpStatusCode.OK, (await db.Api.As(again).GetAsync("/api/account/saved")).StatusCode);

        Assert.Equal(1, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_RevokedSession WHERE ActorID = @b AND Reason = 'sign_out'", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("Review", "N03")]
    public async Task Signing_out_a_shop_user_ends_that_session_only()
    {
        var shop = await db.Data.CreateShop();
        string one = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        string two = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        Assert.Equal(HttpStatusCode.NoContent, (await db.Api.As(one).PostAsync("/api/auth/logout", null)).StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.As(one).GetAsync("/api/shop/users")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await db.Api.As(two).GetAsync("/api/shop/users")).StatusCode);
    }

    [Fact]
    [Trait("Review", "N03")]
    public async Task Expired_or_forged_tokens_are_refused()
    {
        var buyer = await db.Data.CreateBuyer();

        string expired = Token(buyer.Id, "integration-tests-only-signing-key-0123456789", DateTime.UtcNow.AddMinutes(-5));
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.As(expired).GetAsync("/api/account/saved")).StatusCode);

        string forged = Token(buyer.Id, "somebody-elses-signing-key-0123456789-abcdef", DateTime.UtcNow.AddHours(1));
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Api.As(forged).GetAsync("/api/account/saved")).StatusCode);

        string good = Token(buyer.Id, "integration-tests-only-signing-key-0123456789", DateTime.UtcNow.AddHours(1));
        Assert.Equal(HttpStatusCode.OK, (await db.Api.As(good).GetAsync("/api/account/saved")).StatusCode);
    }

    [Fact]
    [Trait("Review", "N05")]
    [Trait("BR", "BR-01-R01")]
    public async Task Registration_steps_cannot_be_skipped_through_the_api()
    {
        string email = "skip-" + Guid.NewGuid().ToString("N") + "@test.local";
        var start = await db.Api.CreateClient().PostAsJsonAsync("/api/register", new { email });
        string challenge = (await start.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("challenge").GetString()!;
        var verify = await db.Api.CreateClient().PostAsJsonAsync("/api/register/verify", new { challenge, pin = KnownPins.Pin });
        string token = (await verify.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("token").GetString()!;
        var client = db.Api.As(token);

        // straight to the address step, then straight to accepting, without step 2
        var address = await client.PutAsJsonAsync("/api/register/address",
            new { addressLine1 = "1 Skip Road", city = "Durban", postalCode = "4001", countryCode = "ZA", shippingPreferences = Array.Empty<object>(), outbidAlerts = true });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, address.StatusCode);

        var docs = await client.GetFromJsonAsync<JsonElement>("/api/register/legal");
        var accept = await client.PostAsJsonAsync("/api/register/accept",
            new { versionIDs = docs.EnumerateArray().Select(x => x.GetProperty("versionID").GetGuid()).ToList() });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, accept.StatusCode);

        // invalid personal details are refused too
        var personal = await client.PutAsJsonAsync("/api/register/personal",
            new { fullName = "", mobile = "abc", identificationType = "sa_id", identificationNumber = "123", dateOfBirth = "2030-01-01" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, personal.StatusCode);

        Assert.Null(await db.Data.Scalar<DateTimeOffset?>("SELECT RegistrationCompletedAt FROM philmart.Buy_Buyer WHERE Email = @e", TestData.P("@e", email)));
        Assert.Equal(0, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance a JOIN philmart.Buy_Buyer b ON b.ID = a.BuyerID WHERE b.Email = @e", TestData.P("@e", email)));
    }

    [Fact]
    [Trait("Review", "N07")]
    [Trait("BR", "BR-03-R03")]
    public async Task A_tampered_buy_request_cannot_change_price_shop_or_delivery()
    {
        var shop = await db.Data.CreateShop();
        var other = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 45000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var detail = await Detail(listing);
        Guid commitment = CommitmentId(detail);

        // a delivery method this Shop doesn't offer
        Guid notOffered = await db.Data.Scalar<Guid>(
            "SELECT TOP (1) ID FROM philmart.Sys_DeliveryMethod WHERE Code NOT IN ('TEST_COURIER', 'TEST_PICKUP') ORDER BY Code");
        var wrongMethod = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = commitment, deliveryMethodID = notOffered, idempotencyKey = Guid.NewGuid().ToString() });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, wrongMethod.StatusCode);

        // extra fields for price and Shop are not part of the request and are ignored
        var tampered = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new
            {
                commitmentVersionID = commitment,
                deliveryMethodID = CourierId(detail),
                idempotencyKey = Guid.NewGuid().ToString(),
                priceMinor = 1,
                salePriceMinor = 1,
                shopID = other.ID
            });
        Assert.Equal(HttpStatusCode.OK, tampered.StatusCode);

        Assert.Equal(45000L, await db.Data.Scalar<long>("SELECT SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
        Assert.Equal(shop.ID, await db.Data.Scalar<Guid>("SELECT ShopID FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
        Assert.Equal("TEST_COURIER", await db.Data.Scalar<string>(
            "SELECT s.DeliveryMethodCode FROM philmart.Sale_FulfilmentSnapshot s JOIN philmart.Sale_Transaction t ON t.ID = s.SaleTransactionID WHERE t.ListingID = @l",
            TestData.P("@l", listing)));
    }

    [Fact]
    [Trait("Review", "N08")]
    [Trait("BR", "BR-02-R05")]
    public async Task A_listing_that_stops_being_live_after_the_page_loaded_is_refused_at_confirm()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var detail = await Detail(listing);

        // the Shop withdraws it while the buyer is on the confirm screen
        await db.Data.Execute("UPDATE philmart.List_Listing SET State = 'withdrawn', ClosedAt = philmart.ServerNow() WHERE ID = @l", TestData.P("@l", listing));

        var buy = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = CommitmentId(detail), deliveryMethodID = CourierId(detail), idempotencyKey = Guid.NewGuid().ToString() });

        // a withdrawn listing isn't public any more, so row security hides it
        // from the buyer altogether and it reads as not found
        Assert.Equal(HttpStatusCode.NotFound, buy.StatusCode);
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
    }

    [Fact]
    [Trait("Review", "N09")]
    [Trait("BR", "BR-03-R02")]
    public async Task The_commitment_version_accepted_is_stored_with_the_purchase()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        var detail = await Detail(listing);
        Guid shown = CommitmentId(detail);
        string version = detail.GetProperty("commitment").GetProperty("version").GetString()!;

        var buy = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = shown, deliveryMethodID = CourierId(detail), idempotencyKey = Guid.NewGuid().ToString() });
        Assert.Equal(HttpStatusCode.OK, buy.StatusCode);

        using (var conn = await db.Data.Open())
        using (var cmd = new SqlCommand(@"SELECT VersionID, DocumentCode, DocumentVersion, ShopID FROM philmart.Sys_LegalAcceptance
                                          WHERE BuyerID = @b AND Context = 'buy_now'", conn))
        {
            cmd.Parameters.Add(TestData.P("@b", buyer.Id));
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                Assert.True(await reader.ReadAsync());
                Assert.Equal(shown, reader.GetGuid(0));
                Assert.Equal("LEGAL-DEC-001", reader.GetString(1));
                Assert.Equal(version, reader.GetString(2));
                Assert.Equal(shop.ID, reader.GetGuid(3));
                Assert.False(await reader.ReadAsync());
            }
        }
    }

    [Fact]
    [Trait("Review", "N16")]
    [Trait("BR", "BR-08-R08")]
    public async Task Another_shops_sales_invoices_and_payments_are_out_of_reach()
    {
        var shop = await db.Data.CreateShop();
        var other = await db.Data.CreateShop();
        var (invoiceId, paymentId) = await PaidInvoice(shop, 3000);
        string otherToken = await db.Api.SignIn(other.AdminEmail, TestData.Password, "shop");
        var client = db.Api.As(otherToken);

        var sales = await client.GetFromJsonAsync<JsonElement>("/api/shop/sales");
        Assert.Equal(0, sales.GetArrayLength());

        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/api/shop/invoices/" + invoiceId)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 100, receivedOn = DateTime.UtcNow.Date })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsJsonAsync("/api/shop/payments/" + paymentId + "/reverse", new { reason = "not mine" })).StatusCode);

        // nothing was written for the other Shop
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Payment WHERE SpecificInvoiceID = @i", TestData.P("@i", invoiceId)));
    }

    [Fact]
    [Trait("Review", "N18")]
    [Trait("BR", "BR-08-R06")]
    public async Task Each_money_action_needs_its_own_permission_whatever_the_screen_shows()
    {
        var shop = await db.Data.CreateShop();
        var (invoiceId, paymentId) = await PaidInvoice(shop, 3000);

        var viewer = await db.Data.AddShopUser(shop, "invoice.view");
        var client = db.Api.As(await db.Api.SignIn(viewer.Email, TestData.Password, "shop"));

        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/shop/invoices/" + invoiceId)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 100, receivedOn = DateTime.UtcNow.Date })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/shop/payments/" + paymentId + "/reverse", new { reason = "x" })).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/shop/auctions", new { })).StatusCode);

        var recorder = await db.Data.AddShopUser(shop, "payment.record");
        var recorderClient = db.Api.As(await db.Api.SignIn(recorder.Email, TestData.Password, "shop"));
        Assert.Equal(HttpStatusCode.Forbidden, (await recorderClient.PostAsJsonAsync("/api/shop/payments/" + paymentId + "/reverse", new { reason = "x" })).StatusCode);

        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Payment WHERE ReversesPaymentID = @p", TestData.P("@p", paymentId)));
    }

    [Fact]
    [Trait("Review", "N19")]
    public async Task Buyer_and_shop_identities_stay_separate()
    {
        var shop = await db.Data.CreateShop();
        var buyer = await db.Data.CreateBuyer();
        string buyerToken = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        string shopToken = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");

        // a buyer can't reach the Shop workspace API
        Assert.Equal(HttpStatusCode.Forbidden, (await db.Api.As(buyerToken).GetAsync("/api/shop/sales")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await db.Api.As(buyerToken).GetAsync("/api/shop/users")).StatusCode);

        // and a Shop user can't use buyer-only lists
        Assert.NotEqual(HttpStatusCode.OK, (await db.Api.As(shopToken).GetAsync("/api/account/saved")).StatusCode);
    }

    [Fact]
    [Trait("Review", "N20")]
    public async Task Audit_records_who_did_what_and_cannot_be_changed()
    {
        var shop = await db.Data.CreateShop();
        var (invoiceId, paymentId) = await PaidInvoice(shop, 3000);
        string token = await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop");
        await db.Api.As(token).PostAsJsonAsync("/api/shop/payments/" + paymentId + "/reverse", new { reason = "Cheque bounced" });

        using (var conn = await db.Data.Open())
        using (var cmd = new SqlCommand(@"SELECT Action, ActorID, ActorKind, ShopID, OccurredAt, Reason FROM philmart.Sys_AuditEvent
                                          WHERE ShopID = @s AND Action IN ('Sale_Invoice.issued', 'Sale_Payment.recorded', 'Sale_Payment.reversed')
                                          ORDER BY ID", conn))
        {
            cmd.Parameters.Add(TestData.P("@s", shop.ID));
            var actions = new List<string>();
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    actions.Add(reader.GetString(0));
                    Assert.Equal(shop.AdminID, reader.GetGuid(1));
                    Assert.Equal("Shop_User", reader.GetString(2));
                    Assert.Equal(shop.ID, reader.GetGuid(3));
                    Assert.False(reader.IsDBNull(4));
                    if (reader.GetString(0) == "Sale_Payment.reversed")
                    {
                        Assert.Equal("Cheque bounced", reader.GetString(5));
                    }
                }
            }

            Assert.Equal(new[] { "Sale_Invoice.issued", "Sale_Payment.recorded", "Sale_Payment.reversed" }, actions);
        }

        // append-only at the database, even as system
        await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sys_AuditEvent SET Reason = N'edited' WHERE ShopID = @s", TestData.P("@s", shop.ID)));
        await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "DELETE FROM philmart.Sys_AuditEvent WHERE ShopID = @s", TestData.P("@s", shop.ID)));
    }

    [Fact]
    [Trait("Review", "N25")]
    public async Task An_outbid_email_goes_only_to_the_outbid_buyer_and_names_nobody_else()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1));
        var a = await db.Data.CreateBuyer();
        var b = await db.Data.CreateBuyer();
        string ta = await db.Api.SignIn(a.Email, TestData.Password, "buyer");
        string tb = await db.Api.SignIn(b.Email, TestData.Password, "buyer");

        Assert.Equal(HttpStatusCode.OK, (await Bid(ta, auction, 10000, "a1")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Bid(tb, auction, 10500, "b1")).StatusCode);

        using (var conn = await db.Data.Open())
        using (var cmd = new SqlCommand(@"SELECT ToAddress, BuyerID, Subject + N' ' + Body FROM philmart.Sys_EmailMessage
                                          WHERE TemplateCode = 'EML-013' AND BuyerID IN (@a, @b)", conn))
        {
            cmd.Parameters.Add(TestData.P("@a", a.Id));
            cmd.Parameters.Add(TestData.P("@b", b.Id));
            var rows = new List<(string To, Guid Buyer, string Text)>();
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    rows.Add((reader.GetString(0), reader.GetGuid(1), reader.GetString(2)));
                }
            }

            var only = Assert.Single(rows);
            Assert.Equal(a.Email, only.To, ignoreCase: true);
            Assert.Equal(a.Id, only.Buyer);
            Assert.DoesNotContain(b.Email, only.Text, StringComparison.OrdinalIgnoreCase);
        }

        // and the sign-in PIN is never written to the email table at all
        await db.Api.CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email = a.Email });
        Assert.Equal(0, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_EmailMessage WHERE ToAddress = @e AND Body LIKE @pin",
            TestData.P("@e", a.Email), TestData.P("@pin", "%" + KnownPins.Pin + "%")));
    }

    [Fact]
    [Trait("Review", "N21")]
    [Trait("BR", "BR-13-R04")]
    public async Task A_refused_bid_leaves_nothing_half_written()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1), startMinor: 4500);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        // the commitment is written first inside the same transaction as the bid,
        // so a bid the database refuses must take the commitment row with it
        var bid = await Bid(token, auction, 4300, "low");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, bid.StatusCode);

        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_Bid WHERE ListingID = @l", TestData.P("@l", auction)));
        Assert.Equal(0, await db.Data.Scalar<int>(
            "SELECT COUNT(*) FROM philmart.Sys_LegalAcceptance WHERE BuyerID = @b AND Context = 'confirm_bid'", TestData.P("@b", buyer.Id)));
    }

    [Fact]
    [Trait("Review", "N28")]
    public async Task The_api_says_which_build_is_running()
    {
        var version = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/version");
        Assert.False(string.IsNullOrEmpty(version.GetProperty("version").GetString()));
        Assert.True(version.TryGetProperty("commit", out _));
    }

    [Fact]
    [Trait("Review", "B01")]
    [Trait("BR", "BR-02-R02")]
    public async Task Sorting_by_price_uses_the_current_bid_of_an_auction()
    {
        var shop = await db.Data.CreateShop();
        Guid fixedPrice = await db.Data.CreateFixedPrice(shop, 50000);
        Guid bidUp = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1), startMinor: 500, incrementMinor: 500);
        Guid noBids = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1), startMinor: 4200, incrementMinor: 500);

        // the screenshot case: an auction that started at R5 now stands at R600
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        Assert.Equal(HttpStatusCode.OK, (await Bid(token, bidUp, 60000, "up")).StatusCode);

        var desc = await Order("price_desc");
        Assert.Equal(new[] { bidUp, fixedPrice, noBids }, desc);

        var asc = await Order("price_asc");
        Assert.Equal(new[] { noBids, fixedPrice, bidUp }, asc);

        async Task<Guid[]> Order(string sort)
        {
            var page = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/items?pageSize=50&sort=" + sort + "&shopId=" + shop.ID);
            return page.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("listingID").GetGuid()).ToArray();
        }
    }

    [Fact]
    [Trait("Review", "B02")]
    [Trait("BR", "BR-03-R04")]
    public async Task A_blank_or_incomplete_alternative_address_is_refused()
    {
        var shop = await db.Data.CreateShop();
        Guid listing = await db.Data.CreateFixedPrice(shop, 4000);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        var detail = await Detail(listing);

        foreach (var address in new object[]
        {
            new { addressLine1 = "", city = "", postalCode = "", countryCode = "ZA" },
            new { addressLine1 = "5 Main Road", city = "", postalCode = "8001", countryCode = "ZA" },
            new { addressLine1 = "5 Main Road", city = "Cape Town", postalCode = "", countryCode = "ZA" }
        })
        {
            var buy = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
                new { commitmentVersionID = CommitmentId(detail), deliveryMethodID = CourierId(detail), address, idempotencyKey = Guid.NewGuid().ToString() });
            Assert.Equal(HttpStatusCode.UnprocessableEntity, buy.StatusCode);
        }

        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Transaction WHERE ListingID = @l", TestData.P("@l", listing)));
        Assert.Equal("live", await db.Data.Scalar<string>("SELECT State FROM philmart.List_Listing WHERE ID = @l", TestData.P("@l", listing)));
    }

    [Fact]
    [Trait("Review", "B03")]
    [Trait("BR", "BR-13-R04")]
    public async Task A_bid_below_the_minimum_is_refused_by_the_server()
    {
        var shop = await db.Data.CreateShop();
        Guid auction = await db.Data.CreateAuction(shop, DateTimeOffset.UtcNow.AddDays(1), startMinor: 4500, incrementMinor: 500);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");

        // the screenshot case: R43 against a R45 minimum
        var low = await Bid(token, auction, 4300, "r43");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, low.StatusCode);
        Assert.Contains("below the minimum", (await low.Content.ReadAsStringAsync()), StringComparison.OrdinalIgnoreCase);

        Assert.Equal(HttpStatusCode.OK, (await Bid(token, auction, 4500, "r45")).StatusCode);

        // and below current bid + increment once there is a bid
        var other = await db.Data.CreateBuyer();
        string otherToken = await db.Api.SignIn(other.Email, TestData.Password, "buyer");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await Bid(otherToken, auction, 4900, "r49")).StatusCode);

        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.List_Bid WHERE ListingID = @l", TestData.P("@l", auction)));
    }

    // an issued invoice for a Buy Now sale with one full payment recorded
    private async Task<(Guid InvoiceId, Guid PaymentId)> PaidInvoice(TestShop shop, long price)
    {
        Guid listing = await db.Data.CreateFixedPrice(shop, price);
        var buyer = await db.Data.CreateBuyer();
        string buyerToken = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        var detail = await Detail(listing);
        var buy = await db.Api.As(buyerToken).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new { commitmentVersionID = CommitmentId(detail), deliveryMethodID = CourierId(detail), idempotencyKey = Guid.NewGuid().ToString() });
        Guid sale = (await buy.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("saleTransactionID").GetGuid();

        var client = db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));
        var invoice = await (await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null)).Content.ReadFromJsonAsync<JsonElement>();
        Guid invoiceId = invoice.GetProperty("invoiceID").GetGuid();

        var paid = await (await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = price, receivedOn = DateTime.UtcNow.Date, paymentReference = "EFT test" })).Content.ReadFromJsonAsync<JsonElement>();
        Guid paymentId = paid.GetProperty("payments")[0].GetProperty("paymentID").GetGuid();

        return (invoiceId, paymentId);
    }

    private Task<JsonElement> Detail(Guid listing)
    {
        return db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
    }

    private async Task<HttpResponseMessage> Bid(string token, Guid listing, long amount, string key)
    {
        var detail = await Detail(listing);
        return await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/bids",
            new { commitmentVersionID = CommitmentId(detail), amountMinor = amount, idempotencyKey = key + "-" + listing });
    }

    private static Guid CommitmentId(JsonElement detail)
    {
        return detail.GetProperty("commitment").GetProperty("versionID").GetGuid();
    }

    private static Guid CourierId(JsonElement detail)
    {
        return detail.GetProperty("deliveryOptions").EnumerateArray()
            .First(x => x.GetProperty("code").GetString() == "TEST_COURIER").GetProperty("id").GetGuid();
    }

    // a buyer token built by hand, to try lifetimes and keys the API never issues
    private static string Token(Guid buyerId, string key, DateTime expires)
    {
        var descriptor = new SecurityTokenDescriptor();
        descriptor.Issuer = "philmart";
        descriptor.Audience = "philmart-web";
        descriptor.Subject = new ClaimsIdentity(new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, buyerId.ToString()),
            new Claim("philmart:actor_kind", "Buy_Buyer")
        });
        descriptor.NotBefore = expires.AddHours(-2);
        descriptor.IssuedAt = expires.AddHours(-2);
        descriptor.Expires = expires;
        descriptor.SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256);

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }
}
