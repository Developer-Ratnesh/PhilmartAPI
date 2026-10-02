/* ===========================================================================
   PHILMART V1 — Microsoft SQL Server schema
   Part 1 of 9 : foundation, value domains, audit, configuration, reference data

   Target: SQL Server 2019 or later, or Azure SQL Database.
           2016 is the floor for Row Level Security and JSON; 2019 is required
           for scalar UDF inlining, without which ServerNow() in a predicate
           is a per-row call.

   Authority: Controlled Decision Register D001-D076 (16 Sep 2026)
              D076 Authority Matrix, 208 records / 159 screen IDs
              Software Development Agreement D076, clauses 8, 9.1, 9.2, 9.3

   Conventions
     * Money is BIGINT in minor units (cents). No FLOAT, no REAL, ever.
       Percentages are DECIMAL(9,6).
     * Timestamps are DATETIMEOFFSET(7), defaulted from philmart.server_now().
       Application and client clocks are never authoritative (clause 9.2).
     * Surrogate keys are UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID() so the
       clustered primary key stays sequential. NEWID() would fragment it.
     * SQL Server has no ENUM. Closed value sets are VARCHAR + CHECK, and every
       permitted value is also catalogued in philmart.enum_value for lookup,
       dropdown binding and introspection.
     * Ledger and audit tables are append-only, enforced by trigger.
     * created_at is on every table. updated_at only where the row is
       legitimately mutable; its absence is a deliberate signal.

   IMPORTANT: filtered indexes require these SET options ON for any session
   performing DML on the affected tables. The application connection must set
   them; most drivers do by default, but verify.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
GO

IF SCHEMA_ID(N'philmart') IS NULL EXEC(N'CREATE SCHEMA philmart AUTHORIZATION dbo;');
GO

/* ------------------------------------------------------------------ time ---
   Single source of authoritative time. The deterministic test clock (task T06)
   overrides this one function and nothing else, so every timing rule becomes
   testable without waiting. Application code must never call SYSDATETIMEOFFSET()
   or GETUTCDATE() directly; it calls philmart.server_now().                  */
CREATE TABLE philmart.Sys_TestClock (
    ID              BIT              NOT NULL CONSTRAINT PK_test_clock PRIMARY KEY
                                     CONSTRAINT CK_test_clock_single CHECK (ID = 1),
    FrozenAt       DATETIMEOFFSET(7) NULL,
    OffsetSeconds  BIGINT           NOT NULL CONSTRAINT DF_test_clock_offset DEFAULT (0),
    Enabled         BIT              NOT NULL CONSTRAINT DF_test_clock_enabled DEFAULT (0)
);
GO
INSERT INTO philmart.Sys_TestClock (ID) VALUES (1);
GO

CREATE FUNCTION philmart.ServerNow()
RETURNS DATETIMEOFFSET(7)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @now DATETIMEOFFSET(7);
    SELECT @now = CASE
        WHEN c.Enabled = 1 AND c.FrozenAt IS NOT NULL
             THEN DATEADD(SECOND, c.OffsetSeconds, c.FrozenAt)
        WHEN c.Enabled = 1
             THEN DATEADD(SECOND, c.OffsetSeconds, SYSDATETIMEOFFSET())
        ELSE SYSDATETIMEOFFSET()
    END
    FROM philmart.Sys_TestClock AS c WHERE c.ID = 1;
    RETURN @now;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Authoritative time for every business rule. Agreement clause 9.2: auction time must be authoritative on the server or database and may not depend on a user device clock. The task T06 test clock hooks here and nowhere else. WITH SCHEMABINDING enables scalar UDF inlining on SQL Server 2019+.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'FUNCTION',@level1name=N'ServerNow';
GO

/* ------------------------------------------------------ session / tenancy ---
   The API sets these per request, after authenticating, via
   sp_set_session_context. RLS predicates read them. A ShopID supplied by the
   client application is never sufficient authorisation (clause 9.1) — these are
   set from the verified session, server-side only.

   SESSION_CONTEXT lives on the connection. Connection pooling issues
   sp_reset_connection, which clears it, but the application must still set all
   three at the start of EVERY request and never assume a carried-over value.  */
