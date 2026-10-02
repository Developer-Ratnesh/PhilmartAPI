/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 5 of 9 : listings, auctions, bids, auction events

   The highest-risk area in the system. Agreement clause 9.2 makes an invalid
   auction outcome a Critical Severity Defect that blocks acceptance.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE philmart.List_Listing (
    ID                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_lst_id DEFAULT NEWSEQUENTIALID()
                                          CONSTRAINT PK_listing PRIMARY KEY,
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_lst_shop REFERENCES philmart.Shop_Shop(ID),
    ItemID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_lst_item REFERENCES philmart.Item_Item(ID),
    ListingType         VARCHAR(20)      NOT NULL,
    State                VARCHAR(20)      NOT NULL CONSTRAINT DF_lst_state DEFAULT ('draft'),
    Reference            VARCHAR(40)      NOT NULL,

    /* Fixed price */
    PriceMinor          BIGINT           NULL,
    ListedAt            DATETIMEOFFSET(7) NULL,
    ExpiresAt           DATETIMEOFFSET(7) NULL,          -- listed_at + 90 days max (D063)

    /* Auction */
    AuctionEventID     UNIQUEIDENTIFIER NULL,
    StartingPriceMinor BIGINT           NULL,
    ReservePriceMinor  BIGINT           NULL,
    BidIncrementMinor  BIGINT           NULL,
    StartsAt            DATETIMEOFFSET(7) NULL,
    EndsAt              DATETIMEOFFSET(7) NULL,
    OriginalEndsAt     DATETIMEOFFSET(7) NULL,          -- before any soft-close extension
    SoftCloseSeconds   INT              NULL,
    SoftCloseExtensionSeconds INT      NULL,
    ExtensionCount      INT              NOT NULL CONSTRAINT DF_lst_extcount DEFAULT (0),

    /* Outcome */
    ClosedAt            DATETIMEOFFSET(7) NULL,
    WinningBidID       UNIQUEIDENTIFIER NULL,
    SoldPriceMinor     BIGINT           NULL,
    CancellationReason  NVARCHAR(1000)   NULL,

    CreatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_lst_created DEFAULT (philmart.ServerNow()),
    CreatedBy           UNIQUEIDENTIFIER NULL,
    UpdatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_lst_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT UQ_lst_shop_reference UNIQUE (ShopID, Reference),

    CONSTRAINT CK_lst_type CHECK (ListingType IN ('fixed_price','auction')),
    CONSTRAINT CK_lst_state CHECK (State IN
        ('draft','scheduled','live','sold','unsold','withdrawn','expired','cancelled')),

    CONSTRAINT CK_lst_prices_nonneg CHECK (
        (PriceMinor IS NULL OR PriceMinor >= 0) AND
        (StartingPriceMinor IS NULL OR StartingPriceMinor >= 0) AND
        (ReservePriceMinor IS NULL OR ReservePriceMinor >= 0) AND
        (SoldPriceMinor IS NULL OR SoldPriceMinor >= 0) AND
        (BidIncrementMinor IS NULL OR BidIncrementMinor > 0)),

    /* D063: fixed price maximum live period is 90 days. */
    CONSTRAINT CK_lst_fixed_90_days CHECK (
        ListingType <> 'fixed_price' OR ListedAt IS NULL OR ExpiresAt IS NULL
        OR ExpiresAt <= DATEADD(DAY, 90, ListedAt)),

    /* D064: auction close must be after start. */
    CONSTRAINT CK_lst_auction_window CHECK (
        ListingType <> 'auction' OR StartsAt IS NULL OR EndsAt IS NULL
        OR EndsAt > StartsAt),

    CONSTRAINT CK_lst_fixed_has_price CHECK (
        ListingType <> 'fixed_price' OR State = 'draft' OR PriceMinor IS NOT NULL),

    CONSTRAINT CK_lst_auction_has_terms CHECK (
        ListingType <> 'auction' OR State = 'draft'
        OR (StartingPriceMinor IS NOT NULL AND StartsAt IS NOT NULL AND EndsAt IS NOT NULL)),

    /* D016: an auction cancelled while carrying bids needs a mandatory reason. */
    CONSTRAINT CK_lst_cancel_reason CHECK (
        State <> 'cancelled' OR (CancellationReason IS NOT NULL
                                 AND LEN(LTRIM(RTRIM(CancellationReason))) > 0)),

    /* D064: event timing is inherited and must be populated. */
    CONSTRAINT CK_lst_event_timing_inherited CHECK (
        AuctionEventID IS NULL OR (StartsAt IS NOT NULL AND EndsAt IS NOT NULL))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D063. Fixed Price Listing maximum live period is 90 days. At expiry the Listing becomes historical and read-only and the Item returns to Ready to List for deliberate positive relisting (D015). D012/D013: a historical Listing is NEVER reopened — a further offer of the Item uses a NEW Listing.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_Listing';
GO

/* ONE active Listing per Item. A filtered unique index is the only safe way to
   express this: it holds under concurrency, where an application check does not.
   A filtered index predicate accepts IN, and does NOT accept OR - OR is a
   syntax error that fails CREATE INDEX outright, which silently leaves this
   uniqueness guarantee (D013) absent from the database.                      */
CREATE UNIQUE INDEX UX_lst_one_active_per_item
    ON philmart.List_Listing (ItemID)
    WHERE State IN ('draft', 'scheduled', 'live');
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D013. Creating a Listing ties the Item to it; an Item can carry at most one non-historical Listing at a time. Enforced by filtered unique index because an application-level check loses under concurrent List_Listing creation.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_Listing',
 @level2type=N'INDEX',@level2name=N'UX_lst_one_active_per_item';
GO

CREATE INDEX IX_lst_shop_state ON philmart.List_Listing (ShopID, State);
CREATE INDEX IX_lst_live_fixed ON philmart.List_Listing (ExpiresAt)
    WHERE ListingType = 'fixed_price' AND State = 'live';
CREATE INDEX IX_lst_closing ON philmart.List_Listing (EndsAt)
    WHERE ListingType = 'auction' AND State = 'live';
CREATE INDEX IX_lst_event ON philmart.List_Listing (AuctionEventID)
    WHERE AuctionEventID IS NOT NULL;
GO

/* ------------------------------------------------------------- bids -------
   Append-only. A List_Bid is never edited or deleted, including through an
   exceptional cancellation, where bids and audit are preserved (D016).       */
CREATE TABLE philmart.List_Bid (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bid_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_bid PRIMARY KEY,
    ListingID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bid_listing REFERENCES philmart.List_Listing(ID),
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bid_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerID            UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bid_buyer REFERENCES philmart.Buy_Buyer(ID),
    AmountMinor        BIGINT           NOT NULL,

    /* Authoritative ordering. PlacedAt comes from the database, never the
       client or the application server (Agreement clause 9.2).              */
    PlacedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bid_placed DEFAULT (philmart.ServerNow()),
    SequenceNo         BIGINT           NOT NULL,

    /* Idempotency: a duplicate submission of the same client token is rejected
       rather than creating a second List_Bid.                                     */
    IdempotencyKey     VARCHAR(80)      NOT NULL,

    IsWinning          BIT              NOT NULL CONSTRAINT DF_bid_winning DEFAULT (0),
    TriggeredExtension BIT              NOT NULL CONSTRAINT DF_bid_extension DEFAULT (0),
    IpAddress          VARCHAR(45)      NULL,

    CONSTRAINT CK_bid_amount CHECK (AmountMinor > 0),
    CONSTRAINT UQ_bid_listing_sequence UNIQUE (ListingID, SequenceNo),
    CONSTRAINT UQ_bid_listing_idempotency UNIQUE (ListingID, IdempotencyKey)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Append-only. Agreement clause 9.2: decisions affecting List_Bid validity, price, winner or close state must be transactionally safe so concurrent requests cannot silently overwrite or invalidate one another. Bids survive exceptional cancellation (D016). SequenceNo is monotonic per List_Listing, allocated inside the same SERIALIZABLE transaction as the List_Bid — it is the authoritative ordering for simultaneous bids. Do NOT order by PlacedAt alone, which can tie.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_Bid';
GO

/* Bids may be flagged as winning by P_List_Auction_Close, so UPDATE is allowed only
   for that column; DELETE is never allowed.                                  */
CREATE TRIGGER philmart.TR_bid_no_delete
ON philmart.List_Bid
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50005, 'philmart.bid is append-only. Bids and audit are preserved even through an exceptional auction cancellation (D016).', 1;
END;
GO

CREATE TRIGGER philmart.TR_bid_immutable_columns
ON philmart.List_Bid
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF UPDATE(AmountMinor) OR UPDATE(BuyerID) OR UPDATE(ListingID)
       OR UPDATE(PlacedAt) OR UPDATE(SequenceNo) OR UPDATE(IdempotencyKey)
    BEGIN
        THROW 50006, 'Only is_winning and triggered_extension may be updated on philmart.bid. Amount, bidder, List_Listing, time and ordering are immutable (clause 9.2).', 1;
    END
END;
GO

CREATE INDEX IX_bid_listing ON philmart.List_Bid (ListingID, SequenceNo DESC);
CREATE INDEX IX_bid_buyer ON philmart.List_Bid (BuyerID, PlacedAt DESC);
CREATE UNIQUE INDEX UX_bid_one_winner ON philmart.List_Bid (ListingID) WHERE IsWinning = 1;
GO

ALTER TABLE philmart.List_Listing ADD CONSTRAINT FK_lst_winning_bid
    FOREIGN KEY (WinningBidID) REFERENCES philmart.List_Bid(ID);
GO

/* Outbid alert throttling (D068): 4-hour cooldown, max 3 per Buy_Buyer per auction
   per rolling 24 hours. Affects EMAIL ONLY, never bidding or in-platform state. */
CREATE TABLE philmart.List_OutbidAlertLog (
    ID              BIGINT            IDENTITY(1,1) NOT NULL CONSTRAINT PK_outbid_alert_log PRIMARY KEY,
    ListingID      UNIQUEIDENTIFIER  NOT NULL CONSTRAINT FK_oal_listing REFERENCES philmart.List_Listing(ID),
    ShopID         UNIQUEIDENTIFIER  NOT NULL CONSTRAINT FK_oal_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerID        UNIQUEIDENTIFIER  NOT NULL CONSTRAINT FK_oal_buyer REFERENCES philmart.Buy_Buyer(ID),
    SentAt         DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_oal_sent DEFAULT (philmart.ServerNow()),
    Suppressed      BIT               NOT NULL CONSTRAINT DF_oal_suppressed DEFAULT (0),
    SuppressReason NVARCHAR(200)     NULL
);
GO
CREATE INDEX IX_oal_window ON philmart.List_OutbidAlertLog (BuyerID, ListingID, SentAt DESC);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D068. Every considered EML-013 is logged, sent or suppressed, so throttling is auditable. Cooldown 4 hours; maximum 3 alerts per Buy_Buyer per auction in any rolling 24-hour period. Throttling NEVER affects bidding or in-platform state.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_OutbidAlertLog';
GO

/* ---------------------------------------------------- auction events ------ */
CREATE TABLE philmart.List_AuctionEvent (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ae_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_auction_event PRIMARY KEY,
    Scope               VARCHAR(20)      NOT NULL,
    ShopID             UNIQUEIDENTIFIER NULL CONSTRAINT FK_ae_shop REFERENCES philmart.Shop_Shop(ID),
    Name                NVARCHAR(200)    NOT NULL,
    Description         NVARCHAR(MAX)    NULL,
    StartsAt           DATETIMEOFFSET(7) NOT NULL,
    EndsAt             DATETIMEOFFSET(7) NOT NULL,
    SoftCloseSeconds  INT              NULL,
    SoftCloseExtensionSeconds INT     NULL,
    PublishedAt        DATETIMEOFFSET(7) NULL,
    CancelledAt        DATETIMEOFFSET(7) NULL,
    CancellationReason NVARCHAR(1000)   NULL,
    CreatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ae_created DEFAULT (philmart.ServerNow()),
    CreatedBy          UNIQUEIDENTIFIER NULL,
    UpdatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ae_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_ae_window CHECK (EndsAt > StartsAt),
    CONSTRAINT CK_ae_scope CHECK (Scope IN ('Shop_Shop','philmart')),
    CONSTRAINT CK_ae_scope_shop CHECK (
        (Scope = 'Shop_Shop'     AND ShopID IS NOT NULL) OR
        (Scope = 'philmart' AND ShopID IS NULL))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D064. Auction Event timing is INHERITED and read-only on the individual Auction where it belongs to an event. A PHILMART event may span Shops; Shop isolation still applies to every Shop-controlled record surfaced within it (BR-14-R05).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_AuctionEvent';
GO

ALTER TABLE philmart.List_Listing ADD CONSTRAINT FK_lst_event
    FOREIGN KEY (AuctionEventID) REFERENCES philmart.List_AuctionEvent(ID);
GO

CREATE TABLE philmart.List_AuctionEventShop (
    AuctionEventID UNIQUEIDENTIFIER NOT NULL
                     CONSTRAINT FK_aes_event REFERENCES philmart.List_AuctionEvent(ID),
    ShopID          UNIQUEIDENTIFIER NOT NULL
                     CONSTRAINT FK_aes_shop REFERENCES philmart.Shop_Shop(ID),
    InvitedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_aes_invited DEFAULT (philmart.ServerNow()),
    AcceptedAt      DATETIMEOFFSET(7) NULL,
    CONSTRAINT PK_auction_event_shop PRIMARY KEY (AuctionEventID, ShopID)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Participation register for PHILMART-run events that span multiple Shops (BR-14-R05). Shop isolation is unaffected: a Shop user still sees only its own Shop''s listings within the event.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'List_AuctionEventShop';
GO
