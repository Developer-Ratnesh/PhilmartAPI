/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 4 of 9 : items, images, state history, bulk upload
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE philmart.Item_Item (
    ID                         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_item_id DEFAULT NEWSEQUENTIALID()
                                                CONSTRAINT PK_item PRIMARY KEY,
    ShopID                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_item_shop REFERENCES philmart.Shop_Shop(ID),
    Reference                  VARCHAR(40)      NOT NULL,
    Title                      NVARCHAR(400)    NOT NULL,
    Description                NVARCHAR(MAX)    NULL,

    /* Classification: PHILMART-controlled reference data (BR-22-R08) */
    AreaCountryID            UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_area REFERENCES philmart.Sys_ClassificationAreaCountry(ID),
    TypeID                    UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_type REFERENCES philmart.Sys_ClassificationType(ID),
    SubtypeID                 UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_subtype REFERENCES philmart.Sys_ClassificationSubtype(ID),
    ThemeID                   UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_theme REFERENCES philmart.Sys_ClassificationTheme(ID),
    FormatID                  UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_format REFERENCES philmart.Sys_ClassificationFormat(ID),
    StampStateID             UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_stampstate REFERENCES philmart.Sys_ClassificationStampState(ID),
    ConditionID               UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_condition REFERENCES philmart.Sys_ItemCondition(ID),
    CatalogueReference        NVARCHAR(120)    NULL,
    YearFrom                  SMALLINT         NULL,
    YearTo                    SMALLINT         NULL,

    StockLocationID          UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_stockloc REFERENCES philmart.Shop_StockLocation(ID),

    /* Ownership. A consigned Item_Item has a Sell_Seller and a Seller Minimum Price. */
    IsConsigned               BIT              NOT NULL CONSTRAINT DF_item_consigned DEFAULT (0),
    SellerID                  UNIQUEIDENTIFIER NULL CONSTRAINT FK_item_seller REFERENCES philmart.Sell_Seller(ID),
    SellerMinimumPriceMinor BIGINT           NULL,

    State                      VARCHAR(30)      NOT NULL CONSTRAINT DF_item_state DEFAULT ('ready_to_list'),
    ReadyToListSince        DATETIMEOFFSET(7) NULL,
    RemovalReason             VARCHAR(30)      NULL,
    RemovalNote               NVARCHAR(1000)   NULL,
    StateChangedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_item_statechanged DEFAULT (philmart.ServerNow()),

    CreatedAt                 DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_item_created DEFAULT (philmart.ServerNow()),
    CreatedBy                 UNIQUEIDENTIFIER NULL,
    UpdatedAt                 DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_item_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT UQ_item_shop_reference UNIQUE (ShopID, Reference),

    CONSTRAINT CK_item_state CHECK (State IN
        ('ready_to_list','listed','sold_fulfilment_pending','complete',
         'removed_from_stock','missing_damaged','returned_to_seller','written_off')),

    CONSTRAINT CK_item_removal_reason CHECK (RemovalReason IS NULL OR RemovalReason IN
        ('damaged','lost','seller_request','pricing','other')),

    CONSTRAINT CK_item_smp_nonneg CHECK (SellerMinimumPriceMinor IS NULL
                                         OR SellerMinimumPriceMinor >= 0),

    /* D062: Seller Minimum Price is the minimum GROSS selling price before Shop
       commission, agreed with the Seller. Consigned stock must carry one.    */
    CONSTRAINT CK_item_consigned_has_seller CHECK (
        IsConsigned = 0 OR (SellerID IS NOT NULL AND SellerMinimumPriceMinor IS NOT NULL)),

    /* D066: Remove from Stock with reason Other requires a mandatory note.   */
    CONSTRAINT CK_item_removal_other_note CHECK (
        RemovalReason IS NULL OR RemovalReason <> 'other'
        OR (RemovalNote IS NOT NULL AND LEN(LTRIM(RTRIM(RemovalNote))) > 0)),

    /* Ageing clock only meaningful while Ready to List (D061).              */
    CONSTRAINT CK_item_ready_since CHECK (
        State <> 'ready_to_list' OR ReadyToListSince IS NOT NULL),

    CONSTRAINT CK_item_years CHECK (YearTo IS NULL OR YearFrom IS NULL OR YearTo >= YearFrom)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D013. An Item is a distinct record from a Listing. Creating a Listing removes the Item from Ready to List and ties it to that Listing; completed Listings are historical and a future offer uses a NEW Listing. D016: state value missing_damaged is a DISTINCT non-saleable state, NOT a boolean flag — OPC-005 in the superseded 7 Sep pack called it a flag, which is contradicted by D016 and the D076 README and must not be implemented. D061: ReadyToListSince drives 60-day Shop attention and 75-day responsible-person escalation; NEITHER threshold automatically changes the Item state. D062: SellerMinimumPriceMinor is GROSS, before Shop commission.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Item_Item';
GO

CREATE INDEX IX_item_shop_state ON philmart.Item_Item (ShopID, State);
CREATE INDEX IX_item_ready_ageing ON philmart.Item_Item (ShopID, ReadyToListSince)
    WHERE State = 'ready_to_list';
CREATE INDEX IX_item_seller ON philmart.Item_Item (SellerID) WHERE IsConsigned = 1;
CREATE INDEX IX_item_classification ON philmart.Item_Item (AreaCountryID, TypeID, ThemeID);
GO

/* Catalogue search. SQL Server Full-Text Search replaces the Postgres
   tsvector/trigram pair. The catalogue is a low-hundreds-of-thousands corpus,
   which FTS handles without a second datastore.
   The full-text catalogue and index are created in part 9, after all tables
   exist, because CREATE FULLTEXT INDEX requires a unique single-column index. */

/* Append-only transition history (BR-10-R12). */
CREATE TABLE philmart.Item_StateHistory (
    ID         BIGINT            IDENTITY(1,1) NOT NULL CONSTRAINT PK_item_state_history PRIMARY KEY,
    ItemID    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT FK_ish_item REFERENCES philmart.Item_Item(ID),
    ShopID    UNIQUEIDENTIFIER  NOT NULL CONSTRAINT FK_ish_shop REFERENCES philmart.Shop_Shop(ID),
    FromState VARCHAR(30)       NULL,
    ToState   VARCHAR(30)       NOT NULL,
    Reason     NVARCHAR(1000)    NULL,
    ListingID UNIQUEIDENTIFIER  NULL,
    ChangedAt DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ish_changed DEFAULT (philmart.ServerNow()),
    ChangedBy UNIQUEIDENTIFIER  NULL,
    ActorKind VARCHAR(20)       NOT NULL CONSTRAINT DF_ish_actorkind DEFAULT ('Shop_User'),
    CONSTRAINT CK_ish_actor_kind CHECK (ActorKind IN
        ('anonymous','Buy_Buyer','Shop_User','platform_admin','system'))
);
GO
CREATE INDEX IX_ish_item ON philmart.Item_StateHistory (ItemID, ChangedAt DESC);
GO

CREATE TRIGGER philmart.TR_item_state_history_append_only
ON philmart.Item_StateHistory
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50004, 'philmart.item_state_history is append-only. Item state history is never rewritten (BR-10-R12).', 1;
END;
GO

/* Legal Item_Item state transitions. Anything not listed here is rejected by the
   guard trigger in part 9. THIS TABLE IS THE STATE MACHINE.                  */
CREATE TABLE philmart.Item_TransitionRule (
    FromState      VARCHAR(30)   NOT NULL,
    ToState        VARCHAR(30)   NOT NULL,
    RequiresReason BIT           NOT NULL CONSTRAINT DF_itr_reason DEFAULT (0),
    DecisionRef    VARCHAR(60)   NOT NULL,
    Note            NVARCHAR(400) NULL,
    CONSTRAINT PK_item_transition_rule PRIMARY KEY (FromState, ToState)
);
GO

INSERT INTO philmart.Item_TransitionRule (FromState, ToState, RequiresReason, DecisionRef, Note) VALUES
 ('ready_to_list','listed',                   0,'D013','Listing created; Item leaves Ready to List'),
 ('ready_to_list','removed_from_stock',       1,'D010','Reversible removal from List_Listing eligibility'),
 ('ready_to_list','missing_damaged',          1,'D016','Distinct non-saleable state'),
 ('ready_to_list','returned_to_seller',       1,'D065','Only at physical handover; terminal'),
 ('ready_to_list','written_off',              1,'D056','Terminal; history remains'),
 ('listed','sold_fulfilment_pending',         0,'D017','Sold fixed price or won auction'),
 ('listed','ready_to_list',                   0,'D012/D014/D015/D016','Unsold, withdrawn, expired or ordinary cancellation'),
 ('listed','missing_damaged',                 1,'D016','Exceptional cancellation path'),
 ('sold_fulfilment_pending','complete',       0,'D017','Full Sale_Payment plus Sale_Fulfilment event'),
 ('sold_fulfilment_pending','ready_to_list',  1,'D018','Cancelled sold transaction, Item still saleable'),
 ('sold_fulfilment_pending','missing_damaged',1,'D018','Cancelled sold transaction, Item not saleable'),
 ('removed_from_stock','ready_to_list',       0,'D010','Restore'),
 ('removed_from_stock','returned_to_seller',  1,'D065','Physical handover'),
 ('removed_from_stock','written_off',         1,'D056','Terminal'),
 ('missing_damaged','written_off',            1,'D056','Permanent terminal removal; Seller notified ONLY here'),
 ('missing_damaged','ready_to_list',          1,'D016','Resolved and saleable again');
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'The Item state machine AS DATA. Any transition absent from this table is rejected by TR_item_transition_guard. Note what is deliberately ABSENT: there is no transition out of returned_to_seller or written_off (both terminal), and no Pending Return intermediate state (D065 removed it — Return to Seller is recorded only at physical handover and goes straight to terminal).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Item_TransitionRule';
GO

/* ------------------------------------------------------------- images ----- */
CREATE TABLE philmart.Item_Image (
    ID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ii_id DEFAULT NEWSEQUENTIALID()
                                     CONSTRAINT PK_item_image PRIMARY KEY,
    ItemID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ii_item REFERENCES philmart.Item_Item(ID),
    ShopID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ii_shop REFERENCES philmart.Shop_Shop(ID),
    StorageKey     NVARCHAR(500)    NOT NULL,
    ContentType    VARCHAR(60)      NOT NULL,
    ByteSize       BIGINT           NOT NULL,
    WidthPx        INT              NULL,
    HeightPx       INT              NULL,
    ChecksumSha256 CHAR(64)         NOT NULL,
    SortOrder      INT              NOT NULL CONSTRAINT DF_ii_sort DEFAULT (0),
    IsPrimary      BIT              NOT NULL CONSTRAINT DF_ii_primary DEFAULT (0),
    UploadedAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ii_uploaded DEFAULT (philmart.ServerNow()),
    UploadedBy     UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_ii_size CHECK (ByteSize > 0),
    CONSTRAINT CK_ii_type CHECK (ContentType IN ('image/jpeg','image/png','image/webp'))
);
GO
CREATE UNIQUE INDEX UX_ii_one_primary ON philmart.Item_Image (ItemID) WHERE IsPrimary = 1;
CREATE INDEX IX_ii_item ON philmart.Item_Image (ItemID, SortOrder);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'One of only two user-supplied file paths into the system (the other is the bulk workbook). Content type and size are validated at the data layer as well as the application layer.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Item_Image';
GO

/* ------------------------------------------------------- bulk upload ------
   BR-11. XLSX against the controlled template, validated before any commit.  */
CREATE TABLE philmart.Item_BulkUploadBatch (
    ID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bub_id DEFAULT NEWSEQUENTIALID()
                                       CONSTRAINT PK_bulk_upload_batch PRIMARY KEY,
    ShopID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bub_shop REFERENCES philmart.Shop_Shop(ID),
    OriginalFilename NVARCHAR(400)    NOT NULL,
    StorageKey       NVARCHAR(500)    NOT NULL,
    ChecksumSha256   CHAR(64)         NOT NULL,
    State             VARCHAR(30)      NOT NULL CONSTRAINT DF_bub_state DEFAULT ('uploaded'),
    [RowCount]       INT              NOT NULL CONSTRAINT DF_bub_rows DEFAULT (0),
    ValidCount       INT              NOT NULL CONSTRAINT DF_bub_valid DEFAULT (0),
    ErrorCount       INT              NOT NULL CONSTRAINT DF_bub_errors DEFAULT (0),
    WarningCount     INT              NOT NULL CONSTRAINT DF_bub_warnings DEFAULT (0),
    ImportValidOnly BIT              NOT NULL CONSTRAINT DF_bub_validonly DEFAULT (0),
    UploadedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bub_uploaded DEFAULT (philmart.ServerNow()),
    UploadedBy       UNIQUEIDENTIFIER NULL,
    ImportedAt       DATETIMEOFFSET(7) NULL,
    CONSTRAINT CK_bub_state CHECK (State IN
        ('uploaded','validating','validation_failed','validated','imported','abandoned'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'BR-11-R04. A batch is all-or-nothing unless the Shop EXPLICITLY elects to import only the valid rows. Partial silent import is never permitted, which is why ImportValidOnly defaults to 0 and must be set by a deliberate user action.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Item_BulkUploadBatch';
GO

CREATE TABLE philmart.Item_BulkUploadRow (
    ID              BIGINT           IDENTITY(1,1) NOT NULL CONSTRAINT PK_bulk_upload_row PRIMARY KEY,
    BatchID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bur_batch REFERENCES philmart.Item_BulkUploadBatch(ID),
    ShopID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bur_shop REFERENCES philmart.Shop_Shop(ID),
    RowNumber      INT              NOT NULL,
    RawPayload     NVARCHAR(MAX)    NOT NULL,
    IsValid        BIT              NOT NULL CONSTRAINT DF_bur_valid DEFAULT (0),
    Errors          NVARCHAR(MAX)    NULL,
    Warnings        NVARCHAR(MAX)    NULL,
    CreatedItemID UNIQUEIDENTIFIER NULL CONSTRAINT FK_bur_item REFERENCES philmart.Item_Item(ID),
    CONSTRAINT UQ_bur_batch_row UNIQUE (BatchID, RowNumber),
    CONSTRAINT CK_bur_payload_json CHECK (ISJSON(RawPayload) = 1),
    CONSTRAINT CK_bur_errors_json CHECK (Errors IS NULL OR ISJSON(Errors) = 1),
    CONSTRAINT CK_bur_warnings_json CHECK (Warnings IS NULL OR ISJSON(Warnings) = 1)
);
GO
CREATE INDEX IX_bur_invalid ON philmart.Item_BulkUploadRow (BatchID) WHERE IsValid = 0;
GO