CREATE FUNCTION philmart.CurrentActorID()
RETURNS UNIQUEIDENTIFIER
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER);
END;
GO

CREATE FUNCTION philmart.CurrentShopID()
RETURNS UNIQUEIDENTIFIER
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER);
END;
GO

CREATE FUNCTION philmart.CurrentActorKind()
RETURNS VARCHAR(20)
WITH SCHEMABINDING
AS
BEGIN
    RETURN ISNULL(CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)), 'anonymous');
END;
GO

CREATE FUNCTION philmart.IsPlatformAdmin()
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN ISNULL(CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)),'') = 'platform_admin'
                THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END;
GO

/* --------------------------------------------------------- value domains ---
   SQL Server has no ENUM type. Each closed set below is enforced by a CHECK
   constraint on the column, and catalogued here so the application, the UI and
   a reviewer can all discover the permitted values without reading DDL.

   Adding a value means changing BOTH the CHECK and this table. That friction is
   deliberate: these sets come from controlled decisions, not from convenience. */
CREATE TABLE philmart.Sys_EnumValue (
    EnumName    VARCHAR(40)  NOT NULL,
    Value        VARCHAR(40)  NOT NULL,
    SortOrder   INT          NOT NULL CONSTRAINT DF_enum_sort DEFAULT (0),
    DecisionRef VARCHAR(40)  NULL,
    Note         NVARCHAR(400) NULL,
    CONSTRAINT PK_enum_value PRIMARY KEY (EnumName, Value)
);
GO

