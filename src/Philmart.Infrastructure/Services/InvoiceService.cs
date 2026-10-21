using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Philmart.Application.Invoices;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

// Schedule A6 early technical proof (the Delivery Plan makes Milestone 2 double
// as it): an invoice, a Shop-recorded Buyer payment and a permitted reversal.
// It runs as the Shop user, so row security keeps every read and write inside
// their own Shop. The money rules live in the database (006, 009): an issued
// invoice can't be edited, payments and allocations are append-only, and the
// paid status is worked out from the allocations, never stored.
public class InvoiceService(IDbContextFactory<PhilmartContext> contextFactory, ITenantContext tenant) : IInvoiceService
{
    public async Task<List<ShopSaleDTO>> Sales(CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            var rows = await context.Database
                .SqlQuery<SaleRow>($@"SELECT t.ID AS SaleTransactionID, l.Reference AS ListingReference, i.Title, t.SaleKind,
                                             t.SalePriceMinor, t.SoldAt, t.BuyerID, inv.ID AS InvoiceID, inv.InvoiceNumber,
                                             CASE WHEN inv.ID IS NULL THEN NULL ELSE philmart.InvoiceStatus(inv.ID) END AS InvoiceStatus
                                      FROM philmart.Sale_Transaction t
                                      JOIN philmart.List_Listing l ON l.ID = t.ListingID
                                      JOIN philmart.Item_Item i ON i.ID = t.ItemID
                                      LEFT JOIN philmart.Sale_InvoiceLine il ON il.SaleTransactionID = t.ID
                                      LEFT JOIN philmart.Sale_Invoice inv ON inv.ID = il.InvoiceID
                                      WHERE t.ShopID = {shopId} AND t.CancelledAt IS NULL
                                      ORDER BY t.SoldAt DESC")
                .ToListAsync(cancellationToken);

            var names = await BuyerNames(context, rows.Select(x => x.BuyerID), cancellationToken);
            var result = new List<ShopSaleDTO>();

            foreach (var row in rows)
            {
                var dto = new ShopSaleDTO();
                dto.SaleTransactionID = row.SaleTransactionID;
                dto.ListingReference = row.ListingReference;
                dto.Title = row.Title;
                dto.SaleKind = row.SaleKind;
                dto.SalePriceMinor = row.SalePriceMinor;
                dto.SoldAt = row.SoldAt;
                dto.BuyerName = names.GetValueOrDefault(row.BuyerID);
                dto.InvoiceID = row.InvoiceID;
                dto.InvoiceNumber = row.InvoiceNumber;
                dto.InvoiceStatus = row.InvoiceStatus;
                result.Add(dto);
            }

            return result;
        }
    }

