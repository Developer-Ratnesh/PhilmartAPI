namespace Philmart.Application.Invoices;

public interface IInvoiceService
{
    // the Shop's sales, newest first, with any invoice and its derived status
    Task<List<ShopSaleDTO>> Sales(CancellationToken cancellationToken = default);

    // D019: raises and issues the invoice for one sale. Asking again hands back
    // the same invoice, so a double click can't raise two.
    Task<InvoiceDetailDTO> IssueForSale(Guid saleTransactionId, CancellationToken cancellationToken = default);

    Task<InvoiceDetailDTO> Get(Guid invoiceId, CancellationToken cancellationToken = default);

    // Agreement clause 9.3: a record of money the Buyer paid the Shop directly.
    // Allocated by D021 (this invoice first, then oldest outstanding).
    Task<InvoiceDetailDTO> RecordPayment(Guid invoiceId, RecordPaymentRequest request, CancellationToken cancellationToken = default);

    // D022: a separate linked reversal. The original payment stays as it was.
    Task<InvoiceDetailDTO> ReversePayment(Guid paymentId, ReversePaymentRequest request, CancellationToken cancellationToken = default);
}