INSERT INTO philmart.Sys_EnumValue (EnumName, Value, SortOrder, DecisionRef, Note) VALUES
 ('actor_kind','anonymous',1,NULL,NULL),
 ('actor_kind','Buy_Buyer',2,NULL,NULL),
 ('actor_kind','Shop_User',3,NULL,NULL),
 ('actor_kind','platform_admin',4,'D049','Separate from Shop permissions entirely'),
 ('actor_kind','system',5,NULL,'Background jobs and database-initiated actions'),

 ('shop_status','application_submitted',1,'D002','Awaiting PHILMART review'),
 ('shop_status','application_rejected',2,NULL,NULL),
 ('shop_status','setup_access_granted',3,'D001','Approved: Setup access ONLY, not active'),
 ('shop_status','active',4,'D005','Automatic on valid setup completion'),
 ('shop_status','deactivated',5,'D031','Manual only, never automatic'),

 ('item_state','ready_to_list',1,'D061','60+ days attention, 75+ escalation; neither changes state'),
 ('item_state','listed',2,'D013','Tied to exactly one active Listing'),
 ('item_state','sold_fulfilment_pending',3,'D017','Not complete until full Sale_Payment plus Sale_Fulfilment'),
 ('item_state','complete',4,'D017',NULL),
 ('item_state','removed_from_stock',5,'D010','Reversible'),
 ('item_state','missing_damaged',6,'D016','DISTINCT non-saleable state, NOT a flag'),
 ('item_state','returned_to_seller',7,'D065','Terminal; only at physical handover'),
 ('item_state','written_off',8,'D056','Terminal; history remains'),

 ('listing_type','fixed_price',1,NULL,NULL),
 ('listing_type','auction',2,NULL,NULL),

 ('listing_state','draft',1,NULL,NULL),
 ('listing_state','scheduled',2,'D064',NULL),
 ('listing_state','live',3,NULL,NULL),
 ('listing_state','sold',4,NULL,'Historical, read-only'),
 ('listing_state','unsold',5,'D012','Historical; Item auto-returns to Ready to List'),
 ('listing_state','withdrawn',6,'D014','Historical; Item auto-returns'),
 ('listing_state','expired',7,'D015','Historical at 90 days; Item auto-returns'),
 ('listing_state','cancelled',8,'D016','Reason mandatory when bids exist'),

 ('invoice_state','draft',1,NULL,NULL),
 ('invoice_state','issued',2,'D019','Immutable once issued'),
 ('invoice_state','cancelled',3,NULL,'Reason mandatory'),

 ('settlement_status','unpaid',1,NULL,'DERIVED, never stored'),
 ('settlement_status','part_paid',2,NULL,'DERIVED, never stored'),
 ('settlement_status','paid',3,'D020','DERIVED; gates Dispatch and Ready for Collection'),

 ('fulfilment_method','shipping',1,'D023','Financial trigger is Dispatch'),
 ('fulfilment_method','collection',2,'D023','Financial trigger is Ready for Collection'),

 ('fulfilment_state','pending',1,NULL,NULL),
 ('fulfilment_state','dispatched',2,'D023',NULL),
 ('fulfilment_state','ready_for_collection',3,'D023',NULL),
 ('fulfilment_state','collected',4,'D023','Later event; NEVER a financial trigger'),

 ('query_status','awaiting_shop',1,'D047','Never auto-closes'),
 ('query_status','awaiting_buyer',2,'D069','Auto-closes after 14 days'),
 ('query_status','closed',3,'D069','A Buy_Buyer reply reopens the SAME case'),

 ('restriction_scope','Shop_Shop',1,'D044','Shop may lift only its own'),
 ('restriction_scope','platform',2,'D045','PHILMART only; takes precedence'),

 ('fee_invoice_kind','monthly_transaction',1,'D028',NULL),
 ('fee_invoice_kind','annual_shop_fee',2,'D075','Raised 1 January where applicable'),

 ('ledger_direction','debit',1,NULL,NULL),
 ('ledger_direction','credit',2,NULL,NULL),

 ('email_authority','current',1,'D060',NULL),
 ('email_authority','current_optional',2,'D068','EML-013 only; throttled'),
 ('email_authority','current_scoped',3,'D056','EML-015'),
 ('email_authority','current_reword',4,'D035','EML-019'),
 ('email_authority','current_redefined',5,'D003','EML-022'),
 ('email_authority','current_exception_only',6,'D058','EML-010'),
 ('email_authority','retired',7,'D060','DO NOT IMPLEMENT'),
 ('email_authority','pending_not_approved',8,'D060','EML-024; DO NOT IMPLEMENT'),

 ('email_delivery_state','queued',1,NULL,NULL),
 ('email_delivery_state','sent',2,NULL,NULL),
 ('email_delivery_state','delivered',3,NULL,NULL),
 ('email_delivery_state','bounced',4,'NF-12','Surfaces on Email Delivery Exceptions'),
 ('email_delivery_state','failed',5,'NF-12','Surfaces on Email Delivery Exceptions'),
 ('email_delivery_state','suppressed',6,'D068','Throttled, not a failure'),

 ('removal_reason','damaged',1,NULL,NULL),
 ('removal_reason','lost',2,NULL,NULL),
 ('removal_reason','seller_request',3,NULL,NULL),
 ('removal_reason','pricing',4,NULL,NULL),
 ('removal_reason','other',5,'D066','Mandatory internal note required'),

 ('bulk_upload_state','uploaded',1,NULL,NULL),
 ('bulk_upload_state','validating',2,NULL,NULL),
 ('bulk_upload_state','validation_failed',3,NULL,NULL),
 ('bulk_upload_state','validated',4,NULL,NULL),
 ('bulk_upload_state','imported',5,NULL,NULL),
 ('bulk_upload_state','abandoned',6,NULL,NULL);
GO

/* ----------------------------------------------------------------- audit ---
   Append-only. Enforced at database level, not by application convention
   (Agreement clause 8, task T07).                                            */
