using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Philmart.Application.Auctions;
using Philmart.Application.Common;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class AuctionService(IDbContextFactory<PhilmartContext> contextFactory, ITenantContext tenant) : IAuctionService
{
    public async Task<List<ShopAuctionDTO>> List(CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            return await context.Database
                .SqlQuery<ShopAuctionDTO>($@"SELECT l.ID AS ListingID, l.ItemID, l.Reference, i.Title, l.State,
                                                    l.StartingPriceMinor, l.ReservePriceMinor,
                                                    (SELECT MAX(b.AmountMinor) FROM philmart.List_Bid b WHERE b.ListingID = l.ID) AS CurrentBidMinor,
                                                    (SELECT COUNT(*) FROM philmart.List_Bid b WHERE b.ListingID = l.ID) AS BidCount,
                                                    l.StartsAt, l.EndsAt, l.ExtensionCount, l.SoldPriceMinor, l.CancellationReason
                                             FROM philmart.List_Listing l JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                             WHERE l.ShopID = {shopId} AND l.ListingType = 'auction'
                                             ORDER BY CASE WHEN l.State IN ('live', 'scheduled') THEN 0 ELSE 1 END, l.EndsAt DESC")
                .ToListAsync(cancellationToken);
        }
    }

    public async Task<AuctionManagementDTO> Get(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();
        AuctionManagementDTO dto;

        // ownership first, under the Shop's own session: RLS and the ShopID both
        // have to agree, otherwise it's not found, the same as an unknown ID
        using (var context = contextFactory.CreateDbContext())
        {
            var row = await context.Database
                .SqlQuery<ManagementRow>($@"SELECT l.ID AS ListingID, l.ItemID, l.Reference, i.Reference AS ItemReference, i.Title, i.State AS ItemState,
                                                   s.FullName AS SellerName, l.State, l.StartingPriceMinor, l.ReservePriceMinor, l.BidIncrementMinor,
                                                   l.StartsAt, l.EndsAt, l.ExtensionCount, l.SoldPriceMinor, l.CancellationReason, l.ClosedAt,
                                                   philmart.ServerNow() AS ServerNow
                                            FROM philmart.List_Listing l
                                            JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                            LEFT JOIN philmart.Sell_Seller s ON s.ID = i.SellerID
                                            WHERE l.ID = {listingId} AND l.ShopID = {shopId} AND l.ListingType = 'auction'")
                .FirstOrDefaultAsync(cancellationToken);

            if (row == null)
            {
                throw new NotFoundException("Auction", listingId);
            }

            dto = new AuctionManagementDTO
            {
                ListingID = row.ListingID,
                ItemID = row.ItemID,
                Reference = row.Reference,
                ItemReference = row.ItemReference,
                Title = row.Title,
                ItemState = row.ItemState,
                SellerName = row.SellerName,
                State = row.State,
                StartingPriceMinor = row.StartingPriceMinor,
                ReservePriceMinor = row.ReservePriceMinor,
                BidIncrementMinor = row.BidIncrementMinor,
                StartsAt = row.StartsAt,
                EndsAt = row.EndsAt,
                ExtensionCount = row.ExtensionCount,
                SoldPriceMinor = row.SoldPriceMinor,
                CancellationReason = row.CancellationReason,
                ClosedAt = row.ClosedAt,
                ServerNow = row.ServerNow,
            };
        }

        // The listing is this Shop's, so its whole trail can be read. The unsold
        // close is audited by the system without a ShopID, so read as system,
        // and only for this one listing.
        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(null, cancellationToken);

            var bids = await context.Database
                .SqlQuery<BidRow>($@"SELECT BuyerID, AmountMinor, PlacedAt, SequenceNo, IsWinning, TriggeredExtension
                                     FROM philmart.List_Bid WHERE ListingID = {listingId} ORDER BY SequenceNo")
                .ToListAsync(cancellationToken);

            var audit = await context.Database
                .SqlQuery<AuditRow>($@"SELECT ID, OccurredAt, Action, Reason, AfterValue FROM philmart.Sys_AuditEvent
                                       WHERE EntityTable = 'List_Listing' AND EntityID = {listingId.ToString()}
                                       ORDER BY ID")
                .ToListAsync(cancellationToken);

            // bidders numbered by first bid, the same number on every row
            var bidderNumbers = new Dictionary<Guid, int>();
            foreach (var b in bids)
            {
                if (!bidderNumbers.ContainsKey(b.BuyerID))
                {
                    bidderNumbers[b.BuyerID] = bidderNumbers.Count + 1;
                }
            }

            var ranked = bids.OrderByDescending(x => x.AmountMinor).ThenBy(x => x.SequenceNo).ToList();
            foreach (var b in ranked)
            {
                dto.Bids.Add(new AuctionBidDTO
                {
                    SequenceNo = b.SequenceNo,
                    Rank = dto.Bids.Count + 1,
                    Bidder = "Bidder " + bidderNumbers[b.BuyerID],
                    AmountMinor = b.AmountMinor,
                    PlacedAt = b.PlacedAt,
                    Leading = dto.Bids.Count == 0 && dto.State != PhilmartConstants.ListingState.Cancelled,
                    Winning = b.IsWinning,
                    ExtendedClose = b.TriggeredExtension,
                });
            }

            dto.BidCount = bids.Count;
            dto.CurrentBidMinor = ranked.Count == 0 ? null : ranked[0].AmountMinor;

            var activity = new List<(DateTimeOffset At, long Order, AuctionActivityDTO Entry)>();

            foreach (var a in audit)
            {
                activity.Add((a.OccurredAt, a.ID, new AuctionActivityDTO
                {
                    At = a.OccurredAt,
                    Action = a.Action,
                    Description = Describe(a, dto),
                    Reason = a.Reason,
                }));
            }

            // going live is the sweep's state change, it has no audit row of its own
            bool opened = dto.State != PhilmartConstants.ListingState.Scheduled && dto.StartsAt <= dto.ServerNow
                          && (dto.ClosedAt == null || dto.ClosedAt > dto.StartsAt);
            if (opened)
            {
                activity.Add((dto.StartsAt, 0, new AuctionActivityDTO
                {
                    At = dto.StartsAt,
                    Action = "auction.live",
                    Description = "Auction opened for bidding",
                }));
            }

            foreach (var b in bids)
            {
                activity.Add((b.PlacedAt, 0, new AuctionActivityDTO
                {
                    At = b.PlacedAt,
                    Action = "bid.placed",
                    Description = "Bid " + b.SequenceNo + ": " + Money.DisplayExact(b.AmountMinor) + " by Bidder " + bidderNumbers[b.BuyerID]
                                  + (b.TriggeredExtension ? ", extended the close" : ""),
                }));
            }

            dto.Activity = activity.OrderBy(x => x.At).ThenBy(x => x.Order).Select(x => x.Entry).ToList();
        }

        return dto;
    }

    private static string Describe(AuditRow a, AuctionManagementDTO dto)
    {
        switch (a.Action)
        {
            case "auction.created":
                return "Auction scheduled";

            case "auction.cancelled":
                return "Cancelled. It had no bids, so the item went back to Ready to List.";

            case PhilmartConstants.AuditAction.AuctionCancelledWithBids:
                return "Cancelled as an exception. Every bid is kept on record and the bidders were told.";

            case "auction.closed":
                if (a.AfterValue != null && a.AfterValue.Contains("\"sold\"", StringComparison.OrdinalIgnoreCase))
                {
                    return "Closed: sold for " + Money.DisplayExact(dto.SoldPriceMinor ?? 0) + " to the highest bidder";
                }

                return "Closed: unsold, the item went back to Ready to List";

            default:
                return a.Action;
        }
    }

    public async Task<List<ReadyItemDTO>> ReadyItems(CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        using (var context = contextFactory.CreateDbContext())
        {
            return await context.Database
                .SqlQuery<ReadyItemDTO>($@"SELECT ID AS ItemID, Reference, Title, SellerMinimumPriceMinor
                                           FROM philmart.Item_Item WHERE ShopID = {shopId} AND State = 'ready_to_list'
                                           ORDER BY Reference")
                .ToListAsync(cancellationToken);
        }
    }

    public async Task<Guid> Create(CreateAuctionRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();

        if (request.StartingPriceMinor < 0 || request.BidIncrementMinor <= 0)
        {
            throw new BusinessRuleViolationException("Enter a starting price and a bid increment above zero.");
        }

        if (request.ReservePriceMinor != null && request.ReservePriceMinor < request.StartingPriceMinor)
        {
            throw new BusinessRuleViolationException("The reserve can't be lower than the starting price.");
        }

        if (request.EndsAt <= request.StartsAt)
        {
            throw new BusinessRuleViolationException("The auction has to end after it starts.", "D064");
        }

        if ((request.SoftCloseSeconds ?? 1) <= 0 || (request.SoftCloseExtensionSeconds ?? 1) <= 0)
        {
            throw new BusinessRuleViolationException("Soft close times have to be more than zero seconds.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            return await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                var now = await context.Database
                    .SqlQuery<DateTimeOffset>($"SELECT philmart.ServerNow() AS Value")
                    .FirstAsync(cancellationToken);

                // D064, checked against database time, not the browser's
                if (request.StartsAt <= now)
                {
                    throw new BusinessRuleViolationException("The start has to be in the future.", "D064");
                }

                var item = await context.Database
                    .SqlQuery<ItemRow>($@"SELECT ID, Reference, State, SellerMinimumPriceMinor FROM philmart.Item_Item WITH (UPDLOCK)
                                          WHERE ID = {request.ItemID} AND ShopID = {shopId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (item == null)
                {
                    throw new NotFoundException("Item", request.ItemID);
                }

                if (item.State != PhilmartConstants.ItemState.ReadyToList)
                {
                    throw new BusinessRuleViolationException("Only a Ready to List item can go to auction.", "D013");
                }

                // D062. TR_listing_seller_minimum_price enforces it too.
                long effectiveMinimum = request.ReservePriceMinor ?? request.StartingPriceMinor;
                if (item.SellerMinimumPriceMinor != null && effectiveMinimum < item.SellerMinimumPriceMinor)
                {
                    throw new BusinessRuleViolationException("The reserve, or the starting price if there's no reserve, is below the Seller Minimum Price for this item.", "D062");
                }

                int previous = await context.Database
                    .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.List_Listing WHERE ShopID = {shopId} AND ItemID = {item.ID}")
                    .FirstAsync(cancellationToken);

                // an item can be offered more than once (D012), each offer is a new listing
                string reference = "A-" + item.Reference + (previous == 0 ? "" : "-" + (previous + 1));
                Guid listingId = Guid.NewGuid();

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.List_Listing
                           (ID, ShopID, ItemID, ListingType, State, Reference, StartingPriceMinor, ReservePriceMinor, BidIncrementMinor,
                            StartsAt, EndsAt, SoftCloseSeconds, SoftCloseExtensionSeconds, CreatedBy)
                       VALUES ({listingId}, {shopId}, {item.ID}, 'auction', 'scheduled', {reference}, {request.StartingPriceMinor},
                               {request.ReservePriceMinor}, {request.BidIncrementMinor}, {request.StartsAt}, {request.EndsAt},
                               {request.SoftCloseSeconds}, {request.SoftCloseExtensionSeconds}, {tenant.ActorId})",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Item_Item SET State = 'listed', UpdatedAt = philmart.ServerNow() WHERE ID = {item.ID}",
                    cancellationToken);

                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "List_Listing", listingId.ToString(),
                    "auction.created",
                    new { ItemID = item.ID, request.StartingPriceMinor, request.ReservePriceMinor, request.StartsAt, request.EndsAt },
                    cancellationToken: cancellationToken);

                return listingId;
            }, cancellationToken);
        }
    }

    public async Task Cancel(Guid listingId, CancelAuctionRequest request, CancellationToken cancellationToken = default)
    {
        Guid shopId = RequireShop();
        string reason = request.Reason.Trim();

        // CK_lst_cancel_reason wants one for every cancellation
        if (reason.Length == 0)
        {
            throw new BusinessRuleViolationException("Give a reason for cancelling.", "D016");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                var listing = await context.Database
                    .SqlQuery<ListingRow>($@"SELECT l.ID, l.ItemID, l.State, l.ListingType, l.EndsAt, i.Title, philmart.ServerNow() AS Now
                                             FROM philmart.List_Listing l WITH (UPDLOCK, HOLDLOCK)
                                             JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                             WHERE l.ID = {listingId} AND l.ShopID = {shopId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (listing == null || listing.ListingType != PhilmartConstants.ListingType.Auction)
                {
                    throw new NotFoundException("Auction", listingId);
                }

                if (listing.State != PhilmartConstants.ListingState.Scheduled && listing.State != PhilmartConstants.ListingState.Live)
                {
                    throw new BusinessRuleViolationException("This auction has already finished, so it can't be cancelled.", "D012");
                }

                if (listing.EndsAt <= listing.Now)
                {
                    throw new BusinessRuleViolationException("This auction has ended and is closing. It can't be cancelled now.");
                }

                var bidders = await context.Database
                    .SqlQuery<BidderRow>($@"SELECT DISTINCT b.BuyerID, u.Email FROM philmart.List_Bid b
                                            JOIN philmart.Buy_Buyer u ON u.ID = b.BuyerID WHERE b.ListingID = {listingId}")
                    .ToListAsync(cancellationToken);

                bool hasBids = bidders.Count > 0;

                // the listing row is locked, and P_List_Bid_Place takes the same
                // lock, so no bid can land between this count and the update
                if (request.ExpectedBidCount != null)
                {
                    int bidCount = await context.Database
                        .SqlQuery<int>($"SELECT COUNT(*) AS Value FROM philmart.List_Bid WHERE ListingID = {listingId}")
                        .FirstAsync(cancellationToken);

                    if (bidCount != request.ExpectedBidCount)
                    {
                        throw new ConflictException("Bids on this auction have changed since you opened it. Nothing was cancelled. Check the auction again before deciding.");
                    }
                }

                // D016: with bids it's the exceptional route, admin-only permission
                if (hasBids && !tenant.Has(PhilmartConstants.Permission.AuctionCancelWithBids))
                {
                    throw new NotAuthorisedException("This auction has bids. Cancelling it needs the 'auction.cancel_with_bids' permission.");
                }

                await context.Database.ExecuteSqlAsync(
                    $@"UPDATE philmart.List_Listing
                          SET State = 'cancelled', CancellationReason = {reason}, ClosedAt = philmart.ServerNow(), UpdatedAt = philmart.ServerNow()
                        WHERE ID = {listingId}",
                    cancellationToken);

                // Bids are kept as they are (D016). ReadyToListSince has to be set here,
                // the check constraint runs before the trigger would fill it in (see 013).
                if (request.ItemMissingOrDamaged)
                {
                    await context.Database.ExecuteSqlAsync(
                        $"UPDATE philmart.Item_Item SET State = 'missing_damaged', RemovalNote = {reason}, UpdatedAt = philmart.ServerNow() WHERE ID = {listing.ItemID}",
                        cancellationToken);
                }
                else
                {
                    await context.Database.ExecuteSqlAsync(
                        $"UPDATE philmart.Item_Item SET State = 'ready_to_list', ReadyToListSince = philmart.ServerNow(), UpdatedAt = philmart.ServerNow() WHERE ID = {listing.ItemID}",
                        cancellationToken);
                }

                string action = hasBids ? PhilmartConstants.AuditAction.AuctionCancelledWithBids : "auction.cancelled";
                await AuditSql.Add(context, tenant.ActorId, tenant.ActorKind, shopId, "List_Listing", listingId.ToString(), action,
                    new { Bidders = bidders.Count, request.ItemMissingOrDamaged }, reason, cancellationToken);

                // EML-015 to everyone who bid (D056). EML-014 is retired, the Shop gets nothing.
                foreach (var b in bidders)
                {
                    await EmailSql.Queue(context, PhilmartConstants.Email.ExceptionalCancellation, b.Email, b.BuyerID, shopId,
                        "Auction cancelled: " + listing.Title,
                        "The auction for " + listing.Title + " has been cancelled by the Shop. Reason: " + reason + "\n\nYour bid has not been taken up and you owe nothing.\n",
                        new { item = listing.Title, reason },
                        cancellationToken);
                }

                return true;
            }, cancellationToken);
        }
    }

    private Guid RequireShop()
    {
        if (!tenant.IsShopUser || tenant.ShopId == null)
        {
            throw new NotAuthorisedException("Sign in as a Shop user to do this.");
        }

        return tenant.ShopId.Value;
    }

    private class ItemRow
    {
        public Guid ID { get; set; }

        public string Reference { get; set; } = null!;

        public string State { get; set; } = null!;

        public long? SellerMinimumPriceMinor { get; set; }
    }

    private class ListingRow
    {
        public Guid ID { get; set; }

        public Guid ItemID { get; set; }

        public string State { get; set; } = null!;

        public string ListingType { get; set; } = null!;

        public DateTimeOffset EndsAt { get; set; }

        public string Title { get; set; } = null!;

        public DateTimeOffset Now { get; set; }
    }

    private class BidderRow
    {
        public Guid BuyerID { get; set; }

        public string Email { get; set; } = null!;
    }

    private class ManagementRow
    {
        public Guid ListingID { get; set; }

        public Guid ItemID { get; set; }

        public string Reference { get; set; } = null!;

        public string ItemReference { get; set; } = null!;

        public string Title { get; set; } = null!;

        public string ItemState { get; set; } = null!;

        public string? SellerName { get; set; }

        public string State { get; set; } = null!;

        public long StartingPriceMinor { get; set; }

        public long? ReservePriceMinor { get; set; }

        public long BidIncrementMinor { get; set; }

        public DateTimeOffset StartsAt { get; set; }

        public DateTimeOffset EndsAt { get; set; }

        public int ExtensionCount { get; set; }

        public long? SoldPriceMinor { get; set; }

        public string? CancellationReason { get; set; }

        public DateTimeOffset? ClosedAt { get; set; }

        public DateTimeOffset ServerNow { get; set; }
    }

    private class BidRow
    {
        public Guid BuyerID { get; set; }

        public long AmountMinor { get; set; }

        public DateTimeOffset PlacedAt { get; set; }

        public long SequenceNo { get; set; }

        public bool IsWinning { get; set; }

        public bool TriggeredExtension { get; set; }
    }

    private class AuditRow
    {
        public long ID { get; set; }

        public DateTimeOffset OccurredAt { get; set; }

        public string Action { get; set; } = null!;

        public string? Reason { get; set; }

        public string? AfterValue { get; set; }
    }
}

public class AuctionCloser(IDbContextFactory<PhilmartContext> contextFactory, ILogger<AuctionCloser> logger) : IAuctionCloser
{
    public async Task<AuctionSweepResult> Sweep(CancellationToken cancellationToken = default)
    {
        var result = new AuctionSweepResult();
        List<Guid> due;

        using (var context = contextFactory.CreateDbContext())
        {
            await context.UseSystemSession(null, cancellationToken);

            // scheduled to live once the start time passes (D064)
            result.Opened = await context.Database.ExecuteSqlAsync(
                $@"UPDATE philmart.List_Listing SET State = 'live', UpdatedAt = philmart.ServerNow()
                   WHERE ListingType = 'auction' AND State = 'scheduled' AND StartsAt <= philmart.ServerNow()",
                cancellationToken);

            due = await context.Database
                .SqlQuery<Guid>($@"SELECT ID AS Value FROM philmart.List_Listing
                                   WHERE ListingType = 'auction' AND State = 'live' AND EndsAt <= philmart.ServerNow()
                                   ORDER BY EndsAt")
                .ToListAsync(cancellationToken);
        }

        foreach (Guid listingId in due)
        {
            try
            {
                string outcome = await Close(listingId, cancellationToken);

                if (outcome == PhilmartConstants.ListingState.Sold)
                {
                    result.Sold++;
                }
                else if (outcome == PhilmartConstants.ListingState.Unsold)
                {
                    result.Unsold++;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // one bad listing mustn't hold up the rest, the next sweep tries again
                logger.LogError(ex, "Closing auction {ListingId} failed", listingId);
            }
        }

        return result;
    }

    private async Task<string> Close(Guid listingId, CancellationToken cancellationToken)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            return await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                await context.UseSystemSession(null, cancellationToken);

                var outcome = new SqlParameter("@outcome", SqlDbType.VarChar, 20) { Direction = ParameterDirection.Output };
                await context.Database.ExecuteSqlRawAsync(
                    "EXEC philmart.P_List_Auction_Close @listingId, @outcome OUTPUT",
                    new object[] { new SqlParameter("@listingId", listingId), outcome },
                    cancellationToken);

                string result = (string)outcome.Value;

                // already_closed means another sweep or server got there first.
                // Only the call that actually closed it writes the sale.
                if (result == PhilmartConstants.ListingState.Sold)
                {
                    var win = await context.Database
                        .SqlQuery<WinRow>($@"SELECT l.ShopID, l.ItemID, b.BuyerID, b.AmountMinor, u.Email, i.Title
                                             FROM philmart.List_Listing l
                                             JOIN philmart.List_Bid b ON b.ID = l.WinningBidID
                                             JOIN philmart.Buy_Buyer u ON u.ID = b.BuyerID
                                             JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                             WHERE l.ID = {listingId}")
                        .FirstAsync(cancellationToken);

                    Guid accountId = await BuyerAccounts.Ensure(context, win.ShopID, win.BuyerID, cancellationToken);
                    Guid saleId = Guid.NewGuid();

                    // the delivery snapshot comes later, when the winner chooses delivery at invoicing (BR-15)
                    await context.Database.ExecuteSqlAsync(
                        $@"INSERT INTO philmart.Sale_Transaction (ID, ShopID, ListingID, ItemID, BuyerID, BuyerAccountID, SaleKind, SalePriceMinor)
                           VALUES ({saleId}, {win.ShopID}, {listingId}, {win.ItemID}, {win.BuyerID}, {accountId}, 'auction', {win.AmountMinor})",
                        cancellationToken);

                    // D056
                    await EmailSql.Queue(context, PhilmartConstants.Email.AuctionWon, win.Email, win.BuyerID, win.ShopID,
                        "You won: " + win.Title,
                        "Congratulations, your bid won the auction for " + win.Title + ". The Shop will send your invoice.\n",
                        new { item = win.Title, amountMinor = win.AmountMinor },
                        cancellationToken);

                    await AuditSql.Add(context, null, PhilmartConstants.ActorKind.System, win.ShopID, "List_Listing", listingId.ToString(),
                        "auction.closed", new { Outcome = result, SaleTransactionID = saleId, win.AmountMinor }, cancellationToken: cancellationToken);
                }
                else if (result == PhilmartConstants.ListingState.Unsold)
                {
                    await AuditSql.Add(context, null, PhilmartConstants.ActorKind.System, null, "List_Listing", listingId.ToString(),
                        "auction.closed", new { Outcome = result }, cancellationToken: cancellationToken);
                }

                return result;
            }, cancellationToken);
        }
    }

    private class WinRow
    {
        public Guid ShopID { get; set; }

        public Guid ItemID { get; set; }

        public Guid BuyerID { get; set; }

        public long AmountMinor { get; set; }

        public string Email { get; set; } = null!;

        public string Title { get; set; } = null!;
    }
}
