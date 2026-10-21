using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Philmart.IntegrationTests.Support;

namespace Philmart.IntegrationTests;

// Schedule A6 early technical proof, which Milestone 2 doubles as (Delivery
// Plan): an invoice, a Shop-recorded Buyer payment and a permitted reversal.
// Client review N29 and N10.
[Collection("Database")]
[Trait("Review", "N29")]
public class InvoiceTests(DatabaseFixture db)
{
    [Fact]
    [Trait("Decision", "D019")]
    [Trait("Decision", "D021")]
    [Trait("Decision", "D022")]
    public async Task Invoice_then_payment_then_reversal_with_the_history_kept()
    {
        var shop = await db.Data.CreateShop();
        var (sale, _) = await Sale(shop, 120000);
        var client = await ShopAdmin(shop);

        // issue: unpaid, one item line, the ledger shows the debit
        var issued = await Json(await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null));
        Guid invoiceId = issued.GetProperty("invoiceID").GetGuid();
        Assert.Equal("issued", issued.GetProperty("state").GetString());
        Assert.Equal("unpaid", issued.GetProperty("status").GetString());
        Assert.Equal(120000, issued.GetProperty("totalMinor").GetInt64());
        Assert.Equal(sale, issued.GetProperty("lines")[0].GetProperty("saleTransactionID").GetGuid());
        Assert.StartsWith("INV-", issued.GetProperty("invoiceNumber").GetString());