CREATE TABLE philmart.Sys_AuditEvent (
    ID              BIGINT            IDENTITY(1,1) NOT NULL CONSTRAINT PK_audit_event PRIMARY KEY,
    OccurredAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_audit_occurred DEFAULT (philmart.ServerNow()),
    ActorID        UNIQUEIDENTIFIER  NULL,
    ActorKind      VARCHAR(20)       NOT NULL,
    ShopID         UNIQUEIDENTIFIER  NULL,
    EntityTable    VARCHAR(80)       NOT NULL,
    EntityID       VARCHAR(80)       NOT NULL,
    Action          VARCHAR(80)       NOT NULL,
    Reason          NVARCHAR(1000)    NULL,
    BeforeValue    NVARCHAR(MAX)     NULL,
    AfterValue     NVARCHAR(MAX)     NULL,
    RequestID      VARCHAR(80)       NULL,
    IpAddress      VARCHAR(45)       NULL,
    CONSTRAINT CK_audit_actor_kind CHECK (ActorKind IN
        ('anonymous','Buy_Buyer','Shop_User','platform_admin','system')),
    CONSTRAINT CK_audit_before_json CHECK (BeforeValue IS NULL OR ISJSON(BeforeValue) = 1),
    CONSTRAINT CK_audit_after_json  CHECK (AfterValue  IS NULL OR ISJSON(AfterValue)  = 1),
    /* Reasons that a decision makes mandatory. Enforced, not documented. */
    CONSTRAINT CK_audit_reason_required CHECK (
        Action NOT IN (
            'auction.cancelled_with_bids',     -- D016
            'Item_Item.removed_from_stock.other',   -- D066
            'Buy_Buyer.restricted',                -- D044
            'Shop_Shop.deactivated',                -- D031
            'Shop_Shop.reactivated',                -- D031
            'Sell_Payment.reversed',         -- D026
            'seller_proceeds.adjusted',        -- D027
            'Sale_Invoice.cancelled',
            'fee.waived'                       -- D072
        ) OR (Reason IS NOT NULL AND LEN(LTRIM(RTRIM(Reason))) > 0)
    )
);
GO

CREATE INDEX IX_audit_entity ON philmart.Sys_AuditEvent (EntityTable, EntityID, OccurredAt DESC);
CREATE INDEX IX_audit_shop   ON philmart.Sys_AuditEvent (ShopID, OccurredAt DESC);
CREATE INDEX IX_audit_actor  ON philmart.Sys_AuditEvent (ActorID, OccurredAt DESC);
CREATE INDEX IX_audit_action ON philmart.Sys_AuditEvent (Action, OccurredAt DESC);
GO

/* Append-only guard. SQL Server triggers fire ONCE PER STATEMENT, so this is
   written set-based: a single multi-row UPDATE must be refused as a whole. */
CREATE TRIGGER philmart.TR_audit_event_append_only
ON philmart.Sys_AuditEvent
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50001, 'philmart.audit_event is append-only. Corrections must be made by a linked reversal, adjustment or superseding record (Agreement clause 8).', 1;
END;
GO

/* --------------------------------------------- platform configuration ------
   D052: PHILMART Configuration holds only explicit platform options,
   constraints, defaults/fallbacks and mandatory rules. D053: defaults, minimums
   and maximums exist only where explicitly justified. Values live here as
   configuration, never as constants in code.                                 */
