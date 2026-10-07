namespace Philmart.Application.Auctions;

// BR-13, the Shop side. Bidding itself is in ICommitmentService (BR-03).
public interface IAuctionService
{
    Task<List<ShopAuctionDTO>> List(CancellationToken cancellationToken = default);

    // Ready to List stock, what an auction can be created from
    Task<List<ReadyItemDTO>> ReadyItems(CancellationToken cancellationToken = default);

    Task<Guid> Create(CreateAuctionRequest request, CancellationToken cancellationToken = default);

    Task Cancel(Guid listingId, CancelAuctionRequest request, CancellationToken cancellationToken = default);
}

// Run by the background job, and on boot as the recovery sweep. Safe to run
// any number of times, from any number of servers: closing is idempotent.
public interface IAuctionCloser
{
    Task<AuctionSweepResult> Sweep(CancellationToken cancellationToken = default);
}
