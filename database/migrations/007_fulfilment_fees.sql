/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 7 of 9 : Sale_Fulfilment, financial triggers, Sell_Seller settlement, PHILMART fees
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------- Sale_Fulfilment ------ */
CREATE TABLE philmart.Sale_Fulfilment (
    ID                      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ful_id DEFAULT NEWSEQUENTIALID()
                                             CONSTRAINT PK_fulfilment PRIMARY KEY,
    SaleTransactionID     UNIQUEIDENTIFIER NOT NULL
                            CONSTRAINT FK_ful_sale REFERENCES philmart.Sale_Transaction(ID),
    ShopID                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ful_shop REFERENCES philmart.Shop_Shop(ID),
    MethodKind             VARCHAR(20)      NOT NULL,
    State                   VARCHAR(30)      NOT NULL CONSTRAINT DF_ful_state DEFAULT ('pending'),

    DispatchedAt           DATETIMEOFFSET(7) NULL,
    DispatchReference      NVARCHAR(120)    NULL,
    Carrier                 NVARCHAR(120)    NULL,

    ReadyForCollectionAt DATETIMEOFFSET(7) NULL,
    CollectedAt            DATETIMEOFFSET(7) NULL,
    CollectedByName       NVARCHAR(200)    NULL,

    /* Set when the financial trigger fires. Never set twice (D023). */
    FinancialTriggerAt    DATETIMEOFFSET(7) NULL,
    FinancialTriggerEvent VARCHAR(30)      NULL,

    CreatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ful_created DEFAULT (philmart.ServerNow()),
    UpdatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ful_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT UQ_ful_sale UNIQUE (SaleTransactionID),
    CONSTRAINT CK_ful_kind CHECK (MethodKind IN ('shipping','collection')),
    CONSTRAINT CK_ful_state CHECK (State IN
        ('pending','dispatched','ready_for_collection','collected')),
    CONSTRAINT CK_ful_trigger_event CHECK (FinancialTriggerEvent IS NULL
        OR FinancialTriggerEvent IN ('dispatch','ready_for_collection')),

    /* D023: shipping triggers on Dispatch; collection triggers on Ready for
       Collection. Actual collection is a LATER event that does not move it.  */
    CONSTRAINT CK_ful_trigger_matches_method CHECK (
        FinancialTriggerEvent IS NULL
        OR (MethodKind = 'shipping'   AND FinancialTriggerEvent = 'dispatch')
        OR (MethodKind = 'collection' AND FinancialTriggerEvent = 'ready_for_collection')),

    CONSTRAINT CK_ful_trigger_pair CHECK (
        (FinancialTriggerAt IS NULL AND FinancialTriggerEvent IS NULL)
        OR (FinancialTriggerAt IS NOT NULL AND FinancialTriggerEvent IS NOT NULL)),

    CONSTRAINT CK_ful_collected_after_ready CHECK (
        CollectedAt IS NULL OR ReadyForCollectionAt IS NOT NULL)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D020/D023. Full Sale_Payment is required before Dispatch or Ready for Collection may be recorded. Shipping: full Sale_Payment + Dispatch fires the financial trigger. Collection: full Sale_Payment + Ready for Collection fires it. CollectedAt is recorded for operational completeness ONLY — it must never be used as a financial trigger and must never fire Seller proceeds or fee accrual again. That is an easy and costly mistake.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_Fulfilment';
GO

CREATE INDEX IX_ful_shop_state ON philmart.Sale_Fulfilment (ShopID, State);
CREATE INDEX IX_ful_trigger ON philmart.Sale_Fulfilment (FinancialTriggerAt)
    WHERE FinancialTriggerAt IS NOT NULL;
GO

/* D024: operational alert only. Does not change workflow state. */
CREATE TABLE philmart.Sale_PaidItemAttention (
    ID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pia_id DEFAULT NEWSEQUENTIALID()
                                    CONSTRAINT PK_paid_item_attention PRIMARY KEY,
    FulfilmentID  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pia_ful REFERENCES philmart.Sale_Fulfilment(ID),
    ShopID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_pia_shop REFERENCES philmart.Shop_Shop(ID),
    FullyPaidAt  DATETIMEOFFSET(7) NOT NULL,
    ThresholdDays INT              NOT NULL,
    RaisedAt      DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_pia_raised DEFAULT (philmart.ServerNow()),
    ClearedAt     DATETIMEOFFSET(7) NULL,
    CONSTRAINT UQ_pia_fulfilment UNIQUE (FulfilmentID)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D024. An OPERATIONAL ALERT when a fully paid Item has not reached Dispatch or Ready for Collection within the Shop-configured attention period. It does not change workflow state, does not block anything, and is cleared by the Sale_Fulfilment event occurring.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sale_PaidItemAttention';
GO

/* ------------------------------------------- Sell_Seller proceeds & payments ---
   D025: proceeds and payments are SEPARATE. Proceeds post on the financial
   trigger; Seller Sale_Payment is the later Shop-controlled settlement.          */
CREATE TABLE philmart.Sell_ProceedsEntry (
    ID                  BIGINT           IDENTITY(1,1) NOT NULL
                                         CONSTRAINT PK_seller_proceeds_entry PRIMARY KEY,
    SellerID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_spe_seller REFERENCES philmart.Sell_Seller(ID),
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_spe_shop REFERENCES philmart.Shop_Shop(ID),
    ItemID             UNIQUEIDENTIFIER NULL CONSTRAINT FK_spe_item REFERENCES philmart.Item_Item(ID),
    SaleTransactionID UNIQUEIDENTIFIER NULL CONSTRAINT FK_spe_sale REFERENCES philmart.Sale_Transaction(ID),
    FulfilmentID       UNIQUEIDENTIFIER NULL CONSTRAINT FK_spe_ful REFERENCES philmart.Sale_Fulfilment(ID),
    EntryKind          VARCHAR(20)      NOT NULL,
    Direction           VARCHAR(10)      NOT NULL,
    GrossAmountMinor  BIGINT           NOT NULL,
    CommissionMinor    BIGINT           NOT NULL CONSTRAINT DF_spe_commission DEFAULT (0),
    NetAmountMinor    BIGINT           NOT NULL,
    CommissionPct      DECIMAL(9,6)     NULL,
    ReversesEntryID   BIGINT           NULL,
    Reason              NVARCHAR(1000)   NULL,
    PostedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_spe_posted DEFAULT (philmart.ServerNow()),
    PostedBy           UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_spe_kind CHECK (EntryKind IN ('proceeds','adjustment','reversal')),
    CONSTRAINT CK_spe_direction CHECK (Direction IN ('debit','credit')),
    CONSTRAINT CK_spe_amounts CHECK (GrossAmountMinor >= 0 AND CommissionMinor >= 0),
    CONSTRAINT CK_spe_net CHECK (NetAmountMinor = GrossAmountMinor - CommissionMinor),
    /* D027: corrections use linked adjustment or reversal entries with a reason. */
    CONSTRAINT CK_spe_correction_reason CHECK (
        EntryKind = 'proceeds' OR (Reason IS NOT NULL AND LEN(LTRIM(RTRIM(Reason))) > 0))
);
GO
ALTER TABLE philmart.Sell_ProceedsEntry ADD CONSTRAINT FK_spe_reverses
    FOREIGN KEY (ReversesEntryID) REFERENCES philmart.Sell_ProceedsEntry(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D025/D027. Proceeds post when the qualifying sale conditions are met — full Sale_Payment plus the Sale_Fulfilment event (D023). Corrections use separate LINKED adjustment or reversal entries; the original proceeds row always remains.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sell_ProceedsEntry';
GO

CREATE TRIGGER philmart.TR_seller_proceeds_append_only
ON philmart.Sell_ProceedsEntry
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50011, 'philmart.seller_proceeds_entry is append-only (D027). Corrections use separate linked adjustment or reversal entries; the original proceeds row always remains.', 1;
END;
GO

CREATE UNIQUE INDEX UX_spe_one_per_fulfilment
    ON philmart.Sell_ProceedsEntry (FulfilmentID)
    WHERE EntryKind = 'proceeds' AND FulfilmentID IS NOT NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D023. The financial trigger fires exactly once per Sale_Fulfilment. This filtered unique index makes double-posting impossible even under concurrent trigger evaluation.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sell_ProceedsEntry',
 @level2type=N'INDEX',@level2name=N'UX_spe_one_per_fulfilment';
GO

CREATE INDEX IX_spe_seller ON philmart.Sell_ProceedsEntry (SellerID, PostedAt);
GO

CREATE TABLE philmart.Sell_Payment (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sp_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_seller_payment PRIMARY KEY,
    SellerID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sp_seller REFERENCES philmart.Sell_Seller(ID),
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sp_shop REFERENCES philmart.Shop_Shop(ID),
    AmountMinor        BIGINT           NOT NULL,
    PaidOn             DATE             NOT NULL,
    Method              NVARCHAR(60)     NULL,
    Reference           NVARCHAR(120)    NULL,
    Note                NVARCHAR(1000)   NULL,
    ReversesPaymentID UNIQUEIDENTIFIER NULL,
    ReversalReason     NVARCHAR(1000)   NULL,
    RecordedAt         DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sp_recorded DEFAULT (philmart.ServerNow()),
    RecordedBy         UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT CK_sp_amount CHECK (AmountMinor > 0),
    /* D026: reversing creates a SEPARATE LINKED entry with a mandatory reason. */
    CONSTRAINT CK_sp_reversal_reason CHECK (
        ReversesPaymentID IS NULL OR (ReversalReason IS NOT NULL
                                        AND LEN(LTRIM(RTRIM(ReversalReason))) > 0))
);
GO
ALTER TABLE philmart.Sell_Payment ADD CONSTRAINT FK_sp_reverses
    FOREIGN KEY (ReversesPaymentID) REFERENCES philmart.Sell_Payment(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D025/D026. The later Shop-controlled settlement against outstanding proceeds. Reversing a Seller Sale_Payment creates a separate linked reversal row, preserves the original, and increases the Seller outstanding balance by the reversed amount. EML-010 fires only for a MATERIAL exceptional reversal (D058). EML-009 and routine EML-011 are retired.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sell_Payment';
GO

CREATE TRIGGER philmart.TR_seller_payment_append_only
ON philmart.Sell_Payment
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50012, 'philmart.seller_payment is append-only (D026). A reversal is a separate linked row; the original Sale_Payment is preserved.', 1;
END;
GO

CREATE INDEX IX_sp_seller ON philmart.Sell_Payment (SellerID, PaidOn);
GO

/* D027: an overpayment may create a recoverable / debit Seller balance, so this
   deliberately has no non-negative clamp.                                    */
CREATE FUNCTION philmart.SellerOutstandingMinor (@sellerId UNIQUEIDENTIFIER)
RETURNS BIGINT
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @proceeds BIGINT = ISNULL((
        SELECT SUM(CASE WHEN Direction = 'credit' THEN NetAmountMinor
                        ELSE -NetAmountMinor END)
        FROM philmart.Sell_ProceedsEntry WHERE SellerID = @sellerId), 0);
    DECLARE @payments BIGINT = ISNULL((
        SELECT SUM(CASE WHEN ReversesPaymentID IS NULL THEN AmountMinor
                        ELSE -AmountMinor END)
        FROM philmart.Sell_Payment WHERE SellerID = @sellerId), 0);
    RETURN @proceeds - @payments;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D027. May legitimately return a NEGATIVE value: an overpayment creates a recoverable or debit Seller balance. Do not clamp it to zero.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'FUNCTION',@level1name=N'SellerOutstandingMinor';
GO

/* ------------------------------------------------------ PHILMART fees -----
   D072/D073: Annual Shop Fee is configured PER SHOP; amounts may differ;
   R0.00 represents a waiver for that Shop, audit recorded.                  */
CREATE TABLE philmart.Fee_ShopConfig (
    ID                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sfc_id DEFAULT NEWSEQUENTIALID()
                                          CONSTRAINT PK_shop_fee_config PRIMARY KEY,
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sfc_shop REFERENCES philmart.Shop_Shop(ID),
    TransactionFeePct  DECIMAL(9,6)     NOT NULL,
    AnnualFeeMinor     BIGINT           NOT NULL CONSTRAINT DF_sfc_annual DEFAULT (0),
    AnnualFeeWaived    AS (CASE WHEN AnnualFeeMinor = 0 THEN CAST(1 AS BIT)
                                  ELSE CAST(0 AS BIT) END) PERSISTED,
    FeeInvoiceDueDays INT              NOT NULL CONSTRAINT DF_sfc_due DEFAULT (30),
    EffectiveFrom       DATE             NOT NULL,
    EffectiveTo         DATE             NULL,
    ChangeReason        NVARCHAR(1000)   NULL,
    CreatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sfc_created DEFAULT (philmart.ServerNow()),
    CreatedBy           UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_sfc_pct CHECK (TransactionFeePct >= 0 AND TransactionFeePct <= 100),
    CONSTRAINT CK_sfc_annual CHECK (AnnualFeeMinor >= 0),
    CONSTRAINT CK_sfc_due CHECK (FeeInvoiceDueDays BETWEEN 1 AND 180),
    CONSTRAINT CK_sfc_effective CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D072/D073. Annual Shop Fee amount is configured per Shop and may differ between Shops. R0.00 (AnnualFeeMinor = 0) represents a WAIVED annual fee for that Shop — not "no annual fee configured". Changing one Shop''s fee never alters another''s. Amount, effective date and waiver changes are audit recorded, hence effective-dated rows rather than an in-place update.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Fee_ShopConfig';
GO

CREATE UNIQUE INDEX UX_sfc_current ON philmart.Fee_ShopConfig (ShopID) WHERE EffectiveTo IS NULL;
GO

CREATE TRIGGER philmart.TR_shop_fee_config_no_delete
ON philmart.Fee_ShopConfig
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50013, 'philmart.shop_fee_config is effective-dated and never deleted (D073). Close the current row with effective_to and insert a new one.', 1;
END;
GO

/* D028: fees accrue transaction-by-transaction ONLY on full Sale_Payment plus
   Dispatch or Ready for Collection, then consolidate into ONE monthly Sale_Invoice. */
CREATE TABLE philmart.Fee_Accrual (
    ID                  BIGINT           IDENTITY(1,1) NOT NULL
                                         CONSTRAINT PK_fee_accrual PRIMARY KEY,
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_fa_shop REFERENCES philmart.Shop_Shop(ID),
    SaleTransactionID UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_fa_sale REFERENCES philmart.Sale_Transaction(ID),
    FulfilmentID       UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_fa_ful REFERENCES philmart.Sale_Fulfilment(ID),
    BaseAmountMinor   BIGINT           NOT NULL,
    FeePct             DECIMAL(9,6)     NOT NULL,
    FeeAmountMinor    BIGINT           NOT NULL,
    AccruedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_fa_accrued DEFAULT (philmart.ServerNow()),
    AccrualPeriod      DATE             NOT NULL,      -- first day of the month
    FeeInvoiceID      UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_fa_fulfilment UNIQUE (FulfilmentID),
    CONSTRAINT CK_fa_amounts CHECK (BaseAmountMinor >= 0 AND FeeAmountMinor >= 0)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D028. One accrual per Sale_Fulfilment, created when the financial trigger fires. UQ_fa_fulfilment makes double-accrual structurally impossible. Rows consolidate into one monthly fee Sale_Invoice per Shop with a detailed supporting schedule that reconciles EXACTLY to the Sale_Invoice total.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Fee_Accrual';
GO

CREATE TRIGGER philmart.TR_fee_accrual_no_delete
ON philmart.Fee_Accrual
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50014, 'philmart.fee_accrual is append-only (D028).', 1;
END;
GO

CREATE INDEX IX_fa_period ON philmart.Fee_Accrual (ShopID, AccrualPeriod)
    WHERE FeeInvoiceID IS NULL;
GO

CREATE TABLE philmart.Fee_Invoice (
    ID               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_fi_id DEFAULT NEWSEQUENTIALID()
                                      CONSTRAINT PK_fee_invoice PRIMARY KEY,
    ShopID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_fi_shop REFERENCES philmart.Shop_Shop(ID),
    Kind             VARCHAR(30)      NOT NULL,
    InvoiceNumber   VARCHAR(40)      NOT NULL CONSTRAINT UQ_fi_number UNIQUE,
    PeriodStart     DATE             NULL,
    PeriodEnd       DATE             NULL,
    FeeYear         SMALLINT         NULL,
    TotalMinor      BIGINT           NOT NULL,
    Currency         CHAR(3)          NOT NULL CONSTRAINT DF_fi_ccy DEFAULT ('ZAR'),
    IssuedAt        DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_fi_issued DEFAULT (philmart.ServerNow()),
    DueAt           DATETIMEOFFSET(7) NOT NULL,
    SupersededByID UNIQUEIDENTIFIER NULL,
    CreatedBy       UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_fi_kind CHECK (Kind IN ('monthly_transaction','annual_shop_fee')),
    CONSTRAINT CK_fi_total CHECK (TotalMinor >= 0),
    CONSTRAINT CK_fi_kind_fields CHECK (
        (Kind = 'monthly_transaction' AND PeriodStart IS NOT NULL AND PeriodEnd IS NOT NULL)
     OR (Kind = 'annual_shop_fee'     AND FeeYear IS NOT NULL))
);
GO
ALTER TABLE philmart.Fee_Invoice ADD CONSTRAINT FK_fi_superseded
    FOREIGN KEY (SupersededByID) REFERENCES philmart.Fee_Invoice(ID);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D075. An issued fee Sale_Invoice is NOT edited in place. Later annual-fee amount changes or waivers apply prospectively to the next 1 January unless PHILMART explicitly posts a separate linked current-year adjustment or credit. There is no automatic proration and no silent retroactive rewrite.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Fee_Invoice';
GO

CREATE UNIQUE INDEX UX_fi_one_annual_per_year ON philmart.Fee_Invoice (ShopID, FeeYear)
    WHERE Kind = 'annual_shop_fee';
CREATE UNIQUE INDEX UX_fi_one_monthly_per_period ON philmart.Fee_Invoice (ShopID, PeriodStart)
    WHERE Kind = 'monthly_transaction';
GO

CREATE TRIGGER philmart.TR_fee_invoice_append_only
ON philmart.Fee_Invoice
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50015, 'philmart.fee_invoice is never deleted (D075). Corrections use a separate linked adjustment or credit.', 1;
END;
GO

ALTER TABLE philmart.Fee_Accrual ADD CONSTRAINT FK_fa_invoice
    FOREIGN KEY (FeeInvoiceID) REFERENCES philmart.Fee_Invoice(ID);
GO

CREATE TABLE philmart.Fee_InvoiceLine (
    ID             BIGINT           IDENTITY(1,1) NOT NULL
                                    CONSTRAINT PK_fee_invoice_line PRIMARY KEY,
    FeeInvoiceID UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_fil_invoice REFERENCES philmart.Fee_Invoice(ID),
    ShopID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_fil_shop REFERENCES philmart.Shop_Shop(ID),
    FeeAccrualID BIGINT           NULL CONSTRAINT FK_fil_accrual REFERENCES philmart.Fee_Accrual(ID),
    Description    NVARCHAR(500)    NOT NULL,
    AmountMinor   BIGINT           NOT NULL,
    SortOrder     INT              NOT NULL CONSTRAINT DF_fil_sort DEFAULT (0)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D028. The detailed supporting schedule. SUM(AmountMinor) must reconcile EXACTLY to Fee_Invoice.total_minor — asserted by test, not assumed.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Fee_InvoiceLine';
GO

CREATE INDEX IX_fil_invoice ON philmart.Fee_InvoiceLine (FeeInvoiceID, SortOrder);
GO

/* D074: monthly and annual fee invoices share ONE allocation pool per Shop. */
CREATE TABLE philmart.Fee_ShopPayment (
    ID                      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sfp_id DEFAULT NEWSEQUENTIALID()
                                             CONSTRAINT PK_shop_fee_payment PRIMARY KEY,
    ShopID                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sfp_shop REFERENCES philmart.Shop_Shop(ID),
    AmountMinor            BIGINT           NOT NULL,
    ReceivedOn             DATE             NOT NULL,
    PaymentReference       NVARCHAR(120)    NULL,
    SpecificFeeInvoiceID UNIQUEIDENTIFIER NULL
                            CONSTRAINT FK_sfp_invoice REFERENCES philmart.Fee_Invoice(ID),
    RecordedAt             DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sfp_recorded DEFAULT (philmart.ServerNow()),
    RecordedBy             UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT CK_sfp_amount CHECK (AmountMinor > 0)
);
GO

CREATE TRIGGER philmart.TR_shop_fee_payment_append_only
ON philmart.Fee_ShopPayment
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50016, 'philmart.shop_fee_payment is append-only.', 1;
END;
GO

CREATE TABLE philmart.Fee_ShopAllocation (
    ID                  BIGINT           IDENTITY(1,1) NOT NULL
                                         CONSTRAINT PK_shop_fee_allocation PRIMARY KEY,
    ShopFeePaymentID UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_sfa_payment REFERENCES philmart.Fee_ShopPayment(ID),
    FeeInvoiceID      UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_sfa_invoice REFERENCES philmart.Fee_Invoice(ID),
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sfa_shop REFERENCES philmart.Shop_Shop(ID),
    AmountMinor        BIGINT           NOT NULL,
    AllocationRule     VARCHAR(30)      NOT NULL,
    AllocatedAt        DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sfa_allocated DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_sfa_amount CHECK (AmountMinor <> 0),
    CONSTRAINT CK_sfa_rule CHECK (AllocationRule IN
        ('specific_reference','oldest_outstanding','credit_application','reversal'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D074/D029. Monthly transaction-fee invoices and Annual Shop Fee invoices share ONE Shop fee-account allocation pool. Specifically referenced Sale_Invoice first; otherwise oldest outstanding fee Sale_Invoice first. Residual Shop credit exists only after ALL outstanding fee invoices are settled, and is then automatically available to future fee invoices.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Fee_ShopAllocation';
GO

CREATE TRIGGER philmart.TR_shop_fee_allocation_append_only
ON philmart.Fee_ShopAllocation
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50017, 'philmart.shop_fee_allocation is append-only (D074).', 1;
END;
GO

CREATE INDEX IX_sfa_invoice ON philmart.Fee_ShopAllocation (FeeInvoiceID);
GO

CREATE VIEW philmart.VW_FeeInvoiceSettlement
AS
SELECT f.ID AS FeeInvoiceID, f.ShopID, f.Kind, f.InvoiceNumber, f.TotalMinor,
       ISNULL(SUM(a.AmountMinor), 0)                  AS PaidMinor,
       f.TotalMinor - ISNULL(SUM(a.AmountMinor), 0)  AS OutstandingMinor,
       f.IssuedAt, f.DueAt,
       CAST(CASE WHEN f.DueAt < philmart.ServerNow()
                  AND f.TotalMinor > ISNULL(SUM(a.AmountMinor), 0)
                 THEN 1 ELSE 0 END AS BIT)             AS IsOverdue
FROM philmart.Fee_Invoice AS f
LEFT JOIN philmart.Fee_ShopAllocation AS a ON a.FeeInvoiceID = f.ID
GROUP BY f.ID, f.ShopID, f.Kind, f.InvoiceNumber, f.TotalMinor, f.IssuedAt, f.DueAt;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D030/D076. EML-017 Fees Due is the normal due notice for BOTH monthly and annual fee invoices. EML-018 Fees Overdue sends only where is_overdue, and must warn of controlled consequences including manual deactivation. Repeated reminders stop once settled. D031: arrears NEVER auto-deactivate a Shop.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'VIEW',@level1name=N'VW_FeeInvoiceSettlement';
GO
