/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 8 of 9 : Buy_Buyer queries, notifications, email, governance, reporting
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------ Buy_Buyer queries -----
   D046: ONE persistent threaded case. Not a Shop copy plus a Buy_Buyer copy.    */
CREATE TABLE philmart.Buy_Query (
    ID                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bq_id DEFAULT NEWSEQUENTIALID()
                                          CONSTRAINT PK_buyer_query PRIMARY KEY,
    ShopID              UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bq_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bq_buyer REFERENCES philmart.Buy_Buyer(ID),
    Reference            VARCHAR(40)      NOT NULL CONSTRAINT UQ_bq_reference UNIQUE,
    Subject              NVARCHAR(400)    NOT NULL,
    ItemID              UNIQUEIDENTIFIER NULL CONSTRAINT FK_bq_item REFERENCES philmart.Item_Item(ID),
    ListingID           UNIQUEIDENTIFIER NULL CONSTRAINT FK_bq_listing REFERENCES philmart.List_Listing(ID),
    Status               VARCHAR(20)      NOT NULL CONSTRAINT DF_bq_status DEFAULT ('awaiting_shop'),
    OpenedAt            DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bq_opened DEFAULT (philmart.ServerNow()),
    LastMessageAt      DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bq_lastmsg DEFAULT (philmart.ServerNow()),
    AwaitingBuyerSince DATETIMEOFFSET(7) NULL,     -- starts the 14-day auto-close clock
    ClosedAt            DATETIMEOFFSET(7) NULL,
    ClosedBy            UNIQUEIDENTIFIER NULL,
    CloseKind           VARCHAR(20)      NULL,
    ReopenedCount       INT              NOT NULL CONSTRAINT DF_bq_reopened DEFAULT (0),
    InboundToken        VARCHAR(80)      NOT NULL CONSTRAINT UQ_bq_token UNIQUE,
    UpdatedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bq_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_bq_status CHECK (Status IN ('awaiting_shop','awaiting_buyer','closed')),
    CONSTRAINT CK_bq_close_kind CHECK (CloseKind IS NULL OR CloseKind IN ('shop_resolved','auto_14_day')),
    CONSTRAINT CK_bq_closed_fields CHECK (
        (Status = 'closed' AND ClosedAt IS NOT NULL)
     OR (Status <> 'closed' AND ClosedAt IS NULL)),
    CONSTRAINT CK_bq_awaiting_clock CHECK (
        Status <> 'awaiting_buyer' OR AwaitingBuyerSince IS NOT NULL)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D046/D047/D069. One persistent threaded case. Statuses are exactly awaiting_shop, awaiting_buyer and closed — no others. A Buy_Buyer reply to a Closed query REOPENS THIS SAME ROW as awaiting_shop; it must never create a new case. awaiting_buyer auto-closes after 14 days without a Buy_Buyer reply; awaiting_shop NEVER auto-closes. inbound_token maps an inbound email reply back to THIS query — EML-007 is the only reply-enabled communication, and only because of it. If the token cannot be resolved, the reply must not create a new case.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_Query';
GO

CREATE INDEX IX_bq_shop_status ON philmart.Buy_Query (ShopID, Status, LastMessageAt DESC);
CREATE INDEX IX_bq_buyer ON philmart.Buy_Query (BuyerID, LastMessageAt DESC);
CREATE INDEX IX_bq_autoclose ON philmart.Buy_Query (AwaitingBuyerSince)
    WHERE Status = 'awaiting_buyer';
GO

CREATE TABLE philmart.Buy_QueryMessage (
    ID              BIGINT           IDENTITY(1,1) NOT NULL
                                     CONSTRAINT PK_buyer_query_message PRIMARY KEY,
    QueryID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bqm_query REFERENCES philmart.Buy_Query(ID),
    ShopID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bqm_shop REFERENCES philmart.Shop_Shop(ID),
    AuthorKind     VARCHAR(20)      NOT NULL,
    BuyerID        UNIQUEIDENTIFIER NULL CONSTRAINT FK_bqm_buyer REFERENCES philmart.Buy_Buyer(ID),
    ShopUserID    UNIQUEIDENTIFIER NULL CONSTRAINT FK_bqm_user REFERENCES philmart.Shop_User(ID),
    Body            NVARCHAR(MAX)    NOT NULL,
    PostedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bqm_posted DEFAULT (philmart.ServerNow()),
    ViaEmailReply BIT              NOT NULL CONSTRAINT DF_bqm_viaemail DEFAULT (0),
    CONSTRAINT CK_bqm_author CHECK (AuthorKind IN ('Buy_Buyer','Shop_User','system'))
);
GO

CREATE TRIGGER philmart.TR_buyer_query_message_append_only
ON philmart.Buy_QueryMessage
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50018, 'philmart.buyer_query_message is append-only (D046). All replies remain on the same case.', 1;
END;
GO

CREATE INDEX IX_bqm_query ON philmart.Buy_QueryMessage (QueryID, PostedAt);
GO

CREATE TABLE philmart.Buy_QueryStatusHistory (
    ID           BIGINT           IDENTITY(1,1) NOT NULL
                                  CONSTRAINT PK_buyer_query_status_history PRIMARY KEY,
    QueryID     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bqsh_query REFERENCES philmart.Buy_Query(ID),
    FromStatus  VARCHAR(20)      NULL,
    ToStatus    VARCHAR(20)      NOT NULL,
    TriggerKind VARCHAR(30)      NOT NULL,
    ChangedAt   DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bqsh_changed DEFAULT (philmart.ServerNow()),
    ChangedBy   UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_bqsh_trigger CHECK (TriggerKind IN
        ('buyer_reply','shop_reply','shop_close','auto_close','reopen'))
);
GO

CREATE TRIGGER philmart.TR_buyer_query_status_history_append_only
ON philmart.Buy_QueryStatusHistory
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50019, 'philmart.buyer_query_status_history is append-only.', 1;
END;
GO

/* ------------------------------------------------------- notifications ----
   D067: user-specific informational records. Read state belongs to each user. */
CREATE TABLE philmart.Shop_Notification (
    ID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ntf_id DEFAULT NEWSEQUENTIALID()
                                  CONSTRAINT PK_notification PRIMARY KEY,
    ShopID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ntf_shop REFERENCES philmart.Shop_Shop(ID),
    ShopUserID UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ntf_user REFERENCES philmart.Shop_User(ID),
    EventKey    VARCHAR(160)     NOT NULL,
    Category     VARCHAR(60)      NOT NULL,
    Title        NVARCHAR(300)    NOT NULL,
    Body         NVARCHAR(MAX)    NULL,
    EntityTable VARCHAR(80)      NULL,
    EntityID    VARCHAR(80)      NULL,
    CreatedAt   DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ntf_created DEFAULT (philmart.ServerNow()),
    ReadAt      DATETIMEOFFSET(7) NULL,
    CONSTRAINT UQ_ntf_user_event UNIQUE (ShopUserID, EventKey)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D067. One row PER USER — read/unread belongs to each user, Mark read and Mark all read affect only the acting user, and UQ_ntf_user_event deduplicates per user per event. One event fanned out to five users creates five rows with the same EventKey and five independent read states. Notification actions NEVER change underlying workflow state.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_Notification';
GO

CREATE INDEX IX_ntf_unread ON philmart.Shop_Notification (ShopUserID, CreatedAt DESC)
    WHERE ReadAt IS NULL;
GO

/* --------------------------------------------------- email catalogue ------
   Seeded from PHILMART_CURRENT_EMAIL_CATALOGUE_2026-09-16.csv. A RETIRED or
   PENDING entry must never be sent — enforced below, not left to discipline. */
CREATE TABLE philmart.Sys_EmailTemplate (
    Code               VARCHAR(20)   NOT NULL CONSTRAINT PK_email_template PRIMARY KEY,
    Authority          VARCHAR(30)   NOT NULL,
    Name               NVARCHAR(200) NULL,
    ControlledTrigger NVARCHAR(500) NULL,
    CommunicationRule NVARCHAR(500) NULL,
    ReplyEnabled      BIT           NOT NULL CONSTRAINT DF_et_reply DEFAULT (0),
    IsOptional        BIT           NOT NULL CONSTRAINT DF_et_optional DEFAULT (0),
    SubjectTemplate   NVARCHAR(400) NULL,
    BodyTemplate      NVARCHAR(MAX) NULL,
    UpdatedAt         DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_et_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_et_authority CHECK (Authority IN
        ('current','current_optional','current_scoped','current_reword',
         'current_redefined','current_exception_only','retired','pending_not_approved'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D060. The controlled catalogue. authority IN (retired, pending_not_approved) means DO NOT IMPLEMENT and DO NOT SEND. EML-006, 009, 011, 014 and 023 are retired; EML-024 is pending and not approved. Seed this table directly from the controlled CSV — typing the 24 rows by hand is how a retired template gets marked current.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_EmailTemplate';
GO

CREATE TABLE philmart.Sys_EmailMessage (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_em_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_email_message PRIMARY KEY,
    TemplateCode       VARCHAR(20)      NOT NULL
                        CONSTRAINT FK_em_template REFERENCES philmart.Sys_EmailTemplate(Code),
    ShopID             UNIQUEIDENTIFIER NULL CONSTRAINT FK_em_shop REFERENCES philmart.Shop_Shop(ID),
    ToAddress          NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    BuyerID            UNIQUEIDENTIFIER NULL CONSTRAINT FK_em_buyer REFERENCES philmart.Buy_Buyer(ID),
    SellerID           UNIQUEIDENTIFIER NULL CONSTRAINT FK_em_seller REFERENCES philmart.Sell_Seller(ID),
    ShopUserID        UNIQUEIDENTIFIER NULL CONSTRAINT FK_em_user REFERENCES philmart.Shop_User(ID),
    Subject             NVARCHAR(400)    NOT NULL,
    Body                NVARCHAR(MAX)    NOT NULL,
    Context             NVARCHAR(MAX)    NULL,
    ReplyToken         VARCHAR(80)      NULL,
    QueuedAt           DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_em_queued DEFAULT (philmart.ServerNow()),
    SentAt             DATETIMEOFFSET(7) NULL,
    DeliveryState      VARCHAR(20)      NOT NULL CONSTRAINT DF_em_state DEFAULT ('queued'),
    ProviderMessageID VARCHAR(200)     NULL,
    FailureCode        VARCHAR(80)      NULL,
    FailureDetail      NVARCHAR(1000)   NULL,
    Attempts            INT              NOT NULL CONSTRAINT DF_em_attempts DEFAULT (0),
    CONSTRAINT CK_em_state CHECK (DeliveryState IN
        ('queued','sent','delivered','bounced','failed','suppressed')),
    CONSTRAINT CK_em_context_json CHECK (Context IS NULL OR ISJSON(Context) = 1)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'NF-12. Delivery outcome is PERSISTED for every controlled communication. Failures surface on the Email Delivery Exceptions report (BR-24-R04) rather than being lost silently. Controlled communications are contractual behaviour, not best effort.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_EmailMessage';
GO

CREATE INDEX IX_em_failed ON philmart.Sys_EmailMessage (DeliveryState, QueuedAt DESC)
    WHERE DeliveryState IN ('bounced', 'failed');
CREATE INDEX IX_em_template ON philmart.Sys_EmailMessage (TemplateCode, QueuedAt DESC);
CREATE UNIQUE INDEX UX_em_reply_token ON philmart.Sys_EmailMessage (ReplyToken)
    WHERE ReplyToken IS NOT NULL;
GO

/* Hard stop: a retired or unapproved template can never be queued.
   Set-based: one offending row in a multi-row insert fails the whole statement. */
CREATE TRIGGER philmart.TR_email_message_sendable
ON philmart.Sys_EmailMessage
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN philmart.Sys_EmailTemplate AS t ON t.Code = i.TemplateCode
        WHERE t.Authority IN ('retired','pending_not_approved'))
    BEGIN
        THROW 50020, 'An email template with authority retired or pending_not_approved must not be implemented or sent (D004, D056, D058, D060). EML-006, 009, 011, 014, 023 are retired; EML-024 is pending.', 1;
    END
END;
GO

/* ------------------------------------------- governance exception feed ----
   D070. The monthly Responsible Person Exception Report reads from here.     */
CREATE TABLE philmart.Rpt_GovernanceException (
    ID                 BIGINT           IDENTITY(1,1) NOT NULL
                                        CONSTRAINT PK_governance_exception PRIMARY KEY,
    ShopID            UNIQUEIDENTIFIER NULL CONSTRAINT FK_ge_shop REFERENCES philmart.Shop_Shop(ID),
    ExceptionKind     VARCHAR(60)      NOT NULL,
    Severity           VARCHAR(20)      NOT NULL,
    EntityTable       VARCHAR(80)      NOT NULL,
    EntityID          VARCHAR(80)      NOT NULL,
    Summary            NVARCHAR(500)    NOT NULL,
    Detail             NVARCHAR(MAX)    NULL,
    DecisionRef       VARCHAR(40)      NULL,
    RaisedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ge_raised DEFAULT (philmart.ServerNow()),
    ClearedAt         DATETIMEOFFSET(7) NULL,
    ReportedInPeriod DATE             NULL,
    CONSTRAINT CK_ge_severity CHECK (Severity IN ('info','attention','escalated')),
    CONSTRAINT CK_ge_detail_json CHECK (Detail IS NULL OR ISJSON(Detail) = 1)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D070. Feed for the Monthly Responsible Person Exception Report: 75+ day Ready to List, unresolved Missing/Damaged, write-offs and removals, Sale_Fulfilment exceptions, fee arrears and deactivation/reactivation, Buy_Buyer restrictions, exceptional Auction cancellations, material reversals and refunds, aged or escalated Buyer Queries, and other controlled exceptions.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Rpt_GovernanceException';
GO

CREATE INDEX IX_ge_open ON philmart.Rpt_GovernanceException (ExceptionKind, RaisedAt)
    WHERE ClearedAt IS NULL;
CREATE INDEX IX_ge_shop ON philmart.Rpt_GovernanceException (ShopID, RaisedAt DESC);
GO

/* Canonical exception kinds. Anything not here is not a governance exception. */
CREATE TABLE philmart.Rpt_GovernanceExceptionKind (
    Kind             VARCHAR(60)   NOT NULL CONSTRAINT PK_governance_exception_kind PRIMARY KEY,
    Name             NVARCHAR(200) NOT NULL,
    DecisionRef     VARCHAR(40)   NOT NULL,
    DefaultSeverity VARCHAR(20)   NOT NULL,
    CONSTRAINT CK_gek_severity CHECK (DefaultSeverity IN ('info','attention','escalated'))
);
GO

INSERT INTO philmart.Rpt_GovernanceExceptionKind (Kind, Name, DecisionRef, DefaultSeverity) VALUES
 ('ready_to_list_60',      'Ready to List 60+ days - Shop attention',     'D061','attention'),
 ('ready_to_list_75',      'Ready to List 75+ days - responsible person', 'D061','escalated'),
 ('missing_damaged_open',  'Unresolved Missing or Damaged Item_Item',          'D016','escalated'),
 ('item_written_off',      'Item written off',                            'D056','escalated'),
 ('item_removed',          'Item removed from stock',                     'D010','attention'),
 ('Sale_PaidItemAttention',   'Fully paid Item_Item not yet fulfilled',           'D024','attention'),
 ('fee_arrears',           'PHILMART fee Sale_Invoice overdue',                'D030','attention'),
 ('shop_deactivated',      'Shop manually deactivated',                   'D031','escalated'),
 ('shop_reactivated',      'Shop manually reactivated',                   'D031','info'),
 ('buyer_restricted',      'Buyer restriction imposed',                   'D044','attention'),
 ('auction_cancelled_bids','Exceptional auction cancellation with bids',  'D016','escalated'),
 ('material_reversal',     'Material Sale_Payment reversal or refund',         'D026','escalated'),
 ('query_aged',            'Aged or escalated Buyer Query',               'D069','attention'),
 ('email_delivery_failed', 'Controlled communication failed to deliver',  'NF-12','attention');
GO

ALTER TABLE philmart.Rpt_GovernanceException ADD CONSTRAINT FK_ge_kind
    FOREIGN KEY (ExceptionKind) REFERENCES philmart.Rpt_GovernanceExceptionKind(Kind);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D070. Note what is deliberately ABSENT: routine unpaid invoices and ordinary overdue Buy_Buyer queries are NOT governance exceptions. Adding them would drown the report the responsible person actually has to read. The foreign key from Rpt_GovernanceException makes the set closed.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Rpt_GovernanceExceptionKind';
GO

/* --------------------------------------------------- report definitions --- */
CREATE TABLE philmart.Rpt_Definition (
    Code        VARCHAR(60)   NOT NULL CONSTRAINT PK_report_definition PRIMARY KEY,
    Name        NVARCHAR(200) NOT NULL,
    Audience    VARCHAR(10)   NOT NULL,
    Description NVARCHAR(1000) NOT NULL,
    ScreenRef  VARCHAR(40)   NULL,
    CONSTRAINT CK_rd_audience CHECK (Audience IN ('Shop_Shop','philmart','both'))
);
GO

/* SQL Server has no array type; the Postgres TEXT[] of output formats becomes
   a child table, which is also queryable.                                    */
CREATE TABLE philmart.Rpt_OutputFormat (
    ReportCode VARCHAR(60) NOT NULL
                CONSTRAINT FK_rof_report REFERENCES philmart.Rpt_Definition(Code),
    Format      VARCHAR(10) NOT NULL,
    CONSTRAINT PK_report_output_format PRIMARY KEY (ReportCode, Format),
    CONSTRAINT CK_rof_format CHECK (Format IN ('pdf','xlsx','csv'))
);
GO

CREATE TABLE philmart.Rpt_Run (
    ID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_rr_id DEFAULT NEWSEQUENTIALID()
                                  CONSTRAINT PK_report_run PRIMARY KEY,
    ReportCode  VARCHAR(60)      NOT NULL
                 CONSTRAINT FK_rr_report REFERENCES philmart.Rpt_Definition(Code),
    ShopID      UNIQUEIDENTIFIER NULL CONSTRAINT FK_rr_shop REFERENCES philmart.Shop_Shop(ID),
    PeriodStart DATE             NULL,
    PeriodEnd   DATE             NULL,
    Parameters   NVARCHAR(MAX)    NULL,
    GeneratedAt DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_rr_generated DEFAULT (philmart.ServerNow()),
    GeneratedBy UNIQUEIDENTIFIER NULL,
    StorageKey  NVARCHAR(500)    NULL,
    [RowCount]  INT              NULL,
    CONSTRAINT CK_rr_params_json CHECK (Parameters IS NULL OR ISJSON(Parameters) = 1)
);
GO
CREATE INDEX IX_rr_report ON philmart.Rpt_Run (ReportCode, GeneratedAt DESC);
GO
