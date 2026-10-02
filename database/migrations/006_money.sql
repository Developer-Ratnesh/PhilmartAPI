/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 6 of 9 : sales, Sale_Fulfilment snapshot, invoices, combined shipping,
                 payments, Buy_Buyer ledger

   Agreement clause 9.3: PHILMART does not operate a wallet or gateway, does not
   hold Buy_Buyer funds, and does not store card or bank credentials. Every table
   here is RECORD KEEPING of a Sale_Payment made directly to the Shop.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* --------------------------------------------------- sale transaction ----- */
CREATE TABLE philmart.Sale_Transaction (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_st_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_sale_transaction PRIMARY KEY,
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_st_shop REFERENCES philmart.Shop_Shop(ID),
    ListingID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_st_listing REFERENCES philmart.List_Listing(ID),
    ItemID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_st_item REFERENCES philmart.Item_Item(ID),
    BuyerID            UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_st_buyer REFERENCES philmart.Buy_Buyer(ID),
    BuyerAccountID    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_st_account REFERENCES philmart.Buy_Account(ID),
    SaleKind           VARCHAR(20)      NOT NULL,
    SalePriceMinor    BIGINT           NOT NULL,
    Currency            CHAR(3)          NOT NULL CONSTRAINT DF_st_ccy DEFAULT ('ZAR'),
    SoldAt             DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_st_sold DEFAULT (philmart.ServerNow()),
    CancelledAt        DATETIMEOFFSET(7) NULL,
    CancellationReason NVARCHAR(1000)   NULL,
    CreatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_st_created DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_st_listing UNIQUE (ListingID),
    CONSTRAINT CK_st_kind CHECK (SaleKind IN ('fixed_price','auction')),
    CONSTRAINT CK_st_price CHECK (SalePriceMinor >= 0),
    CONSTRAINT CK_st_cancel_reason CHECK (
        CancelledAt IS NULL OR (CancellationReason IS NOT NULL
                                 AND LEN(LTRIM(RTRIM(CancellationReason))) > 0))
);
GO

/* D042: the immutable Sale_Fulfilment snapshot. Written once at sale. Later profile
   changes or address deletions do not alter it — ever.                       */