    public async Task<InvoiceDetailDTO> IssueForSale(Guid saleTransactionId, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();
        Guid invoiceId;

        using (var context = contextFactory.CreateDbContext())
        {
            invoiceId = await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                var sale = await context.Database
                    .SqlQuery<SaleForInvoice>($@"SELECT t.ID, t.BuyerID, t.BuyerAccountID, t.SalePriceMinor, t.CancelledAt, l.Reference, i.Title
                                                 FROM philmart.Sale_Transaction t WITH (UPDLOCK, HOLDLOCK)
                                                 JOIN philmart.List_Listing l ON l.ID = t.ListingID
                                                 JOIN philmart.Item_Item i ON i.ID = t.ItemID
                                                 WHERE t.ID = {saleTransactionId} AND t.ShopID = {shopId}")
                    .FirstOrDefaultAsync(cancellationToken);

                // another Shop's sale reads as missing, same as one that doesn't exist
                if (sale == null)
                {
                    throw new NotFoundException("Sale", saleTransactionId);
                }

                if (sale.CancelledAt != null)
                {
                    throw new BusinessRuleViolationException("This sale was cancelled, so there's nothing to invoice.");
                }

                // a double click or a retry gets the invoice already raised (N06/N22)
                var existing = await context.Database
                    .SqlQuery<Guid?>($"SELECT InvoiceID AS Value FROM philmart.Sale_InvoiceLine WHERE SaleTransactionID = {saleTransactionId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (existing != null)
                {
                    return existing.Value;
                }

                int count = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Sale_Invoice WITH (UPDLOCK, HOLDLOCK) WHERE ShopID = {shopId}")
                    .FirstAsync(cancellationToken);

                Guid id = Guid.NewGuid();
                string number = "INV-" + (count + 1).ToString("D5");
                long price = sale.SalePriceMinor;

                // Delivery tariffs aren't loaded yet (checklist "Not in Milestone 2"),
                // so there's no shipping line. Lines are written while it's a draft,
                // then it's issued and can't change again (D019).
                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_Invoice (ID, ShopID, BuyerAccountID, BuyerID, InvoiceNumber, State, SubtotalMinor, ShippingMinor, TotalMinor, CreatedBy)
                       VALUES ({id}, {shopId}, {sale.BuyerAccountID}, {sale.BuyerID}, {number}, 'draft', {price}, 0, {price}, {tenant.ActorId})",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_InvoiceLine (InvoiceID, ShopID, SaleTransactionID, LineType, Description, Quantity, UnitAmountMinor, LineTotalMinor, SortOrder)
                       VALUES ({id}, {shopId}, {saleTransactionId}, 'Item_Item', {sale.Reference + " " + sale.Title}, 1, {price}, {price}, 1)",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Sale_Invoice SET State = 'issued', IssuedAt = philmart.ServerNow() WHERE ID = {id}",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Buy_AccountEntry (BuyerAccountID, ShopID, EntryKind, Direction, AmountMinor, InvoiceID, Description, RecordedBy)
                       VALUES ({sale.BuyerAccountID}, {shopId}, 'invoice_raised', 'debit', {price}, {id}, {"Invoice " + number}, {tenant.ActorId})",
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Sale_Invoice", id.ToString(), "Sale_Invoice.issued",
                    new { InvoiceNumber = number, SaleTransactionID = saleTransactionId, TotalMinor = price }, cancellationToken: cancellationToken);

                return id;
            }, cancellationToken);
        }