        // asking again hands back the same invoice
        var again = await Json(await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null));
        Assert.Equal(invoiceId, again.GetProperty("invoiceID").GetGuid());
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_InvoiceLine WHERE SaleTransactionID = @s", TestData.P("@s", sale)));

        // part payment, then the rest: part_paid then paid, worked out not stored
        var part = await Json(await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 20000, receivedOn = DateTime.UtcNow.Date, paymentReference = "EFT 1" }));
        Assert.Equal("part_paid", part.GetProperty("status").GetString());
        Assert.Equal(100000, part.GetProperty("outstandingMinor").GetInt64());

        var full = await Json(await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 100000, receivedOn = DateTime.UtcNow.Date, paymentReference = "EFT 2" }));
        Assert.Equal("paid", full.GetProperty("status").GetString());
        Guid second = full.GetProperty("payments")[1].GetProperty("paymentID").GetGuid();

        // the bank recalls the second payment: a linked reversal, reason required
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await client.PostAsJsonAsync("/api/shop/payments/" + second + "/reverse", new { reason = " " })).StatusCode);

        var reversed = await Json(await client.PostAsJsonAsync("/api/shop/payments/" + second + "/reverse", new { reason = "EFT recalled by the bank" }));
        Assert.Equal("part_paid", reversed.GetProperty("status").GetString());
        Assert.Equal(20000, reversed.GetProperty("paidMinor").GetInt64());

        var payments = reversed.GetProperty("payments").EnumerateArray().ToList();
        Assert.Equal(3, payments.Count);
        var reversal = payments.Single(x => x.GetProperty("reversesPaymentID").ValueKind != JsonValueKind.Null);
        Assert.Equal(second, reversal.GetProperty("reversesPaymentID").GetGuid());
        Assert.Equal("EFT recalled by the bank", reversal.GetProperty("reversalReason").GetString());
        Assert.Equal(reversal.GetProperty("paymentID").GetGuid(),
            payments.Single(x => x.GetProperty("paymentID").GetGuid() == second).GetProperty("reversedByPaymentID").GetGuid());

        // the original payment row is exactly as it was
        Assert.Equal(100000L, await db.Data.Scalar<long>("SELECT AmountMinor FROM philmart.Sale_Payment WHERE ID = @p", TestData.P("@p", second)));

        // can't reverse it twice, and a reversal can't itself be reversed
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await client.PostAsJsonAsync("/api/shop/payments/" + second + "/reverse", new { reason = "again" })).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await client.PostAsJsonAsync("/api/shop/payments/" + reversal.GetProperty("paymentID").GetGuid() + "/reverse", new { reason = "undo" })).StatusCode);

        // statement: raised, two receipts, one reversal pointing at its receipt
        var ledger = reversed.GetProperty("ledger").EnumerateArray().ToList();
        Assert.Equal(new[] { "invoice_raised", "payment_received", "payment_received", "reversal" }, ledger.Select(x => x.GetProperty("entryKind").GetString()));
        Assert.Equal(ledger[2].GetProperty("entryID").GetInt64(), ledger[3].GetProperty("reversesEntryID").GetInt64());
    }

    [Fact]
    [Trait("Decision", "D019")]
    [Trait("Decision", "D022")]
    public async Task The_database_refuses_to_edit_an_issued_invoice_or_a_payment()
    {
        var shop = await db.Data.CreateShop();
        var (sale, _) = await Sale(shop, 5000);
        var client = await ShopAdmin(shop);

        Guid invoiceId = (await Json(await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null))).GetProperty("invoiceID").GetGuid();
        var paid = await Json(await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 5000, receivedOn = DateTime.UtcNow.Date }));
        Guid paymentId = paid.GetProperty("payments")[0].GetProperty("paymentID").GetGuid();

        var invoiceEdit = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sale_Invoice SET TotalMinor = 1, SubtotalMinor = 1 WHERE ID = @i", TestData.P("@i", invoiceId)));
        Assert.Equal(50021, invoiceEdit.Number);

        var lineEdit = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sale_InvoiceLine SET Description = N'changed' WHERE InvoiceID = @i", TestData.P("@i", invoiceId)));
        Assert.Equal(50023, lineEdit.Number);

        var paymentEdit = await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute(
            "UPDATE philmart.Sale_Payment SET AmountMinor = 1 WHERE ID = @p", TestData.P("@p", paymentId)));
        Assert.Equal(50008, paymentEdit.Number);

        await Assert.ThrowsAsync<SqlException>(() => db.Data.Execute("DELETE FROM philmart.Sale_Invoice WHERE ID = @i", TestData.P("@i", invoiceId)));
    }

    [Fact]
    [Trait("Review", "N10")]
    public async Task Purchase_invoice_payment_and_audit_link_up()
    {
        var shop = await db.Data.CreateShop();
        var (sale, listing) = await Sale(shop, 7500);
        var client = await ShopAdmin(shop);

        Guid invoiceId = (await Json(await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null))).GetProperty("invoiceID").GetGuid();
        var paid = await Json(await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 7500, receivedOn = DateTime.UtcNow.Date }));
        Guid paymentId = paid.GetProperty("payments")[0].GetProperty("paymentID").GetGuid();

        // one query walks listing -> sale -> invoice line -> invoice -> allocation -> payment
        Assert.Equal(1, await db.Data.Scalar<int>(@"
            SELECT COUNT(*)
            FROM philmart.List_Listing l
            JOIN philmart.Sale_Transaction t ON t.ListingID = l.ID
            JOIN philmart.Sale_InvoiceLine il ON il.SaleTransactionID = t.ID
            JOIN philmart.Sale_Invoice i ON i.ID = il.InvoiceID AND i.BuyerAccountID = t.BuyerAccountID
            JOIN philmart.Sale_PaymentAllocation a ON a.InvoiceID = i.ID
            JOIN philmart.Sale_Payment p ON p.ID = a.PaymentID
            WHERE l.ID = @l AND p.ID = @p AND a.AmountMinor = 7500 AND philmart.InvoiceStatus(i.ID) = 'paid'",
            TestData.P("@l", listing), TestData.P("@p", paymentId)));

        // and every step left an audit row naming its record
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'Sale_Transaction.buy_now' AND EntityID = @s",
            TestData.P("@s", sale.ToString())));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'Sale_Invoice.issued' AND EntityID = @i",
            TestData.P("@i", invoiceId.ToString())));
        Assert.Equal(1, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sys_AuditEvent WHERE Action = 'Sale_Payment.recorded' AND EntityID = @p",
            TestData.P("@p", paymentId.ToString())));

        // the shop's sales list shows it invoiced and paid
        var sales = await client.GetFromJsonAsync<JsonElement>("/api/shop/sales");
        var row = sales.EnumerateArray().Single(x => x.GetProperty("saleTransactionID").GetGuid() == sale);
        Assert.Equal("paid", row.GetProperty("invoiceStatus").GetString());
        Assert.Equal("Test Buyer", row.GetProperty("buyerName").GetString());
    }

    [Fact]
    public async Task Payment_amount_and_date_are_checked()
    {
        var shop = await db.Data.CreateShop();
        var (sale, _) = await Sale(shop, 5000);
        var client = await ShopAdmin(shop);
        Guid invoiceId = (await Json(await client.PostAsync("/api/shop/sales/" + sale + "/invoice", null))).GetProperty("invoiceID").GetGuid();

        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 0, receivedOn = DateTime.UtcNow.Date })).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync("/api/shop/invoices/" + invoiceId + "/payments",
            new { amountMinor = 100, receivedOn = DateTime.UtcNow.Date.AddDays(5) })).StatusCode);
        Assert.Equal(0, await db.Data.Scalar<int>("SELECT COUNT(*) FROM philmart.Sale_Payment WHERE SpecificInvoiceID = @i", TestData.P("@i", invoiceId)));
    }

    private async Task<(Guid Sale, Guid Listing)> Sale(TestShop shop, long price)
    {
        Guid listing = await db.Data.CreateFixedPrice(shop, price);
        var buyer = await db.Data.CreateBuyer();
        string token = await db.Api.SignIn(buyer.Email, TestData.Password, "buyer");
        var detail = await db.Api.CreateClient().GetFromJsonAsync<JsonElement>("/api/marketplace/listings/" + listing);
        Guid courier = detail.GetProperty("deliveryOptions").EnumerateArray()
            .First(x => x.GetProperty("code").GetString() == "TEST_COURIER").GetProperty("id").GetGuid();

        var buy = await db.Api.As(token).PostAsJsonAsync("/api/listings/" + listing + "/buy",
            new
            {
                commitmentVersionID = detail.GetProperty("commitment").GetProperty("versionID").GetGuid(),
                deliveryMethodID = courier,
                idempotencyKey = Guid.NewGuid().ToString()
            });
        Assert.Equal(HttpStatusCode.OK, buy.StatusCode);

        return ((await buy.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("saleTransactionID").GetGuid(), listing);
    }

    private async Task<HttpClient> ShopAdmin(TestShop shop)
    {
        return db.Api.As(await db.Api.SignIn(shop.AdminEmail, TestData.Password, "shop"));
    }

    private static async Task<JsonElement> Json(HttpResponseMessage response)
    {
        string body = await response.Content.ReadAsStringAsync();
        Assert.True(response.IsSuccessStatusCode, (int)response.StatusCode + " " + body);
        return JsonDocument.Parse(body).RootElement.Clone();
    }
}
