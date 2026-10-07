namespace Philmart.Application.Commitments;

// BR-03. Buy Now and Confirm Bid. Every check happens on the server, hiding a
// button on the page doesn't count (D044).
public interface ICommitmentService
{
    Task<List<PurchaseDefaultsDTO>> GetPurchaseDefaults(Guid listingId, CancellationToken cancellationToken = default);

    Task<PurchaseResultDTO> BuyNow(Guid listingId, BuyNowRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default);

    Task<BidResultDTO> PlaceBid(Guid listingId, PlaceBidRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default);
}
