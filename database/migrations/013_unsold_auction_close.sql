/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 13 : unsold auction close

   P_List_Auction_Close (009) moves an unsold auction's Item back to
   ready_to_list without setting ReadyToListSince. CK_item_ready_since is
   checked before TR_item_transition_guard gets to fill it in, so the UPDATE
   is refused and the whole close rolls back. Every auction that ended without
   a winning bid stayed live, and the close job retried it for ever: an
   invalid auction outcome (clause 9.2, BR-13-R13).

   Same procedure as 009 with one line changed: the unsold branch sets
   ReadyToListSince itself. The trigger then sets it again to the same
   ServerNow(), so the D061 ageing clock is unaffected.

   Raised with the Client alongside 011 and 012.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE philmart.P_List_Auction_Close
    @listingId UNIQUEIDENTIFIER,
    @outcome    VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();
    DECLARE @state VARCHAR(20), @endsAt DATETIMEOFFSET(7),
            @reserve BIGINT, @itemId UNIQUEIDENTIFIER;

    SELECT @state = State, @endsAt = EndsAt,
           @reserve = ReservePriceMinor, @itemId = ItemID
    FROM philmart.List_Listing WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @listingId;

    IF @state IS NULL THROW 50037, 'Listing not found.', 1;

    IF @state <> 'live' BEGIN SET @outcome = 'already_closed'; RETURN 0; END
    IF @now < @endsAt  BEGIN SET @outcome = 'not_due';        RETURN 0; END

    DECLARE @winId UNIQUEIDENTIFIER, @winAmount BIGINT;
    SELECT TOP (1) @winId = ID, @winAmount = AmountMinor
    FROM philmart.List_Bid
    WHERE ListingID = @listingId
      AND (@reserve IS NULL OR AmountMinor >= @reserve)
    ORDER BY AmountMinor DESC, SequenceNo ASC;   -- SequenceNo breaks the tie

    IF @winId IS NOT NULL
    BEGIN
        UPDATE philmart.List_Bid SET IsWinning = 1 WHERE ID = @winId;
        UPDATE philmart.List_Listing
           SET State = 'sold', ClosedAt = @now,
               WinningBidID = @winId, SoldPriceMinor = @winAmount
        WHERE ID = @listingId;
        /* D017: sold/Sale_Fulfilment-pending, not complete. EML-012 Auction Won (D056). */
        UPDATE philmart.Item_Item SET State = 'sold_fulfilment_pending' WHERE ID = @itemId;
        SET @outcome = 'sold';
    END
    ELSE
    BEGIN
        /* D012: unsold Listing stays historical and read-only; the underlying
           Item AUTOMATICALLY returns to Ready to List. No reopen, no reoffer. */
        UPDATE philmart.List_Listing SET State = 'unsold', ClosedAt = @now WHERE ID = @listingId;
        UPDATE philmart.Item_Item SET State = 'ready_to_list', ReadyToListSince = @now WHERE ID = @itemId;
        SET @outcome = 'unsold';
    END
    RETURN 0;
END;
GO
