using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Philmart.Api.Configuration;
using Philmart.Application.Invoices;
using Philmart.Domain.Constants;

namespace Philmart.Api.Controllers;

// Schedule A6 technical proof: invoice, Shop-recorded payment, reversal.
// Each action needs its own permission, so a staff user can be given one
// without the others (D050).
[ApiController]
[Authorize]
[Route("api/shop")]
[Produces("application/json")]
public class ShopInvoicesController(IInvoiceService invoices) : ControllerBase
{
    [HttpGet("sales")]
    [RequiresPermission(PhilmartConstants.Permission.InvoiceView)]
    public Task<List<ShopSaleDTO>> Sales(CancellationToken cancellationToken)
    {
        return invoices.Sales(cancellationToken);
    }

    [HttpPost("sales/{saleTransactionId:guid}/invoice")]
    [RequiresPermission(PhilmartConstants.Permission.InvoiceManage)]
    public Task<InvoiceDetailDTO> Issue(Guid saleTransactionId, CancellationToken cancellationToken)
    {
        return invoices.IssueForSale(saleTransactionId, cancellationToken);
    }

    [HttpGet("invoices/{invoiceId:guid}")]
    [RequiresPermission(PhilmartConstants.Permission.InvoiceView)]
    public Task<InvoiceDetailDTO> Get(Guid invoiceId, CancellationToken cancellationToken)
    {
        return invoices.Get(invoiceId, cancellationToken);
    }

    [HttpPost("invoices/{invoiceId:guid}/payments")]
    [RequiresPermission(PhilmartConstants.Permission.PaymentRecord)]
    public Task<InvoiceDetailDTO> RecordPayment(Guid invoiceId, RecordPaymentRequest request, CancellationToken cancellationToken)
    {
        return invoices.RecordPayment(invoiceId, request, cancellationToken);
    }

    [HttpPost("payments/{paymentId:guid}/reverse")]
    [RequiresPermission(PhilmartConstants.Permission.PaymentReverse)]
    public Task<InvoiceDetailDTO> Reverse(Guid paymentId, ReversePaymentRequest request, CancellationToken cancellationToken)
    {
        return invoices.ReversePayment(paymentId, request, cancellationToken);
    }
}