CREATE TABLE philmart.Sale_FulfilmentSnapshot (
    SaleTransactionID  UNIQUEIDENTIFIER NOT NULL
                         CONSTRAINT PK_fulfilment_snapshot PRIMARY KEY
                         CONSTRAINT FK_fs_sale REFERENCES philmart.Sale_Transaction(ID),
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_fs_shop REFERENCES philmart.Shop_Shop(ID),
    DeliveryMethodID   UNIQUEIDENTIFIER NOT NULL
                         CONSTRAINT FK_fs_method REFERENCES philmart.Sys_DeliveryMethod(ID),
    DeliveryMethodCode VARCHAR(40)      NOT NULL,
    DeliveryMethodName NVARCHAR(200)    NOT NULL,
    MethodKind          VARCHAR(20)      NOT NULL,
    /* Values, not references: a snapshot must survive deletion of the source. */
    AddressLine1        NVARCHAR(200)    NULL,
    AddressLine2        NVARCHAR(200)    NULL,
    City                 NVARCHAR(120)    NULL,
    Province             NVARCHAR(120)    NULL,
    PostalCode          VARCHAR(20)      NULL,
    CountryCode         CHAR(2)          NULL,
    PickupPointCode    VARCHAR(40)      NULL,
    PickupPointName    NVARCHAR(200)    NULL,
    PickupPointAddress NVARCHAR(500)    NULL,
    RecipientName       NVARCHAR(200)    NULL,
    RecipientMobile     VARCHAR(40)      NULL,
    ControlledWording   NVARCHAR(MAX)    NULL,
    SupplementaryNotes  NVARCHAR(MAX)    NULL,
    CapturedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_fs_captured DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_fs_kind CHECK (MethodKind IN ('shipping','collection'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D042. Once a sale transaction exists, the selected shipping method, delivery address and/or pickup point are stored as an IMMUTABLE transaction snapshot. Profile changes and deletions do not alter it. Fields are denormalised VALUES on purpose — a foreign key would let a later edit rewrite history.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_FulfilmentSnapshot';
GO

CREATE TRIGGER philmart.TR_fulfilment_snapshot_append_only
ON philmart.Sale_FulfilmentSnapshot
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50007, 'philmart.fulfilment_snapshot is immutable (D042). Profile changes and deletions must not alter a sale''s recorded delivery details.', 1;
END;
GO

/* --------------------------------------------- combined shipping group ----
   D008: a PRE-INVOICING grouping / deferred-invoicing mechanism only.
   There is no post-Sale_Invoice Deferred Delivery state (D007, D008).            */
CREATE TABLE philmart.Sale_CombinedShippingGroup (
    ID                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_csg_id DEFAULT NEWSEQUENTIALID()
                                          CONSTRAINT PK_combined_shipping_group PRIMARY KEY,
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_csg_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_csg_buyer REFERENCES philmart.Buy_Buyer(ID),
    OpenedAt            DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_csg_opened DEFAULT (philmart.ServerNow()),
    ClosedAt            DATETIMEOFFSET(7) NULL,
    InvoicedAt          DATETIMEOFFSET(7) NULL,
    ReminderSentAt     DATETIMEOFFSET(7) NULL,
    FinalShippingMinor BIGINT           NULL,
    CONSTRAINT CK_csg_shipping CHECK (FinalShippingMinor IS NULL OR FinalShippingMinor >= 0),
    CONSTRAINT CK_csg_invoiced_after_closed CHECK (InvoicedAt IS NULL OR ClosedAt IS NOT NULL)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D008. Pre-invoicing grouping only. Once InvoicedAt is set the group is spent — it never becomes a post-Sale_Invoice delivery state. D007: Custom Delivery and the former Deferred Delivery workflow are retired. EML-016 is the controlled pre-invoicing reminder.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_CombinedShippingGroup';
GO

CREATE TABLE philmart.Sale_CombinedShippingMember (
    GroupID            UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_csm_group REFERENCES philmart.Sale_CombinedShippingGroup(ID),
    SaleTransactionID UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_csm_sale REFERENCES philmart.Sale_Transaction(ID),
    AddedAt            DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_csm_added DEFAULT (philmart.ServerNow()),
    CONSTRAINT PK_combined_shipping_member PRIMARY KEY (GroupID, SaleTransactionID),
    CONSTRAINT UQ_csm_sale UNIQUE (SaleTransactionID)
);
GO

/* ----------------------------------------------------------- Sale_Invoice ------ */
CREATE TABLE philmart.Sale_Invoice (
    ID                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_inv_id DEFAULT NEWSEQUENTIALID()
                                          CONSTRAINT PK_invoice PRIMARY KEY,
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_inv_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerAccountID     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_inv_account REFERENCES philmart.Buy_Account(ID),
    BuyerID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_inv_buyer REFERENCES philmart.Buy_Buyer(ID),
    CombinedGroupID    UNIQUEIDENTIFIER NULL
                         CONSTRAINT FK_inv_group REFERENCES philmart.Sale_CombinedShippingGroup(ID),
    InvoiceNumber       VARCHAR(40)      NOT NULL,
    State                VARCHAR(20)      NOT NULL CONSTRAINT DF_inv_state DEFAULT ('draft'),

    SubtotalMinor       BIGINT           NOT NULL CONSTRAINT DF_inv_subtotal DEFAULT (0),
    ShippingMinor       BIGINT           NOT NULL CONSTRAINT DF_inv_shipping DEFAULT (0),
    AdjustmentMinor     BIGINT           NOT NULL CONSTRAINT DF_inv_adjustment DEFAULT (0),
    TotalMinor          BIGINT           NOT NULL CONSTRAINT DF_inv_total DEFAULT (0),
    Currency             CHAR(3)          NOT NULL CONSTRAINT DF_inv_ccy DEFAULT ('ZAR'),

    IssuedAt            DATETIMEOFFSET(7) NULL,
    DueAt               DATETIMEOFFSET(7) NULL,
    CancelledAt         DATETIMEOFFSET(7) NULL,
    CancellationReason  NVARCHAR(1000)   NULL,
    SupersededByID     UNIQUEIDENTIFIER NULL,

    /* Snapshot of the Sale_Payment instructions in force at issue. */
    PaymentInstructions NVARCHAR(MAX)    NULL,

    CreatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_inv_created DEFAULT (philmart.ServerNow()),
    CreatedBy           UNIQUEIDENTIFIER NULL,

    CONSTRAINT UQ_inv_shop_number UNIQUE (ShopID, InvoiceNumber),
    CONSTRAINT CK_inv_state CHECK (State IN ('draft','issued','cancelled')),
    CONSTRAINT CK_inv_amounts CHECK (SubtotalMinor >= 0 AND ShippingMinor >= 0 AND TotalMinor >= 0),
    CONSTRAINT CK_inv_total_consistent CHECK (
        TotalMinor = SubtotalMinor + ShippingMinor + AdjustmentMinor),
    CONSTRAINT CK_inv_issued_has_date CHECK (
        State <> 'issued' OR IssuedAt IS NOT NULL),
    CONSTRAINT CK_inv_cancel_reason CHECK (
        State <> 'cancelled' OR (CancellationReason IS NOT NULL
                                 AND LEN(LTRIM(RTRIM(CancellationReason))) > 0))
);
GO
ALTER TABLE philmart.Sale_Invoice ADD CONSTRAINT FK_inv_superseded
    FOREIGN KEY (SupersededByID) REFERENCES philmart.Sale_Invoice(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D019. Invoice issuance creates the Buy_Buyer Sale_Payment obligation. Invoice, Sale_Payment and Sale_Fulfilment states remain SEPARATE; the existence of an Sale_Invoice is not completion. An issued Sale_Invoice is immutable (TR_invoice_immutable_when_issued, part 9) — corrections use a linked credit, adjustment or superseding Sale_Invoice via SupersededByID. It is never edited.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_Invoice';
GO

CREATE INDEX IX_inv_account_outstanding ON philmart.Sale_Invoice (BuyerAccountID, IssuedAt)
    WHERE State = 'issued';
CREATE INDEX IX_inv_shop_state ON philmart.Sale_Invoice (ShopID, State);
CREATE INDEX IX_inv_due ON philmart.Sale_Invoice (DueAt) WHERE State = 'issued';
GO

CREATE TABLE philmart.Sale_InvoiceLine (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_il_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_invoice_line PRIMARY KEY,
    InvoiceID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_il_invoice REFERENCES philmart.Sale_Invoice(ID),
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_il_shop REFERENCES philmart.Shop_Shop(ID),
    SaleTransactionID UNIQUEIDENTIFIER NULL
                        CONSTRAINT FK_il_sale REFERENCES philmart.Sale_Transaction(ID),
    LineType           VARCHAR(20)      NOT NULL,
    Description         NVARCHAR(500)    NOT NULL,
    Quantity            INT              NOT NULL CONSTRAINT DF_il_qty DEFAULT (1),
    UnitAmountMinor   BIGINT           NOT NULL,
    LineTotalMinor    BIGINT           NOT NULL,
    SortOrder          INT              NOT NULL CONSTRAINT DF_il_sort DEFAULT (0),
    CONSTRAINT CK_il_type CHECK (LineType IN ('Item_Item','shipping','adjustment')),
    CONSTRAINT CK_il_qty CHECK (Quantity > 0),
    CONSTRAINT CK_il_total CHECK (LineTotalMinor = UnitAmountMinor * Quantity)
);
GO
CREATE INDEX IX_il_invoice ON philmart.Sale_InvoiceLine (InvoiceID, SortOrder);
CREATE UNIQUE INDEX UX_il_one_per_sale ON philmart.Sale_InvoiceLine (SaleTransactionID)
    WHERE SaleTransactionID IS NOT NULL;
GO

/* ----------------------------------------------------------- Sale_Payment ------
   Recorded by the Shop. The Buy_Buyer paid the Shop directly, outside PHILMART.  */
CREATE TABLE philmart.Sale_Payment (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pay_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_payment PRIMARY KEY,
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pay_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerAccountID    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pay_account REFERENCES philmart.Buy_Account(ID),
    AmountMinor        BIGINT           NOT NULL,
    Currency            CHAR(3)          NOT NULL CONSTRAINT DF_pay_ccy DEFAULT ('ZAR'),
    ReceivedOn         DATE             NOT NULL,
    PaymentReference   NVARCHAR(120)    NULL,      -- drives specific allocation (D021)
    SpecificInvoiceID UNIQUEIDENTIFIER NULL CONSTRAINT FK_pay_invoice REFERENCES philmart.Sale_Invoice(ID),
    Note                NVARCHAR(1000)   NULL,
    RecordedAt         DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_pay_recorded DEFAULT (philmart.ServerNow()),
    RecordedBy         UNIQUEIDENTIFIER NOT NULL,
    ReversesPaymentID UNIQUEIDENTIFIER NULL,
    ReversalReason     NVARCHAR(1000)   NULL,
    CONSTRAINT CK_pay_amount CHECK (AmountMinor > 0),
    CONSTRAINT CK_pay_reversal_reason CHECK (
        ReversesPaymentID IS NULL OR (ReversalReason IS NOT NULL
                                        AND LEN(LTRIM(RTRIM(ReversalReason))) > 0))
);
GO
ALTER TABLE philmart.Sale_Payment ADD CONSTRAINT FK_pay_reverses
    FOREIGN KEY (ReversesPaymentID) REFERENCES philmart.Sale_Payment(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Agreement clause 9.3. A RECORD of a Sale_Payment the Buy_Buyer made to the Shop directly, outside PHILMART. No gateway, no funds held, no credentials stored. D021: SpecificInvoiceID carries a specific Sale_Invoice reference and is allocated to THAT Sale_Invoice; otherwise allocation is oldest outstanding first. D022: refunds and reversals are SEPARATE LINKED transactions — the original Sale_Payment row is preserved, never edited.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_Payment';
GO

CREATE TRIGGER philmart.TR_payment_append_only
ON philmart.Sale_Payment
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50008, 'philmart.payment is append-only (D022). Refunds and reversals are separate linked transactions; the original Sale_Payment is preserved, never edited.', 1;
END;
GO

CREATE INDEX IX_pay_account ON philmart.Sale_Payment (BuyerAccountID, ReceivedOn, RecordedAt);
GO

/* Allocation of Sale_Payment value to invoices. Append-only; a reallocation is a new
   pair of rows, never an update.                                             */
CREATE TABLE philmart.Sale_PaymentAllocation (
    ID                     BIGINT           IDENTITY(1,1) NOT NULL
                                            CONSTRAINT PK_payment_allocation PRIMARY KEY,
    PaymentID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pa_payment REFERENCES philmart.Sale_Payment(ID),
    InvoiceID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pa_invoice REFERENCES philmart.Sale_Invoice(ID),
    ShopID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pa_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerAccountID       UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pa_account REFERENCES philmart.Buy_Account(ID),
    AmountMinor           BIGINT           NOT NULL,
    AllocatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_pa_allocated DEFAULT (philmart.ServerNow()),
    AllocationRule        VARCHAR(30)      NOT NULL,
    ReversesAllocationID BIGINT           NULL,
    CONSTRAINT CK_pa_amount CHECK (AmountMinor <> 0),
    CONSTRAINT CK_pa_rule CHECK (AllocationRule IN
        ('specific_reference','oldest_outstanding','credit_application','reversal'))
);
GO
ALTER TABLE philmart.Sale_PaymentAllocation ADD CONSTRAINT FK_pa_reverses
    FOREIGN KEY (ReversesAllocationID) REFERENCES philmart.Sale_PaymentAllocation(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D021/D022. Allocation ordering: specific reference first; otherwise oldest outstanding Sale_Invoice first, then next-oldest, until the Sale_Payment is exhausted. Residual credit exists ONLY after all outstanding invoices are settled. Append-only: an unwind is a linked reversal row.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_PaymentAllocation';
GO

CREATE TRIGGER philmart.TR_payment_allocation_append_only
ON philmart.Sale_PaymentAllocation
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50009, 'philmart.payment_allocation is append-only. A reallocation is a new linked reversal row, never an update (D021, D022).', 1;
END;
GO

CREATE INDEX IX_pa_invoice ON philmart.Sale_PaymentAllocation (InvoiceID);
CREATE INDEX IX_pa_account ON philmart.Sale_PaymentAllocation (BuyerAccountID, AllocatedAt);
GO

/* Credits, refunds and adjustments on the Buy_Buyer account (D022). */
CREATE TABLE philmart.Buy_AccountEntry (
    ID                BIGINT           IDENTITY(1,1) NOT NULL
                                       CONSTRAINT PK_buyer_account_entry PRIMARY KEY,
    BuyerAccountID  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bae_account REFERENCES philmart.Buy_Account(ID),
    ShopID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bae_shop REFERENCES philmart.Shop_Shop(ID),
    EntryKind        VARCHAR(30)      NOT NULL,
    Direction         VARCHAR(10)      NOT NULL,
    AmountMinor      BIGINT           NOT NULL,
    InvoiceID        UNIQUEIDENTIFIER NULL CONSTRAINT FK_bae_invoice REFERENCES philmart.Sale_Invoice(ID),
    PaymentID        UNIQUEIDENTIFIER NULL CONSTRAINT FK_bae_payment REFERENCES philmart.Sale_Payment(ID),
    ReversesEntryID BIGINT           NULL,
    Description       NVARCHAR(500)    NOT NULL,
    Reason            NVARCHAR(1000)   NULL,
    OccurredAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bae_occurred DEFAULT (philmart.ServerNow()),
    RecordedBy       UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_bae_kind CHECK (EntryKind IN
        ('invoice_raised','payment_received','allocation','credit_note','refund','reversal','adjustment')),
    CONSTRAINT CK_bae_direction CHECK (Direction IN ('debit','credit')),
    CONSTRAINT CK_bae_amount CHECK (AmountMinor > 0)
);
GO
ALTER TABLE philmart.Buy_AccountEntry ADD CONSTRAINT FK_bae_reverses
    FOREIGN KEY (ReversesEntryID) REFERENCES philmart.Buy_AccountEntry(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D022. The auditable movement log for the Buy_Buyer statement. Append-only. Refunds and reversals are separate linked transactions. Credit never crosses Shops — every row carries ShopID and the account is Shop-scoped (clause 9.3).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_AccountEntry';
GO

CREATE TRIGGER philmart.TR_buyer_account_entry_append_only
ON philmart.Buy_AccountEntry
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50010, 'philmart.buyer_account_entry is append-only (D022). The Buy_Buyer statement preserves auditable account movements.', 1;
END;
GO

CREATE INDEX IX_bae_account ON philmart.Buy_AccountEntry (BuyerAccountID, OccurredAt, ID);
GO

/* ------------------------------------------------ derived settlement ------
   Status is DERIVED, never a stored editable column (BR-16-R07).            */
CREATE FUNCTION philmart.InvoicePaidMinor (@invoiceId UNIQUEIDENTIFIER)
RETURNS BIGINT
WITH SCHEMABINDING
AS
BEGIN
    RETURN (SELECT ISNULL(SUM(AmountMinor), 0)
            FROM philmart.Sale_PaymentAllocation WHERE InvoiceID = @invoiceId);
END;
GO

CREATE FUNCTION philmart.InvoiceStatus (@invoiceId UNIQUEIDENTIFIER)
RETURNS VARCHAR(20)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @paid BIGINT = philmart.InvoicePaidMinor(@invoiceId);
    DECLARE @total BIGINT = (SELECT TotalMinor FROM philmart.Sale_Invoice WHERE ID = @invoiceId);
    RETURN CASE WHEN @paid <= 0 THEN 'unpaid'
                WHEN @paid >= @total THEN 'paid'
                ELSE 'part_paid' END;
END;
GO

CREATE FUNCTION philmart.InvoiceIsFullyPaid (@invoiceId UNIQUEIDENTIFIER)
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN philmart.InvoiceStatus(@invoiceId) = 'paid'
                THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D020. Full Sale_Payment of the relevant Sale_Invoice is required before Dispatch or Ready for Collection. This function is the ONLY gate — call it, do not reimplement the comparison at call sites.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'FUNCTION',@level1name=N'InvoiceIsFullyPaid';
GO

CREATE VIEW philmart.VW_InvoiceSettlement
AS
SELECT i.ID                                        AS InvoiceID,
       i.ShopID,
       i.BuyerAccountID,
       i.InvoiceNumber,
       i.TotalMinor,
       philmart.InvoicePaidMinor(i.ID)           AS PaidMinor,
       i.TotalMinor - philmart.InvoicePaidMinor(i.ID) AS OutstandingMinor,
       philmart.InvoiceStatus(i.ID)               AS Status,
       i.IssuedAt,
       i.DueAt,
       CAST(CASE WHEN i.DueAt IS NOT NULL
                  AND i.DueAt < philmart.ServerNow()
                  AND philmart.InvoiceStatus(i.ID) <> 'paid'
                 THEN 1 ELSE 0 END AS BIT)         AS IsOverdue
FROM philmart.Sale_Invoice AS i
WHERE i.State = 'issued';
GO
