namespace Philmart.Application.Support;

// BR-02-R07, SCR-PUB-015. Goes to PHILMART, not to a Shop. Shop questions are
// Buyer Queries (BR-05).
public interface ISupportService
{
    Task<List<SupportCategoryDTO>> GetCategories(CancellationToken cancellationToken = default);

    Task<SupportReceiptDTO> Submit(SupportRequest request, CancellationToken cancellationToken = default);
}
