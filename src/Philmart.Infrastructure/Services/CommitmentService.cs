using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Philmart.Application.Commitments;
using Philmart.Application.Registration;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class CommitmentService(IDbContextFactory<PhilmartContext> contextFactory, ITenantContext tenant) : ICommitmentService
{
    private const string BuyNowCommitment = "LEGAL-DEC-001";
    private const string BidCommitment = "LEGAL-DEC-002";

    public async Task<List<PurchaseDefaultsDTO>> GetPurchaseDefaults(Guid listingId, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            var listing = await LoadListing(context, listingId, cancellationToken);
            var methods = await DeliveryOptions.Load(context, listing.ShopID, cancellationToken);
            var result = new List<PurchaseDefaultsDTO>();

            foreach (var m in methods)
            {
                var pref = await LoadPreference(context, buyerId, m.ID, cancellationToken);

                var dto = new PurchaseDefaultsDTO();
                dto.DeliveryMethodID = m.ID;
                dto.PickupPointID = pref?.DefaultPickupPointID;
                dto.Address = await LoadAddress(context, buyerId, pref?.DefaultAddressID, cancellationToken);
                result.Add(dto);
            }

            return result;
        }
    }

    public async Task<PurchaseResultDTO> BuyNow(Guid listingId, BuyNowRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await CheckBuyerCanCommit(context, buyerId, cancellationToken);
            var listing = await LoadListing(context, listingId, cancellationToken);

            if (listing.ListingType != PhilmartConstants.ListingType.FixedPrice)
            {
                throw new BusinessRuleViolationException("This item is sold by auction. Place a bid instead.");
            }

            if (!listing.ShopActive)
            {
                throw new BusinessRuleViolationException("This Shop isn't trading at the moment, so the item can't be bought.", "D032");
            }

            var commitment = await CheckCommitment(context, BuyNowCommitment, request.CommitmentVersionID, cancellationToken);

            // D009: the method has to be one this Shop offers for the item
            var methods = await DeliveryOptions.Load(context, listing.ShopID, cancellationToken);
            var method = methods.FirstOrDefault(x => x.ID == request.DeliveryMethodID);
            if (method == null)
            {
                throw new BusinessRuleViolationException("Choose one of the delivery methods this Shop offers.", "D009");
            }

            var snapshot = await BuildSnapshot(context, buyerId, buyer, method, request, cancellationToken);

            return await context.InTransaction(IsolationLevel.Serializable, async () =>
            {
                // The buyer's session can't write the Shop's sale rows. Everything's
                // been checked above, so write them as system.
                await context.UseSystemSession(buyerId, cancellationToken);

                var locked = await context.Database
                    .SqlQuery<LockedListing>($@"SELECT ID, ShopID, ItemID, State, PriceMinor, ExpiresAt, philmart.ServerNow() AS Now
                                                FROM philmart.List_Listing WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
                                                WHERE ID = {listingId}")
                    .FirstAsync(cancellationToken);

                // a double click, or a retry after a dropped connection
                var existing = await context.Database
                    .SqlQuery<ExistingSale>($"SELECT ID, BuyerID, SalePriceMinor FROM philmart.Sale_Transaction WHERE ListingID = {listingId}")
                    .FirstOrDefaultAsync(cancellationToken);

                if (existing != null)
                {
                    if (existing.BuyerID != buyerId)
                    {
                        throw new BusinessRuleViolationException("Sorry, someone else bought this item first.");
                    }

                    return new PurchaseResultDTO { SaleTransactionID = existing.ID, PriceMinor = existing.SalePriceMinor, DeliveryMethod = method.Name };
                }

                if (locked.State != PhilmartConstants.ListingState.Live || locked.PriceMinor == null)
                {
                    throw new BusinessRuleViolationException("This item is no longer for sale.");
                }

                if (locked.ExpiresAt != null && locked.ExpiresAt <= locked.Now)
                {
                    throw new BusinessRuleViolationException("This listing has expired.", "D063");
                }

                // D044/D045, at the commitment point
                bool restricted = await context.Database
                    .SqlQuery<bool>($"SELECT philmart.BuyerIsRestricted({buyerId}, {locked.ShopID}) AS Value")
                    .FirstAsync(cancellationToken);

                if (restricted)
                {
                    throw new BusinessRuleViolationException("Your account can't buy from this Shop at the moment. Please contact the Shop.", "D044");
                }

                Guid accountId = await BuyerAccounts.Ensure(context, locked.ShopID, buyerId, cancellationToken);
                Guid saleId = Guid.NewGuid();
                long price = locked.PriceMinor.Value;

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_Transaction (ID, ShopID, ListingID, ItemID, BuyerID, BuyerAccountID, SaleKind, SalePriceMinor)
                       VALUES ({saleId}, {locked.ShopID}, {listingId}, {locked.ItemID}, {buyerId}, {accountId}, 'fixed_price', {price})",
                    cancellationToken);

                // D042: values, not references, so a later address edit can't touch it
                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Sale_FulfilmentSnapshot
                           (SaleTransactionID, ShopID, DeliveryMethodID, DeliveryMethodCode, DeliveryMethodName, MethodKind,
                            AddressLine1, AddressLine2, City, Province, PostalCode, CountryCode,
                            PickupPointCode, PickupPointName, PickupPointAddress, RecipientName, RecipientMobile, ControlledWording)
                       VALUES ({saleId}, {locked.ShopID}, {method.ID}, {method.Code}, {method.Name}, {method.MethodKind},
                               {snapshot.AddressLine1}, {snapshot.AddressLine2}, {snapshot.City}, {snapshot.Province}, {snapshot.PostalCode}, {snapshot.CountryCode},
                               {snapshot.PickupPointCode}, {snapshot.PickupPointName}, {snapshot.PickupPointAddress},
                               {buyer.FullName}, {buyer.Mobile}, {snapshot.ControlledWording})",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"UPDATE philmart.List_Listing
                          SET State = 'sold', ClosedAt = philmart.ServerNow(), SoldPriceMinor = {price}, UpdatedAt = philmart.ServerNow()
                        WHERE ID = {listingId}",
                    cancellationToken);

                // D017: sold, fulfilment pending. Not complete.
                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Item_Item SET State = 'sold_fulfilment_pending', UpdatedAt = philmart.ServerNow() WHERE ID = {locked.ItemID}",
                    cancellationToken);

                await RecordAcceptance(context, commitment, buyerId, locked.ShopID, "buy_now", ipAddress, userAgent, cancellationToken);

                await AuditSql.Add(context, buyerId, PhilmartConstants.ActorKind.Buyer, locked.ShopID, "Sale_Transaction", saleId.ToString(),
                    "Sale_Transaction.buy_now",
                    new { ListingID = listingId, PriceMinor = price, DeliveryMethod = method.Code, Commitment = commitment.Version },
                    cancellationToken: cancellationToken);

                return new PurchaseResultDTO { SaleTransactionID = saleId, PriceMinor = price, DeliveryMethod = method.Name };
            }, cancellationToken);
        }
    }

    public async Task<BidResultDTO> PlaceBid(Guid listingId, PlaceBidRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        if (string.IsNullOrWhiteSpace(request.IdempotencyKey) || request.IdempotencyKey.Length > 80)
        {
            throw new BusinessRuleViolationException("Missing or invalid idempotency key.");
        }

        if (request.AmountMinor <= 0)
        {
            throw new BusinessRuleViolationException("Enter a bid amount.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await CheckBuyerCanCommit(context, buyerId, cancellationToken);
            var listing = await LoadListing(context, listingId, cancellationToken);

            if (listing.ListingType != PhilmartConstants.ListingType.Auction)
            {
                throw new BusinessRuleViolationException("This item has a fixed price. Use Buy Now instead.");
            }

            // D032 stops new bidding on a deactivated Shop, but D033 lets an
            // auction that already has bids run to its end
            if (!listing.ShopActive && listing.BidCount == 0)
            {
                throw new BusinessRuleViolationException("This Shop isn't trading at the moment, so the auction isn't taking bids.", "D032");
            }

            var commitment = await CheckCommitment(context, BidCommitment, request.CommitmentVersionID, cancellationToken);

            try
            {
                return await context.InTransaction(IsolationLevel.Serializable, async () =>
                {
                    await context.UseSystemSession(buyerId, cancellationToken);

                    // replay of the same click: hand back the bid we already took
                    var replay = await context.Database
                        .SqlQuery<Guid?>($"SELECT ID AS Value FROM philmart.List_Bid WHERE ListingID = {listingId} AND IdempotencyKey = {request.IdempotencyKey}")
                        .FirstOrDefaultAsync(cancellationToken);

                    if (replay != null)
                    {
                        return await BidResult(context, listingId, replay.Value, buyerId, cancellationToken);
                    }

                    // who's winning right now, for the outbid email afterwards
                    var previousLeader = await context.Database
                        .SqlQuery<Guid?>($@"SELECT TOP (1) BuyerID AS Value FROM philmart.List_Bid
                                            WHERE ListingID = {listingId} ORDER BY AmountMinor DESC, SequenceNo ASC")
                        .FirstOrDefaultAsync(cancellationToken);

                    await RecordAcceptance(context, commitment, buyerId, listing.ShopID, "confirm_bid", ipAddress, userAgent, cancellationToken);

                    // the procedure does the locking, the checks and soft close,
                    // all on database time
                    var bidId = new SqlParameter("@bidId", SqlDbType.UniqueIdentifier) { Direction = ParameterDirection.Output };
                    await context.Database.ExecuteSqlRawAsync(
                        "EXEC philmart.P_List_Bid_Place @listingId, @buyerId, @amountMinor, @idempotencyKey, @bidId OUTPUT",
                        new object[]
                        {
                            new SqlParameter("@listingId", listingId),
                            new SqlParameter("@buyerId", buyerId),
                            new SqlParameter("@amountMinor", request.AmountMinor),
                            new SqlParameter("@idempotencyKey", request.IdempotencyKey),
                            bidId
                        },
                        cancellationToken);

                    Guid placed = (Guid)bidId.Value;

                    if (previousLeader != null && previousLeader != buyerId)
                    {
                        await OutbidAlerts.Send(context, listingId, listing.ShopID, previousLeader.Value, listing.Title, cancellationToken);
                    }

                    return await BidResult(context, listingId, placed, buyerId, cancellationToken);
                }, cancellationToken);
            }
            catch (SqlException ex) when (BidMessages.ContainsKey(ex.Number))
            {
                throw new BusinessRuleViolationException(BidMessages[ex.Number].Message, BidMessages[ex.Number].Decision);
            }
        }
    }

    // P_List_Bid_Place's errors, in words a bidder understands
    private static readonly Dictionary<int, (string Message, string? Decision)> BidMessages = new Dictionary<int, (string, string?)>
    {
        { 50031, ("This auction doesn't exist.", null) },
        { 50032, ("This item isn't an auction.", null) },
        { 50033, ("This auction isn't open for bidding yet.", "D064") },
        { 50034, ("This auction has closed.", "D064") },
        { 50035, ("Your account can't bid with this Shop at the moment. Please contact the Shop.", "D044") },
        { 50036, ("Your bid is below the minimum next bid. Someone may have bid since the page loaded, so check the amount and try again.", null) }
    };

    private static async Task<BidResultDTO> BidResult(PhilmartContext context, Guid listingId, Guid bidId, Guid buyerId, CancellationToken cancellationToken)
    {
        var row = await context.Database
            .SqlQuery<BidRow>($@"SELECT b.ID, b.AmountMinor, b.TriggeredExtension, l.EndsAt,
                                        CAST(CASE WHEN b.ID = (SELECT TOP (1) x.ID FROM philmart.List_Bid x WHERE x.ListingID = l.ID
                                                               ORDER BY x.AmountMinor DESC, x.SequenceNo ASC) THEN 1 ELSE 0 END AS BIT) AS Leading
                                 FROM philmart.List_Bid b JOIN philmart.List_Listing l ON l.ID = b.ListingID
                                 WHERE b.ID = {bidId} AND b.BuyerID = {buyerId}")
            .FirstAsync(cancellationToken);

        var dto = new BidResultDTO();
        dto.BidID = row.ID;
        dto.AmountMinor = row.AmountMinor;
        dto.Leading = row.Leading;
        dto.EndsAt = row.EndsAt;
        dto.ExtendedClose = row.TriggeredExtension;
        return dto;
    }

    private Guid RequireBuyer()
    {
        if (!tenant.IsBuyer || tenant.ActorId == null)
        {
            throw new NotAuthorisedException("Sign in as a buyer to buy or bid.");
        }

        return tenant.ActorId.Value;
    }

    // BR-01-R01 and R09: registered, and nothing superseded waiting to be accepted
    private static async Task<BuyerRow> CheckBuyerCanCommit(PhilmartContext context, Guid buyerId, CancellationToken cancellationToken)
    {
        var buyer = await context.Database
            .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, Mobile, RegistrationCompletedAt FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
            .FirstAsync(cancellationToken);

        if (buyer.RegistrationCompletedAt == null)
        {
            throw new BusinessRuleViolationException("Finish your registration before buying or bidding.", "D036");
        }

        var pending = await AuthService.PendingAcceptances(context, buyerId, cancellationToken);
        if (pending.Count > 0)
        {
            throw new BusinessRuleViolationException("Some of our terms have been updated. Please review and accept them before you buy or bid.", "BR-01-R09");
        }

        return buyer;
    }

    private static async Task<LegalDocumentDTO> CheckCommitment(PhilmartContext context, string code, Guid shownVersionId, CancellationToken cancellationToken)
    {
        var current = await context.Database
            .SqlQuery<LegalDocumentDTO>($@"SELECT v.ID AS VersionID, d.Code, d.Name, v.Version, d.AcceptanceMode, v.Body
                                           FROM philmart.Sys_LegalDocumentVersion v JOIN philmart.Sys_LegalDocument d ON d.Code = v.DocumentCode
                                           WHERE v.DocumentCode = {code} AND v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL")
            .FirstOrDefaultAsync(cancellationToken);

        if (current == null)
        {
            throw new BusinessRuleViolationException("The commitment wording hasn't been published yet, so this can't go ahead.");
        }

        // BR-03-R02: they accept the version they were shown, and it must be current
        if (current.VersionID != shownVersionId)
        {
            throw new BusinessRuleViolationException("The commitment wording has been updated. Please read it again before confirming.", "BR-03-R02");
        }

        return current;
    }

    private static Task RecordAcceptance(PhilmartContext context, LegalDocumentDTO doc, Guid buyerId, Guid shopId, string usedFor, string? ip, string? agent, CancellationToken cancellationToken)
    {
        string? userAgent = agent != null && agent.Length > 500 ? agent.Substring(0, 500) : agent;

        return context.Database.ExecuteSqlAsync(
            $@"INSERT INTO philmart.Sys_LegalAcceptance
                   (VersionID, DocumentCode, DocumentVersion, SubjectKind, BuyerID, ShopID, Context, IpAddress, UserAgent)
               VALUES ({doc.VersionID}, {doc.Code}, {doc.Version}, 'Buy_Buyer', {buyerId}, {shopId}, {usedFor}, {ip}, {userAgent})",
            cancellationToken);
    }

    // D009/D038: start from the buyer's saved default for the method, let this
    // purchase override it, and never write the override back to the profile
    private static async Task<SnapshotValues> BuildSnapshot(PhilmartContext context, Guid buyerId, BuyerRow buyer, DeliveryOptionDTO method, BuyNowRequest request, CancellationToken cancellationToken)
    {
        var values = new SnapshotValues();
        var pref = await LoadPreference(context, buyerId, method.ID, cancellationToken);

        values.ControlledWording = await context.Database
            .SqlQuery<string?>($"SELECT ControlledWording AS Value FROM philmart.Sys_DeliveryMethod WHERE ID = {method.ID}")
            .FirstAsync(cancellationToken);

        if (method.RequiresPickupPoint)
        {
            Guid? pickupId = request.PickupPointID ?? pref?.DefaultPickupPointID;
            var point = await context.Database
                .SqlQuery<PickupRow>($@"SELECT Code, Name, AddressLine1, City, PostalCode FROM philmart.Sys_PickupPoint
                                        WHERE ID = {pickupId} AND DeliveryMethodID = {method.ID} AND Active = 1")
                .FirstOrDefaultAsync(cancellationToken);

            if (point == null)
            {
                throw new BusinessRuleViolationException("Choose a pickup point for " + method.Name + ".", "D009");
            }

            values.PickupPointCode = point.Code;
            values.PickupPointName = point.Name;
            values.PickupPointAddress = string.Join(", ", new[] { point.AddressLine1, point.City, point.PostalCode }.Where(x => !string.IsNullOrWhiteSpace(x)));
            return values;
        }

        if (method.RequiresAddress)
        {
            var address = request.Address ?? await LoadAddress(context, buyerId, pref?.DefaultAddressID, cancellationToken);

            if (address == null || string.IsNullOrWhiteSpace(address.AddressLine1) || string.IsNullOrWhiteSpace(address.City))
            {
                throw new BusinessRuleViolationException("Enter a delivery address.", "D009");
            }

            values.AddressLine1 = address.AddressLine1.Trim();
            values.AddressLine2 = address.AddressLine2;
            values.City = address.City.Trim();
            values.Province = address.Province;
            values.PostalCode = address.PostalCode;
            values.CountryCode = string.IsNullOrWhiteSpace(address.CountryCode) ? "ZA" : address.CountryCode.Trim().ToUpperInvariant();
        }

        return values;
    }

    private static Task<PreferenceRow?> LoadPreference(PhilmartContext context, Guid buyerId, Guid methodId, CancellationToken cancellationToken)
    {
        return context.Database
            .SqlQuery<PreferenceRow>($@"SELECT DefaultPickupPointID, DefaultAddressID FROM philmart.Buy_ShippingPreference
                                        WHERE BuyerID = {buyerId} AND DeliveryMethodID = {methodId} AND Available = 1")
            .FirstOrDefaultAsync(cancellationToken)!;
    }

    // a specific address if the preference names one, otherwise their default
    private static async Task<DeliveryAddressDTO?> LoadAddress(PhilmartContext context, Guid buyerId, Guid? addressId, CancellationToken cancellationToken)
    {
        var rows = await context.Database
            .SqlQuery<DeliveryAddressDTO>($@"SELECT TOP (1) AddressLine1, AddressLine2, City, Province, PostalCode, CountryCode
                                             FROM philmart.Buy_Address
                                             WHERE BuyerID = {buyerId} AND ArchivedAt IS NULL
                                               AND ({addressId} IS NULL OR ID = {addressId})
                                             ORDER BY IsDefault DESC")
            .ToListAsync(cancellationToken);

        return rows.FirstOrDefault();
    }

    private static async Task<ListingRow> LoadListing(PhilmartContext context, Guid listingId, CancellationToken cancellationToken)
    {
        var listing = await context.Database
            .SqlQuery<ListingRow>($@"SELECT l.ID, l.ShopID, l.ListingType, i.Title,
                                            CAST(CASE WHEN s.Status = 'active' THEN 1 ELSE 0 END AS BIT) AS ShopActive,
                                            (SELECT COUNT(*) FROM philmart.List_Bid b WHERE b.ListingID = l.ID) AS BidCount
                                     FROM philmart.List_Listing l
                                     JOIN philmart.Item_Item i ON i.ID = l.ItemID
                                     JOIN philmart.Shop_Shop s ON s.ID = l.ShopID
                                     WHERE l.ID = {listingId}")
            .FirstOrDefaultAsync(cancellationToken);

        if (listing == null)
        {
            throw new NotFoundException("Listing", listingId);
        }

        return listing;
    }

    private class BuyerRow
    {
        public Guid ID { get; set; }

        public string Email { get; set; } = null!;

        public string? FullName { get; set; }

        public string? Mobile { get; set; }

        public DateTimeOffset? RegistrationCompletedAt { get; set; }
    }

    private class ListingRow
    {
        public Guid ID { get; set; }

        public Guid ShopID { get; set; }

        public string ListingType { get; set; } = null!;

        public string Title { get; set; } = null!;

        public bool ShopActive { get; set; }

        public int BidCount { get; set; }
    }

    private class LockedListing
    {
        public Guid ID { get; set; }

        public Guid ShopID { get; set; }

        public Guid ItemID { get; set; }

        public string State { get; set; } = null!;

        public long? PriceMinor { get; set; }

        public DateTimeOffset? ExpiresAt { get; set; }

        public DateTimeOffset Now { get; set; }
    }

    private class ExistingSale
    {
        public Guid ID { get; set; }

        public Guid BuyerID { get; set; }

        public long SalePriceMinor { get; set; }
    }

    private class PreferenceRow
    {
        public Guid? DefaultPickupPointID { get; set; }

        public Guid? DefaultAddressID { get; set; }
    }

    private class PickupRow
    {
        public string Code { get; set; } = null!;

        public string Name { get; set; } = null!;

        public string? AddressLine1 { get; set; }

        public string? City { get; set; }

        public string? PostalCode { get; set; }
    }

    private class BidRow
    {
        public Guid ID { get; set; }

        public long AmountMinor { get; set; }

        public bool TriggeredExtension { get; set; }

        public DateTimeOffset EndsAt { get; set; }

        public bool Leading { get; set; }
    }

    private class SnapshotValues
    {
        public string? AddressLine1 { get; set; }

        public string? AddressLine2 { get; set; }

        public string? City { get; set; }

        public string? Province { get; set; }

        public string? PostalCode { get; set; }

        public string? CountryCode { get; set; }

        public string? PickupPointCode { get; set; }

        public string? PickupPointName { get; set; }

        public string? PickupPointAddress { get; set; }

        public string? ControlledWording { get; set; }
    }
}