        return await Get(invoiceId, cancellationToken);
    }

    public async Task<InvoiceDetailDTO> Get(Guid invoiceId, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            var head = await context.Database
                .SqlQuery<InvoiceRow>($@"SELECT ID AS InvoiceID, InvoiceNumber, State, BuyerID, TotalMinor, IssuedAt,
                                                philmart.InvoiceStatus(ID) AS Status, philmart.InvoicePaidMinor(ID) AS PaidMinor
                                         FROM philmart.Sale_Invoice WHERE ID = {invoiceId} AND ShopID = {shopId}")
                .FirstOrDefaultAsync(cancellationToken);

            if (head == null)
            {
                throw new NotFoundException("Invoice", invoiceId);
            }

            var dto = new InvoiceDetailDTO();
            dto.InvoiceID = head.InvoiceID;
            dto.InvoiceNumber = head.InvoiceNumber;
            dto.State = head.State;
            dto.Status = head.Status;
            dto.TotalMinor = head.TotalMinor;
            dto.PaidMinor = head.PaidMinor;
            dto.OutstandingMinor = Math.Max(0, head.TotalMinor - head.PaidMinor);
            dto.IssuedAt = head.IssuedAt;
            dto.BuyerName = (await BuyerNames(context, new[] { head.BuyerID }, cancellationToken)).GetValueOrDefault(head.BuyerID);

            dto.Lines = await context.Database
                .SqlQuery<InvoiceLineDTO>($@"SELECT SaleTransactionID, LineType, Description, LineTotalMinor
                                             FROM philmart.Sale_InvoiceLine WHERE InvoiceID = {invoiceId} ORDER BY SortOrder")
                .ToListAsync(cancellationToken);

            // payments against this invoice, and the reversals linked to them
            dto.Payments = await context.Database
                .SqlQuery<PaymentDTO>($@"SELECT p.ID AS PaymentID, p.AmountMinor, CAST(p.ReceivedOn AS DATETIME2) AS ReceivedOn, p.PaymentReference,
                                                p.RecordedAt, p.ReversesPaymentID, p.ReversalReason,
                                                (SELECT TOP (1) r.ID FROM philmart.Sale_Payment r WHERE r.ReversesPaymentID = p.ID) AS ReversedByPaymentID
                                         FROM philmart.Sale_Payment p
                                         WHERE p.ShopID = {shopId}
                                           AND (p.SpecificInvoiceID = {invoiceId}
                                                OR p.ID IN (SELECT a.PaymentID FROM philmart.Sale_PaymentAllocation a WHERE a.InvoiceID = {invoiceId}))
                                         ORDER BY p.RecordedAt, p.ID")
                .ToListAsync(cancellationToken);

            dto.Ledger = await context.Database
                .SqlQuery<AccountEntryDTO>($@"SELECT e.ID AS EntryID, e.EntryKind, e.Direction, e.AmountMinor, e.Description, e.ReversesEntryID, e.OccurredAt
                                              FROM philmart.Buy_AccountEntry e
                                              WHERE e.ShopID = {shopId}
                                                AND (e.InvoiceID = {invoiceId}
                                                     OR e.PaymentID IN (SELECT p.ID FROM philmart.Sale_Payment p WHERE p.SpecificInvoiceID = {invoiceId})
                                                     OR e.PaymentID IN (SELECT a.PaymentID FROM philmart.Sale_PaymentAllocation a WHERE a.InvoiceID = {invoiceId}))
                                              ORDER BY e.ID")
                .ToListAsync(cancellationToken);

            return dto;
        }
    }

    public async Task<InvoiceDetailDTO> RecordPayment(Guid invoiceId, RecordPaymentRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        if (request.AmountMinor <= 0)
        {
            throw new BusinessRuleViolationException("Enter the amount the Buyer paid.");
        }

        string? reference = string.IsNullOrWhiteSpace(request.PaymentReference) ? null : request.PaymentReference.Trim();
        if (reference != null && reference.Length > 120)
        {
            throw new BusinessRuleViolationException("The payment reference can be at most 120 characters.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                var invoice = await context.Database
                    .SqlQuery<InvoiceForPayment>($@"SELECT ID, BuyerAccountID, State, InvoiceNumber, CAST(philmart.ServerNow() AS DATE) AS Today
                                                    FROM philmart.Sale_Invoice WITH (UPDLOCK, HOLDLOCK)
                                                    WHERE ID = {invoiceId} AND ShopID = {shopId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (invoice == null)
                {
                    throw new NotFoundException("Invoice", invoiceId);
                }

                if (invoice.State != "issued")
                {
                    throw new BusinessRuleViolationException("Payments can only be recorded against an issued invoice.", "D019");
                }

                if (request.ReceivedOn.Date > invoice.Today)
                {
                    throw new BusinessRuleViolationException("The payment date can't be in the future.");
                }

                Guid paymentId = Guid.NewGuid();

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_Payment (ID, ShopID, BuyerAccountID, AmountMinor, ReceivedOn, PaymentReference, SpecificInvoiceID, Note, RecordedBy)
                       VALUES ({paymentId}, {shopId}, {invoice.BuyerAccountID}, {request.AmountMinor}, {request.ReceivedOn.Date}, {reference},
                               {invoiceId}, {request.Note}, {tenant.ActorId})",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Buy_AccountEntry (BuyerAccountID, ShopID, EntryKind, Direction, AmountMinor, PaymentID, InvoiceID, Description, RecordedBy)
                       VALUES ({invoice.BuyerAccountID}, {shopId}, 'payment_received', 'credit', {request.AmountMinor}, {paymentId}, {invoiceId},
                               {"Payment received for " + invoice.InvoiceNumber}, {tenant.ActorId})",
                    cancellationToken);

                // D021: this invoice first, then oldest outstanding, credit only after that
                var residual = new SqlParameter("@residual", SqlDbType.BigInt) { Direction = ParameterDirection.Output };
                await context.Database.ExecuteSqlRawAsync(
                    "EXEC philmart.P_Sale_Payment_Allocate @paymentId, @residual OUTPUT",
                    new object[] { new SqlParameter("@paymentId", paymentId), residual },
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Sale_Payment", paymentId.ToString(), "Sale_Payment.recorded",
                    new { InvoiceID = invoiceId, request.AmountMinor, ReceivedOn = request.ReceivedOn.Date, PaymentReference = reference },
                    cancellationToken: cancellationToken);

                return 0;
            }, cancellationToken);
        }

        return await Get(invoiceId, cancellationToken);
    }

    public async Task<InvoiceDetailDTO> ReversePayment(Guid paymentId, ReversePaymentRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();
        string reason = (request.Reason ?? string.Empty).Trim();

        if (reason.Length == 0)
        {
            throw new BusinessRuleViolationException("Give a reason for the reversal.", "D022");
        }

        if (reason.Length > 1000)
        {
            throw new BusinessRuleViolationException("The reason can be at most 1000 characters.");
        }

        Guid invoiceId;

        using (var context = contextFactory.CreateDbContext())
        {
            invoiceId = await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                var payment = await context.Database
                    .SqlQuery<PaymentRow>($@"SELECT ID, BuyerAccountID, AmountMinor, SpecificInvoiceID, ReversesPaymentID,
                                                    CAST(philmart.ServerNow() AS DATE) AS Today
                                             FROM philmart.Sale_Payment WITH (UPDLOCK, HOLDLOCK)
                                             WHERE ID = {paymentId} AND ShopID = {shopId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (payment == null)
                {
                    throw new NotFoundException("Payment", paymentId);
                }

                if (payment.ReversesPaymentID != null)
                {
                    throw new BusinessRuleViolationException("A reversal can't itself be reversed. Record a new payment instead.", "D022");
                }

                bool alreadyReversed = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.Sale_Payment WITH (UPDLOCK, HOLDLOCK) WHERE ReversesPaymentID = {paymentId}")
                    .FirstAsync(cancellationToken) > 0;

                if (alreadyReversed)
                {
                    throw new BusinessRuleViolationException("This payment has already been reversed.", "D022");
                }

                Guid reversalId = Guid.NewGuid();

                // D022: a new linked row. The original payment is never touched.
                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_Payment (ID, ShopID, BuyerAccountID, AmountMinor, ReceivedOn, SpecificInvoiceID, RecordedBy, ReversesPaymentID, ReversalReason)
                       VALUES ({reversalId}, {shopId}, {payment.BuyerAccountID}, {payment.AmountMinor}, {payment.Today}, {payment.SpecificInvoiceID},
                               {tenant.ActorId}, {paymentId}, {reason})",
                    cancellationToken);

                // unwind each allocation with a linked negative one, so the
                // invoice's paid figure drops back by exactly what this payment gave it
                var allocations = await context.Database
                    .SqlQuery<AllocationRow>($@"SELECT ID, InvoiceID, AmountMinor FROM philmart.Sale_PaymentAllocation
                                                WHERE PaymentID = {paymentId} AND AmountMinor > 0")
                    .ToListAsync(cancellationToken);

                foreach (var allocation in allocations)
                {
                    await context.Database.ExecuteSqlAsync(
                        $@"INSERT INTO philmart.Sale_PaymentAllocation (PaymentID, InvoiceID, ShopID, BuyerAccountID, AmountMinor, AllocationRule, ReversesAllocationID)
                           VALUES ({reversalId}, {allocation.InvoiceID}, {shopId}, {payment.BuyerAccountID}, {-allocation.AmountMinor}, 'reversal', {allocation.ID})",
                        cancellationToken);
                }

                // and the statement shows it as a reversal of the original receipt
                var receipt = await context.Database
                    .SqlQuery<long?>($@"SELECT TOP (1) ID AS Value FROM philmart.Buy_AccountEntry
                                        WHERE PaymentID = {paymentId} AND EntryKind = 'payment_received'")
                    .FirstOrDefaultAsync(cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Buy_AccountEntry (BuyerAccountID, ShopID, EntryKind, Direction, AmountMinor, PaymentID, InvoiceID, ReversesEntryID, Description, Reason, RecordedBy)
                       VALUES ({payment.BuyerAccountID}, {shopId}, 'reversal', 'debit', {payment.AmountMinor}, {reversalId}, {payment.SpecificInvoiceID},
                               {receipt}, N'Payment reversed', {reason}, {tenant.ActorId})",
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "Sale_Payment", reversalId.ToString(), "Sale_Payment.reversed",
                    new { ReversesPaymentID = paymentId, payment.AmountMinor }, reason, cancellationToken);

                if (payment.SpecificInvoiceID != null)
                {
                    return payment.SpecificInvoiceID.Value;
                }

                return allocations.Count > 0 ? allocations[0].InvoiceID : Guid.Empty;
            }, cancellationToken);
        }

        if (invoiceId == Guid.Empty)
        {
            throw new BusinessRuleViolationException("The payment was reversed, but it wasn't linked to an invoice.");
        }

        return await Get(invoiceId, cancellationToken);
    }

    // Buy_Buyer is private to the buyer, so read the names as system, and only
    // for buyers who bought from this Shop (the ids come from its own rows)
    private async Task<Dictionary<Guid, string?>> BuyerNames(PhilmartContext context, IEnumerable<Guid> buyerIds, CancellationToken cancellationToken)
    {
        var names = new Dictionary<Guid, string?>();
        var ids = buyerIds.Distinct().ToList();

        if (ids.Count == 0)
        {
            return names;
        }

        await context.Database.OpenConnectionAsync(cancellationToken);
        await context.AsSystem(tenant.ActorKind, async () =>
        {
            foreach (Guid id in ids)
            {
                names[id] = await context.Database
                    .SqlQuery<string?>($"SELECT FullName AS Value FROM philmart.Buy_Buyer WHERE ID = {id}")
                    .FirstOrDefaultAsync(cancellationToken);
            }
        }, cancellationToken);

        return names;
    }

    private Guid RequireShop()
    {
        if (!tenant.IsShopUser || tenant.ShopId == null)
        {
            throw new NotAuthorisedException("Sign in as a Shop user to do this.");
        }

        return tenant.ShopId.Value;
    }

    private class SaleRow
    {
        public Guid SaleTransactionID { get; set; }

        public string ListingReference { get; set; } = null!;

        public string Title { get; set; } = null!;

        public string SaleKind { get; set; } = null!;

        public long SalePriceMinor { get; set; }

        public DateTimeOffset SoldAt { get; set; }

        public Guid BuyerID { get; set; }

        public Guid? InvoiceID { get; set; }

        public string? InvoiceNumber { get; set; }

        public string? InvoiceStatus { get; set; }
    }

    private class SaleForInvoice
    {
        public Guid ID { get; set; }

        public Guid BuyerID { get; set; }

        public Guid BuyerAccountID { get; set; }

        public long SalePriceMinor { get; set; }

        public DateTimeOffset? CancelledAt { get; set; }

        public string Reference { get; set; } = null!;

        public string Title { get; set; } = null!;
    }

    private class InvoiceRow
    {
        public Guid InvoiceID { get; set; }

        public string InvoiceNumber { get; set; } = null!;

        public string State { get; set; } = null!;

        public Guid BuyerID { get; set; }

        public long TotalMinor { get; set; }

        public DateTimeOffset? IssuedAt { get; set; }

        public string Status { get; set; } = null!;

        public long PaidMinor { get; set; }
    }

    private class InvoiceForPayment
    {
        public Guid ID { get; set; }

        public Guid BuyerAccountID { get; set; }

        public string State { get; set; } = null!;

        public string InvoiceNumber { get; set; } = null!;

        public DateTime Today { get; set; }
    }

    private class PaymentRow
    {
        public Guid ID { get; set; }

        public Guid BuyerAccountID { get; set; }

        public long AmountMinor { get; set; }

        public Guid? SpecificInvoiceID { get; set; }

        public Guid? ReversesPaymentID { get; set; }

        public DateTime Today { get; set; }
    }

    private class AllocationRow
    {
        public long ID { get; set; }

        public Guid InvoiceID { get; set; }

        public long AmountMinor { get; set; }
    }
}
