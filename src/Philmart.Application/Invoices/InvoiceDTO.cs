namespace Philmart.Application.Invoices;

// Schedule A6 early technical proof: an invoice, a Shop-recorded Buyer payment
// and a permitted reversal. The full BR-15/BR-16 screens are Milestone 3/4.

public class ShopSaleDTO
{
    public Guid SaleTransactionID { get; set; }

    public string ListingReference { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string SaleKind { get; set; } = string.Empty;

    public long SalePriceMinor { get; set; }

    public DateTimeOffset SoldAt { get; set; }

    public string? BuyerName { get; set; }

    public Guid? InvoiceID { get; set; }

    public string? InvoiceNumber { get; set; }

    // unpaid, part_paid or paid, worked out from the allocations (BR-16-R07)
    public string? InvoiceStatus { get; set; }
}

public class InvoiceDetailDTO
{
    public Guid InvoiceID { get; set; }

    public string InvoiceNumber { get; set; } = string.Empty;

    public string State { get; set; } = string.Empty;

    public string Status { get; set; } = string.Empty;

    public long TotalMinor { get; set; }

    public long PaidMinor { get; set; }

    public long OutstandingMinor { get; set; }

    public DateTimeOffset? IssuedAt { get; set; }

    public string? BuyerName { get; set; }

    public List<InvoiceLineDTO> Lines { get; set; } = new List<InvoiceLineDTO>();

    public List<PaymentDTO> Payments { get; set; } = new List<PaymentDTO>();

    // the Buyer Account statement rows for this invoice, oldest first (D076 s20)
    public List<AccountEntryDTO> Ledger { get; set; } = new List<AccountEntryDTO>();
}

public class InvoiceLineDTO
{
    public Guid? SaleTransactionID { get; set; }

    public string LineType { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public long LineTotalMinor { get; set; }
}

public class PaymentDTO
{
    public Guid PaymentID { get; set; }

    public long AmountMinor { get; set; }

    public DateTime ReceivedOn { get; set; }

    public string? PaymentReference { get; set; }

    public DateTimeOffset RecordedAt { get; set; }

    // set on a reversal row: the payment it reverses and why
    public Guid? ReversesPaymentID { get; set; }

    public string? ReversalReason { get; set; }

    // set on an original payment that has since been reversed
    public Guid? ReversedByPaymentID { get; set; }
}

public class AccountEntryDTO
{
    public long EntryID { get; set; }

    public string EntryKind { get; set; } = string.Empty;

    public string Direction { get; set; } = string.Empty;

    public long AmountMinor { get; set; }

    public string Description { get; set; } = string.Empty;

    public long? ReversesEntryID { get; set; }

    public DateTimeOffset OccurredAt { get; set; }
}

public class RecordPaymentRequest
{
    public long AmountMinor { get; set; }

    public DateTime ReceivedOn { get; set; }

    public string? PaymentReference { get; set; }

    public string? Note { get; set; }
}

public class ReversePaymentRequest
{
    public string Reason { get; set; } = string.Empty;
}