CREATE TABLE philmart.Sys_PlatformSetting (
    [key]            VARCHAR(80)      NOT NULL CONSTRAINT PK_platform_setting PRIMARY KEY,
    Value            NVARCHAR(MAX)    NOT NULL,
    ValueType       VARCHAR(20)      NOT NULL,
    Unit             VARCHAR(40)      NULL,
    Description      NVARCHAR(1000)   NOT NULL,
    DecisionRef     VARCHAR(40)      NULL,
    ShopOverridable BIT              NOT NULL CONSTRAINT DF_setting_override DEFAULT (0),
    MinValue        DECIMAL(19,6)    NULL,
    MaxValue        DECIMAL(19,6)    NULL,
    UpdatedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_setting_updated DEFAULT (philmart.ServerNow()),
    UpdatedBy       UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_setting_type CHECK (ValueType IN ('int','decimal','bool','text','duration','json')),
    CONSTRAINT CK_setting_json CHECK (ValueType <> 'json' OR ISJSON(Value) = 1)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D052/D053. A value may exist here only with a DecisionRef justifying it. Sample values seen in screen evidence are NOT business rules and must not be seeded here.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_PlatformSetting';
GO

/* D054: changing a PHILMART default never overwrites an existing Shop value.
   Where a changed range invalidates a Shop value, it is flagged, not altered. */
CREATE TABLE philmart.Sys_SettingValidationFlag (
    ID             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT DF_svf_id DEFAULT NEWSEQUENTIALID()
                                     CONSTRAINT PK_setting_validation_flag PRIMARY KEY,
    ShopID        UNIQUEIDENTIFIER  NOT NULL,
    SettingKey    VARCHAR(80)       NOT NULL
                   CONSTRAINT FK_svf_setting REFERENCES philmart.Sys_PlatformSetting([key]),
    CurrentValue  NVARCHAR(MAX)     NOT NULL,
    ViolatedRule  NVARCHAR(500)     NOT NULL,
    RaisedAt      DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_svf_raised DEFAULT (philmart.ServerNow()),
    ResolvedAt    DATETIMEOFFSET(7) NULL,
    ResolvedBy    UNIQUEIDENTIFIER  NULL
);
GO
CREATE INDEX IX_svf_open ON philmart.Sys_SettingValidationFlag (ShopID, SettingKey)
    WHERE ResolvedAt IS NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D054. When a PHILMART range change makes an existing Shop value invalid the value is flagged for correction here. It is never silently changed.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_SettingValidationFlag';
GO

/* D055: a retired option is removed from active configuration and future
   selection, but historical and open transaction snapshots keep their value. */
CREATE TABLE philmart.Sys_RetiredOption (
    ID             UNIQUEIDENTIFIER  NOT NULL CONSTRAINT DF_retired_id DEFAULT NEWSEQUENTIALID()
                                     CONSTRAINT PK_retired_option PRIMARY KEY,
    OptionDomain  VARCHAR(60)       NOT NULL,
    OptionCode    VARCHAR(60)       NOT NULL,
    RetiredAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_retired_at DEFAULT (philmart.ServerNow()),
    RetiredBy     UNIQUEIDENTIFIER  NULL,
    DecisionRef   VARCHAR(40)       NULL,
    Note           NVARCHAR(500)     NULL,
    CONSTRAINT UQ_retired_option UNIQUE (OptionDomain, OptionCode)
);
GO

/* ------------------------------------------------- Item_Item classification -----
   PHILMART-controlled reference data, seeded from the controlled classification
   master. Not Shop-editable (D052, BR-22-R08).                               */
CREATE TABLE philmart.Sys_ClassificationAreaCountry (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_cac_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_area_country PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_cac_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    ParentID  UNIQUEIDENTIFIER NULL
               CONSTRAINT FK_cac_parent REFERENCES philmart.Sys_ClassificationAreaCountry(ID),
    SortOrder INT              NOT NULL CONSTRAINT DF_cac_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_cac_active DEFAULT (1)
);
GO

CREATE TABLE philmart.Sys_ClassificationType (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ct_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_type PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_ct_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_ct_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_ct_active DEFAULT (1)
);
GO

CREATE TABLE philmart.Sys_ClassificationSubtype (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_cst_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_subtype PRIMARY KEY,
    TypeID    UNIQUEIDENTIFIER NOT NULL
               CONSTRAINT FK_cst_type REFERENCES philmart.Sys_ClassificationType(ID),
    Code       VARCHAR(40)      NOT NULL,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_cst_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_cst_active DEFAULT (1),
    CONSTRAINT UQ_cst_type_code UNIQUE (TypeID, Code)
);
GO

CREATE TABLE philmart.Sys_ClassificationTheme (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_cth_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_theme PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_cth_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_cth_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_cth_active DEFAULT (1)
);
GO

CREATE TABLE philmart.Sys_ClassificationFormat (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_cf_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_format PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_cf_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_cf_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_cf_active DEFAULT (1)
);
GO

CREATE TABLE philmart.Sys_ClassificationStampState (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_css_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_classification_stamp_state PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_css_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_css_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_css_active DEFAULT (1)
);
GO

CREATE TABLE philmart.Sys_ItemCondition (
    ID         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ic_id DEFAULT NEWSEQUENTIALID()
                                CONSTRAINT PK_item_condition PRIMARY KEY,
    Code       VARCHAR(40)      NOT NULL CONSTRAINT UQ_ic_code UNIQUE,
    Name       NVARCHAR(200)    NOT NULL,
    SortOrder INT              NOT NULL CONSTRAINT DF_ic_sort DEFAULT (0),
    Active     BIT              NOT NULL CONSTRAINT DF_ic_active DEFAULT (1)
);
GO

/* ------------------------------------------------ delivery reference -------
   Platform-permitted delivery methods. A Shop selects from these; it cannot
   invent one (D052). Custom Delivery and Deferred Delivery are retired (D007)
   and must not be seeded.                                                    */
CREATE TABLE philmart.Sys_DeliveryMethod (
    ID                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_dm_id DEFAULT NEWSEQUENTIALID()
                                           CONSTRAINT PK_delivery_method PRIMARY KEY,
    Code                  VARCHAR(40)      NOT NULL CONSTRAINT UQ_dm_code UNIQUE,
    Name                  NVARCHAR(200)    NOT NULL,
    MethodKind           VARCHAR(20)      NOT NULL,
    RequiresPickupPoint BIT              NOT NULL CONSTRAINT DF_dm_pickup DEFAULT (0),
    RequiresAddress      BIT              NOT NULL CONSTRAINT DF_dm_address DEFAULT (0),
    ControlledWording    NVARCHAR(MAX)    NULL,
    SortOrder            INT              NOT NULL CONSTRAINT DF_dm_sort DEFAULT (0),
    Active                BIT              NOT NULL CONSTRAINT DF_dm_active DEFAULT (1),
    RetiredAt            DATETIMEOFFSET(7) NULL,
    CONSTRAINT CK_dm_kind CHECK (MethodKind IN ('shipping','collection')),
    CONSTRAINT CK_dm_not_custom CHECK (Code NOT IN ('CUSTOM','DEFERRED'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D007. Custom Delivery and the former Deferred Delivery concept are retired from active platform use and must not exist as selectable methods. CK_dm_not_custom enforces this at the data layer.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_DeliveryMethod';
GO

CREATE TABLE philmart.Sys_DeliveryTariff (
    ID                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_dt_id DEFAULT NEWSEQUENTIALID()
                                        CONSTRAINT PK_delivery_tariff PRIMARY KEY,
    DeliveryMethodID UNIQUEIDENTIFIER NOT NULL
                       CONSTRAINT FK_dt_method REFERENCES philmart.Sys_DeliveryMethod(ID),
    ZoneCode          VARCHAR(40)      NULL,
    WeightFromG      INT              NOT NULL CONSTRAINT DF_dt_wfrom DEFAULT (0),
    WeightToG        INT              NULL,
    AmountMinor       BIGINT           NOT NULL,
    Currency           CHAR(3)          NOT NULL CONSTRAINT DF_dt_ccy DEFAULT ('ZAR'),
    EffectiveFrom     DATE             NOT NULL,
    EffectiveTo       DATE             NULL,
    CONSTRAINT CK_dt_amount CHECK (AmountMinor >= 0),
    CONSTRAINT CK_dt_weight CHECK (WeightToG IS NULL OR WeightToG > WeightFromG),
    CONSTRAINT CK_dt_effective CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
);
GO
CREATE INDEX IX_dt_lookup ON philmart.Sys_DeliveryTariff (DeliveryMethodID, ZoneCode, WeightFromG);
GO

CREATE TABLE philmart.Sys_PickupPoint (
    ID                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pp_id DEFAULT NEWSEQUENTIALID()
                                        CONSTRAINT PK_pickup_point PRIMARY KEY,
    DeliveryMethodID UNIQUEIDENTIFIER NOT NULL
                       CONSTRAINT FK_pp_method REFERENCES philmart.Sys_DeliveryMethod(ID),
    Code               VARCHAR(40)      NOT NULL,
    Name               NVARCHAR(200)    NOT NULL,
    AddressLine1      NVARCHAR(200)    NULL,
    AddressLine2      NVARCHAR(200)    NULL,
    City               NVARCHAR(120)    NULL,
    Province           NVARCHAR(120)    NULL,
    PostalCode        VARCHAR(20)      NULL,
    CountryCode       CHAR(2)          NOT NULL CONSTRAINT DF_pp_country DEFAULT ('ZA'),
    Active             BIT              NOT NULL CONSTRAINT DF_pp_active DEFAULT (1),
    CONSTRAINT UQ_pp_method_code UNIQUE (DeliveryMethodID, Code)
);
GO
