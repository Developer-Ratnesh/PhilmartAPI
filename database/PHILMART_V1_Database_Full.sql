/* ===========================================================================
   PHILMART V1 - MS SQL Server
   COMPLETE DATABASE IN ONE FILE : schema (parts 1-9) + controlled seed (10)

   GENERATED FILE - DO NOT EDIT BY HAND.
   Built by tools/build_sql.py from 02_Database/migrations/. Change a
   migration, or tools/gen_seed.py for the seed, and rebuild.

   ---------------------------------------------------------------- running --

   Create the database first, then run this file against it:

       sqlcmd -S <server> -E -C -Q "CREATE DATABASE PhilMart;"
       sqlcmd -S <server> -E -C -d PhilMart -f 65001 -b -i PHILMART_V1_Database_Full.sql

   -f 65001 is REQUIRED. This file is UTF-8 without a BOM and carries
   accented controlled names (Reunion, Sao Tome and Principe, em dashes).
   Without it they load mojibaked into a PHILMART-controlled master.

   -b is strongly recommended so a failing batch actually fails the run
   rather than scrolling past and leaving a half-built database.

   There is deliberately no CREATE DATABASE or USE here: USE is not
   supported on Azure SQL Database, and which database this lands in should
   be the caller's explicit choice, not a constant buried in a script.

   Run as a principal that can create objects - the database owner, or a
   member of philmart_migrator once part 9 has created that role. NOT as
   philmart_app: it is denied DELETE and is subject to Row Level Security.

   ------------------------------------------------------------ what you get --

   82 tables, 61 indexes, 15 functions, 4 stored procedures, 30 triggers,
   3 views, 4 security policies over 53 tables, 123 check constraints, and
   the controlled reference seed: 516 Area/Country nodes, 60 subtypes,
   37 formats, 32 themes, 26 permissions, 24 email templates, 8 setup
   sections, 7 types, 7 stamp states, 7 legal documents, 7 report
   definitions and 10 platform settings.

   This targets a FRESH database. It is not a re-runnable upgrade script:
   parts 1-9 are CREATE statements and will fail on objects that already
   exist. Part 10, the seed, IS idempotent and can be re-run on its own.

   Full-Text Search is optional. Where the instance does not have it, part 9
   prints a warning, skips the catalogue and carries on; Item catalogue
   search is then unavailable until the feature is installed.

   Success looks like this, as the last two lines of output:

       PHILMART 010_seed: controlled reference seed loaded and verified.
       PHILMART: database build complete.

   Anything less means the run stopped early. Read upward for the first
   Msg line; everything after the first failure is noise.
=========================================================================== */


/* ========================================================================
   PART 1 OF 10 : 001_foundation.sql
   foundation, test clock, enum catalogue, audit, reference data
   ===================================================================== */
PRINT '>>> PHILMART part 1 of 10: 001_foundation.sql';
GO

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

/* ========================================================================
   PART 2 OF 10 : 002_identity_legal.sql
   platform users, shops, permissions, buyers, legal documents
   ===================================================================== */
PRINT '>>> PHILMART part 2 of 10: 002_identity_legal.sql';
GO

/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 2 of 9 : identity, permissions, legal documents
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------- platform users ---- */
CREATE TABLE philmart.Sys_PlatformUser (
    ID                    UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_pu_id DEFAULT NEWSEQUENTIALID()
                                           CONSTRAINT PK_platform_user PRIMARY KEY,
    Email                 NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL
                                           CONSTRAINT UQ_pu_email UNIQUE,
    FullName             NVARCHAR(200)    NOT NULL,
    PasswordHash         VARCHAR(255)     NOT NULL,
    IsResponsiblePerson BIT              NOT NULL CONSTRAINT DF_pu_rp DEFAULT (0),
    MfaSecret            VARCHAR(255)     NULL,
    DisabledAt           DATETIMEOFFSET(7) NULL,
    CreatedAt            DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_pu_created DEFAULT (philmart.ServerNow()),
    CreatedBy            UNIQUEIDENTIFIER NULL,
    UpdatedAt            DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_pu_updated DEFAULT (philmart.ServerNow())
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D070/D061. is_responsible_person marks the recipient of the monthly exception report and the 75-day Ready-to-List escalation. It is an oversight attribution, not a Sys_Permission set. D049/D051: disabling removes access; the row and all audit history are retained permanently and rows are never deleted.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_PlatformUser';
GO

/* ---------------------------------------------------------------- Shop_Shop ----- */
CREATE TABLE philmart.Shop_Shop (
    ID                      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_shop_id DEFAULT NEWSEQUENTIALID()
                                             CONSTRAINT PK_shop PRIMARY KEY,
    Reference               VARCHAR(40)      NOT NULL CONSTRAINT UQ_shop_reference UNIQUE,
    TradingName            NVARCHAR(200)    NOT NULL,
    LegalEntityName       NVARCHAR(200)    NULL,
    RegistrationNumber     VARCHAR(60)      NULL,
    VatNumber              VARCHAR(60)      NULL,
    Status                  VARCHAR(30)      NOT NULL CONSTRAINT DF_shop_status DEFAULT ('application_submitted'),
    SetupAccessGrantedAt DATETIMEOFFSET(7) NULL,
    ActivatedAt            DATETIMEOFFSET(7) NULL,
    DeactivatedAt          DATETIMEOFFSET(7) NULL,
    DeactivationReason     NVARCHAR(1000)   NULL,
    ReactivatedAt          DATETIMEOFFSET(7) NULL,
    CreatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_shop_created DEFAULT (philmart.ServerNow()),
    CreatedBy              UNIQUEIDENTIFIER NULL,
    UpdatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_shop_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT CK_shop_status CHECK (Status IN
        ('application_submitted','application_rejected','setup_access_granted','active','deactivated')),

    /* D001: approval grants Setup access only; it does not activate.
       D005: activation is automatic on valid setup completion.              */
    CONSTRAINT CK_shop_active_requires_setup CHECK (
        Status <> 'active' OR SetupAccessGrantedAt IS NOT NULL),

    /* D031: deactivation is manual and always carries a reason.             */
    CONSTRAINT CK_shop_deactivation_reason CHECK (
        Status <> 'deactivated' OR
        (DeactivationReason IS NOT NULL AND LEN(LTRIM(RTRIM(DeactivationReason))) > 0))
);
GO
CREATE INDEX IX_shop_status ON philmart.Shop_Shop (Status);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D031. Fee arrears NEVER deactivate a Shop automatically. PHILMART deactivates manually after warning and escalation, always with a recorded reason. CK_shop_deactivation_reason enforces the reason.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_Shop';
GO

/* ------------------------------------------------- Shop_Shop users & perms ------
   D050: the custom role layer is REMOVED. Permissions are assigned DIRECTLY to
   users. There is deliberately no role table, and none may be added.         */
CREATE TABLE philmart.Sys_Permission (
    Code        VARCHAR(60)   NOT NULL CONSTRAINT PK_permission PRIMARY KEY,
    Name        NVARCHAR(120) NOT NULL,
    Category    NVARCHAR(60)  NOT NULL,
    Description NVARCHAR(500) NOT NULL,
    AdminOnly  BIT           NOT NULL CONSTRAINT DF_perm_admin DEFAULT (0)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D050. Reference list of assignable permissions. There is NO role table and none may be introduced: the custom role layer was removed by decision. Shop Administrator receives the full set via Shop_User.is_administrator.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_Permission';
GO

CREATE TABLE philmart.Shop_User (
    ID               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_su_id DEFAULT NEWSEQUENTIALID()
                                      CONSTRAINT PK_shop_user PRIMARY KEY,
    ShopID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_su_shop REFERENCES philmart.Shop_Shop(ID),
    Email            NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    FullName        NVARCHAR(200)    NOT NULL,
    PasswordHash    VARCHAR(255)     NULL,
    IsAdministrator BIT              NOT NULL CONSTRAINT DF_su_admin DEFAULT (0),
    DisabledAt      DATETIMEOFFSET(7) NULL,
    InvitedAt       DATETIMEOFFSET(7) NULL,
    AcceptedAt      DATETIMEOFFSET(7) NULL,
    CreatedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_su_created DEFAULT (philmart.ServerNow()),
    CreatedBy       UNIQUEIDENTIFIER NULL,
    UpdatedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_su_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_su_shop_email UNIQUE (ShopID, Email)
);
GO
CREATE INDEX IX_su_shop_active ON philmart.Shop_User (ShopID) WHERE DisabledAt IS NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D050. is_administrator grants the required full administrative Sys_Permission set. It is not a role and is not user-definable. D049/D051: disabling removes access but preserves the user''s historical actions.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_User';
GO

/* Direct per-user grants (D050, D051). Editing a user changes that user's
   permissions and nobody else's.                                            */
CREATE TABLE philmart.Shop_UserPermission (
    ShopUserID    UNIQUEIDENTIFIER NOT NULL
                    CONSTRAINT FK_sup_user REFERENCES philmart.Shop_User(ID),
    PermissionCode VARCHAR(60)      NOT NULL
                    CONSTRAINT FK_sup_perm REFERENCES philmart.Sys_Permission(Code),
    ShopID         UNIQUEIDENTIFIER NOT NULL
                    CONSTRAINT FK_sup_shop REFERENCES philmart.Shop_Shop(ID),
    GrantedAt      DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sup_granted DEFAULT (philmart.ServerNow()),
    GrantedBy      UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_shop_user_permission PRIMARY KEY (ShopUserID, PermissionCode)
);
GO
CREATE INDEX IX_sup_shop ON philmart.Shop_UserPermission (ShopID);
GO

/* --------------------------------------------------------------- Buy_Buyer ---- */
CREATE TABLE philmart.Buy_Buyer (
    ID                        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_buyer_id DEFAULT NEWSEQUENTIALID()
                                               CONSTRAINT PK_buyer PRIMARY KEY,
    Email                     NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL
                                               CONSTRAINT UQ_buyer_email UNIQUE,
    PasswordHash             VARCHAR(255)     NULL,
    FullName                 NVARCHAR(200)    NULL,
    Mobile                    VARCHAR(40)      NULL,

    /* D039: read-only after registration. Enforced by trigger, part 9. */
    IdentificationType       VARCHAR(40)      NULL,
    IdentificationNumber     VARCHAR(60)      NULL,
    DateOfBirth             DATE             NULL,

    EmailVerifiedAt         DATETIMEOFFSET(7) NULL,   -- EML-019; does NOT complete registration (D035)
    RegistrationCompletedAt DATETIMEOFFSET(7) NULL,   -- EML-020 fires only here (D036)
    RegistrationStep         TINYINT          NOT NULL CONSTRAINT DF_buyer_step DEFAULT (1),

    DisabledAt               DATETIMEOFFSET(7) NULL,
    CreatedAt                DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_buyer_created DEFAULT (philmart.ServerNow()),
    UpdatedAt                DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_buyer_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT CK_buyer_step CHECK (RegistrationStep BETWEEN 1 AND 4)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Agreement clause 9.3: PHILMART does not hold Buy_Buyer funds and does not store Buy_Buyer card or bank credentials. No column for a PAN, card verification value, bank account or tokenised Sale_Payment instrument may be added to this table or any other. D036: EML-020 Buyer Welcome sends only when RegistrationCompletedAt is set, i.e. after the full four-step flow. Email verification alone must never trigger it (D035).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_Buyer';
GO

CREATE TABLE philmart.Buy_Address (
    ID            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ba_id DEFAULT NEWSEQUENTIALID()
                                   CONSTRAINT PK_buyer_address PRIMARY KEY,
    BuyerID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ba_buyer REFERENCES philmart.Buy_Buyer(ID),
    Label         NVARCHAR(80)     NULL,
    AddressLine1 NVARCHAR(200)    NOT NULL,
    AddressLine2 NVARCHAR(200)    NULL,
    City          NVARCHAR(120)    NOT NULL,
    Province      NVARCHAR(120)    NULL,
    PostalCode   VARCHAR(20)      NULL,
    CountryCode  CHAR(2)          NOT NULL CONSTRAINT DF_ba_country DEFAULT ('ZA'),
    IsDefault    BIT              NOT NULL CONSTRAINT DF_ba_default DEFAULT (0),
    ArchivedAt   DATETIMEOFFSET(7) NULL,
    CreatedAt    DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ba_created DEFAULT (philmart.ServerNow()),
    UpdatedAt    DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ba_updated DEFAULT (philmart.ServerNow())
);
GO
CREATE UNIQUE INDEX UX_ba_one_default ON philmart.Buy_Address (BuyerID)
    WHERE IsDefault = 1 AND ArchivedAt IS NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D041/D042. Addresses are archived, never hard-deleted: an existing sale keeps its immutable Sale_Fulfilment snapshot, and profile changes affect future purchases only.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_Address';
GO

/* D009/D037: per delivery method, the Buy_Buyer records availability at their
   location and a preferred pickup point or address used as the purchase default. */
CREATE TABLE philmart.Buy_ShippingPreference (
    ID                      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bsp_id DEFAULT NEWSEQUENTIALID()
                                             CONSTRAINT PK_buyer_shipping_preference PRIMARY KEY,
    BuyerID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bsp_buyer REFERENCES philmart.Buy_Buyer(ID),
    DeliveryMethodID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bsp_method REFERENCES philmart.Sys_DeliveryMethod(ID),
    Available               BIT              NOT NULL CONSTRAINT DF_bsp_available DEFAULT (1),
    DefaultPickupPointID UNIQUEIDENTIFIER NULL CONSTRAINT FK_bsp_pickup REFERENCES philmart.Sys_PickupPoint(ID),
    DefaultAddressID      UNIQUEIDENTIFIER NULL CONSTRAINT FK_bsp_address REFERENCES philmart.Buy_Address(ID),
    CreatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bsp_created DEFAULT (philmart.ServerNow()),
    UpdatedAt              DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bsp_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_bsp_buyer_method UNIQUE (BuyerID, DeliveryMethodID),
    CONSTRAINT CK_bsp_one_target CHECK (
        NOT (DefaultPickupPointID IS NOT NULL AND DefaultAddressID IS NOT NULL))
);
GO

/* D040: only optional auction and following notifications are controllable.
   Essential transactional, Sale_Payment, Sale_Fulfilment, account and security
   communications cannot be disabled — so they have no row here by design.    */
CREATE TABLE philmart.Buy_CommunicationPreference (
    BuyerID   UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bcp_buyer REFERENCES philmart.Buy_Buyer(ID),
    EmailCode VARCHAR(20)      NOT NULL,
    Enabled    BIT              NOT NULL CONSTRAINT DF_bcp_enabled DEFAULT (1),
    UpdatedAt DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bcp_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT PK_buyer_communication_preference PRIMARY KEY (BuyerID, EmailCode),
    CONSTRAINT CK_bcp_optional_only CHECK (EmailCode IN ('EML-013'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D040. Essential transactional, Sale_Payment, Sale_Fulfilment, account and security communications cannot be disabled. Only EML-013 Outbid Alert is optional in the current catalogue, so only it may appear here. CK_bcp_optional_only makes a mistaken opt-out impossible to store.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_CommunicationPreference';
GO

/* ------------------------------------------------------- Buy_Buyer accounts ----
   D043: the Buyer Account is the Shop-side financial ledger and is distinct
   from the Buyer Profile. One account per Buy_Buyer per Shop — credit never
   crosses Shops.                                                             */
CREATE TABLE philmart.Buy_Account (
    ID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bacc_id DEFAULT NEWSEQUENTIALID()
                               CONSTRAINT PK_buyer_account PRIMARY KEY,
    ShopID   UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bacc_shop REFERENCES philmart.Shop_Shop(ID),
    BuyerID  UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bacc_buyer REFERENCES philmart.Buy_Buyer(ID),
    OpenedAt DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bacc_opened DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_bacc_shop_buyer UNIQUE (ShopID, BuyerID)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D043. Shop-side financial ledger for one Buy_Buyer at one Shop. Scoped by ShopID so residual credit can never transfer between Shops and never becomes a marketplace wallet (Agreement clause 9.3).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_Account';
GO

/* ------------------------------------------------- Buy_Buyer restrictions ------
   D044/D045: Shop-level and platform-wide restrictions are independent records. */
CREATE TABLE philmart.Buy_Restriction (
    ID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_br_id DEFAULT NEWSEQUENTIALID()
                                 CONSTRAINT PK_buyer_restriction PRIMARY KEY,
    BuyerID    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_br_buyer REFERENCES philmart.Buy_Buyer(ID),
    Scope       VARCHAR(20)      NOT NULL,
    ShopID     UNIQUEIDENTIFIER NULL CONSTRAINT FK_br_shop REFERENCES philmart.Shop_Shop(ID),
    Reason      NVARCHAR(1000)   NOT NULL,
    ImposedAt  DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_br_imposed DEFAULT (philmart.ServerNow()),
    ImposedBy  UNIQUEIDENTIFIER NOT NULL,
    LiftedAt   DATETIMEOFFSET(7) NULL,
    LiftedBy   UNIQUEIDENTIFIER NULL,
    LiftReason NVARCHAR(1000)   NULL,
    CONSTRAINT CK_br_scope CHECK (Scope IN ('Shop_Shop','platform')),
    CONSTRAINT CK_br_reason CHECK (LEN(LTRIM(RTRIM(Reason))) > 0),
    CONSTRAINT CK_br_scope_shop CHECK (
        (Scope = 'Shop_Shop'     AND ShopID IS NOT NULL) OR
        (Scope = 'platform' AND ShopID IS NULL))
);
GO
CREATE INDEX IX_br_active ON philmart.Buy_Restriction (BuyerID, Scope) WHERE LiftedAt IS NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D044/D045. A Shop may restrict a Buy_Buyer from new purchases and bids with that Shop, with a mandatory reason. PHILMART may impose a platform-wide restriction. A Shop can lift only its own. PHILMART restriction takes precedence. Each restriction is independently recorded and audited. Existing transactions continue in every case — only NEW commitment actions are blocked.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_Restriction';
GO

/* Is this Buy_Buyer blocked from a new commitment at this Shop? Server-side check
   used at Buy Now and Confirm Bid (BR-03-R08). Never a UI-only hide.         */
CREATE FUNCTION philmart.BuyerIsRestricted
    (@buyerId UNIQUEIDENTIFIER, @shopId UNIQUEIDENTIFIER)
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1 FROM philmart.Buy_Restriction AS r
        WHERE r.BuyerID = @buyerId
          AND r.LiftedAt IS NULL
          AND (r.Scope = 'platform' OR r.ShopID = @shopId)
    ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END;
GO

/* ------------------------------------------------------ legal documents ---- */
CREATE TABLE philmart.Sys_LegalDocument (
    Code            VARCHAR(40)   NOT NULL CONSTRAINT PK_legal_document PRIMARY KEY,
    Name            NVARCHAR(200) NOT NULL,
    Audience        VARCHAR(10)   NOT NULL,
    AcceptanceMode VARCHAR(20)   NOT NULL,
    Description     NVARCHAR(500) NULL,
    CONSTRAINT CK_ld_audience CHECK (Audience IN ('Buy_Buyer','Shop_Shop','both')),
    CONSTRAINT CK_ld_mode CHECK (AcceptanceMode IN ('accept','acknowledge'))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Buyer registration legal semantics: ACCEPT the Buyer Terms and the Rules of Auction; ACKNOWLEDGE the Privacy Policy version presented.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_LegalDocument';
GO

CREATE TABLE philmart.Sys_LegalDocumentVersion (
    ID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ldv_id DEFAULT NEWSEQUENTIALID()
                                    CONSTRAINT PK_legal_document_version PRIMARY KEY,
    DocumentCode  VARCHAR(40)      NOT NULL
                   CONSTRAINT FK_ldv_doc REFERENCES philmart.Sys_LegalDocument(Code),
    Version        VARCHAR(20)      NOT NULL,
    Body           NVARCHAR(MAX)    NOT NULL,
    ContentSha256 CHAR(64)         NOT NULL,
    IsDraft       BIT              NOT NULL CONSTRAINT DF_ldv_draft DEFAULT (1),
    PublishedAt   DATETIMEOFFSET(7) NULL,
    SupersededAt  DATETIMEOFFSET(7) NULL,
    ApprovedBy    NVARCHAR(200)    NULL,
    CreatedAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ldv_created DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_ldv_doc_version UNIQUE (DocumentCode, Version)
);
GO
CREATE UNIQUE INDEX UX_ldv_one_published ON philmart.Sys_LegalDocumentVersion (DocumentCode)
    WHERE PublishedAt IS NOT NULL AND SupersededAt IS NULL;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Proposed legal wording is DRAFT pending professional legal review. Mechanics (placement, versioning, acceptance, audit) may be built now; draft wording must never be published as approved production content. Production Release gate, Agreement clause 24.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sys_LegalDocumentVersion';
GO

/* Append-only. A renewed acceptance is a NEW row, never an update (BR-01-R05). */
CREATE TABLE philmart.Sys_LegalAcceptance (
    ID               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_la_id DEFAULT NEWSEQUENTIALID()
                                      CONSTRAINT PK_legal_acceptance PRIMARY KEY,
    VersionID       UNIQUEIDENTIFIER NOT NULL
                     CONSTRAINT FK_la_version REFERENCES philmart.Sys_LegalDocumentVersion(ID),
    DocumentCode    VARCHAR(40)      NOT NULL
                     CONSTRAINT FK_la_doc REFERENCES philmart.Sys_LegalDocument(Code),
    DocumentVersion VARCHAR(20)      NOT NULL,
    SubjectKind     VARCHAR(20)      NOT NULL,
    BuyerID         UNIQUEIDENTIFIER NULL CONSTRAINT FK_la_buyer REFERENCES philmart.Buy_Buyer(ID),
    ShopUserID     UNIQUEIDENTIFIER NULL CONSTRAINT FK_la_shopuser REFERENCES philmart.Shop_User(ID),
    ShopID          UNIQUEIDENTIFIER NULL CONSTRAINT FK_la_shop REFERENCES philmart.Shop_Shop(ID),
    Context          VARCHAR(40)      NOT NULL,
    AcceptedAt      DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_la_accepted DEFAULT (philmart.ServerNow()),
    IpAddress       VARCHAR(45)      NULL,
    UserAgent       NVARCHAR(500)    NULL,
    CONSTRAINT CK_la_subject_kind CHECK (SubjectKind IN ('Buy_Buyer','Shop_User')),
    CONSTRAINT CK_la_context CHECK (Context IN ('registration','buy_now','confirm_bid','shop_setup')),
    CONSTRAINT CK_la_subject CHECK (
        (SubjectKind = 'Buy_Buyer'     AND BuyerID IS NOT NULL AND ShopUserID IS NULL) OR
        (SubjectKind = 'Shop_User' AND ShopUserID IS NOT NULL AND BuyerID IS NULL))
);
GO
CREATE INDEX IX_la_buyer ON philmart.Sys_LegalAcceptance (BuyerID, DocumentCode, AcceptedAt DESC);
GO

CREATE TRIGGER philmart.TR_legal_acceptance_append_only
ON philmart.Sys_LegalAcceptance
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50002, 'philmart.legal_acceptance is append-only. A renewed acceptance is a NEW linked row for the new version, never an update (BR-01-R05).', 1;
END;
GO

/* Has this Buy_Buyer accepted the currently published version of a document?
   Drives the renewed-acceptance gate before a further commitment (BR-01-R09). */
CREATE FUNCTION philmart.BuyerHasCurrentAcceptance
    (@buyerId UNIQUEIDENTIFIER, @documentCode VARCHAR(40))
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN EXISTS (
        SELECT 1
        FROM philmart.Sys_LegalDocumentVersion AS v
        JOIN philmart.Sys_LegalAcceptance AS a
          ON a.VersionID = v.ID AND a.BuyerID = @buyerId
        WHERE v.DocumentCode = @documentCode
          AND v.PublishedAt IS NOT NULL
          AND v.SupersededAt IS NULL
    ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END;
END;
GO

/* ========================================================================
   PART 3 OF 10 : 003_onboarding.sql
   applications, setup sections, shop settings, locations, sellers
   ===================================================================== */
PRINT '>>> PHILMART part 3 of 10: 003_onboarding.sql';
GO

/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 3 of 9 : Shop_Shop application, setup, settings, locations, sellers
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------- Shop_Shop application --------
   BR-06. Five steps: Applicant Contacts, Material Selling Activity,
   Experience and References, Current Selling Platforms, Review and Submit.   */
CREATE TABLE philmart.Shop_Application (
    ID               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sa_id DEFAULT NEWSEQUENTIALID()
                                      CONSTRAINT PK_shop_application PRIMARY KEY,
    ShopID          UNIQUEIDENTIFIER NULL CONSTRAINT FK_sa_shop REFERENCES philmart.Shop_Shop(ID),
    Reference        VARCHAR(40)      NOT NULL CONSTRAINT UQ_sa_reference UNIQUE,
    ApplicantEmail  NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    ApplicantName   NVARCHAR(200)    NOT NULL,
    ApplicantMobile VARCHAR(40)      NULL,
    TradingName     NVARCHAR(200)    NOT NULL,
    CurrentStep     TINYINT          NOT NULL CONSTRAINT DF_sa_step DEFAULT (1),
    SubmittedAt     DATETIMEOFFSET(7) NULL,
    CreatedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sa_created DEFAULT (philmart.ServerNow()),
    UpdatedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sa_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_sa_step CHECK (CurrentStep BETWEEN 1 AND 5)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D002. On successful submission the application enters awaiting-review state and EML-021 Shop Registration/Application Received is sent.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_Application';
GO

/* Step payloads as validated JSON: the five steps capture free-form commercial
   background that is evidence, not operational data.                         */
CREATE TABLE philmart.Shop_ApplicationStep (
    ApplicationID UNIQUEIDENTIFIER NOT NULL
                   CONSTRAINT FK_sas_app REFERENCES philmart.Shop_Application(ID),
    StepNumber    TINYINT          NOT NULL,
    StepCode      VARCHAR(60)      NOT NULL,
    Payload        NVARCHAR(MAX)    NOT NULL,
    CompletedAt   DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sas_completed DEFAULT (philmart.ServerNow()),
    CONSTRAINT PK_shop_application_step PRIMARY KEY (ApplicationID, StepNumber),
    CONSTRAINT CK_sas_step CHECK (StepNumber BETWEEN 1 AND 5),
    CONSTRAINT CK_sas_json CHECK (ISJSON(Payload) = 1)
);
GO

/* D001: approval grants Shop Setup access ONLY. It does not activate the Shop. */
CREATE TABLE philmart.Shop_ApplicationReview (
    ID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sar_id DEFAULT NEWSEQUENTIALID()
                                    CONSTRAINT PK_shop_application_review PRIMARY KEY,
    ApplicationID UNIQUEIDENTIFIER NOT NULL
                   CONSTRAINT FK_sar_app REFERENCES philmart.Shop_Application(ID),
    Decision       VARCHAR(20)      NOT NULL,
    Reason         NVARCHAR(1000)   NOT NULL,
    DecidedAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sar_decided DEFAULT (philmart.ServerNow()),
    DecidedBy     UNIQUEIDENTIFIER NOT NULL
                   CONSTRAINT FK_sar_by REFERENCES philmart.Sys_PlatformUser(ID),
    CONSTRAINT CK_sar_decision CHECK (Decision IN ('approved','rejected')),
    CONSTRAINT CK_sar_reason CHECK (LEN(LTRIM(RTRIM(Reason))) > 0)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D001. Approval grants Shop Setup access only; it does not activate the Shop and sends no activation email. All decisions and reasons are retained as audit history regardless of outcome (BR-06-R05).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_ApplicationReview';
GO

CREATE TRIGGER philmart.TR_shop_application_review_append_only
ON philmart.Shop_ApplicationReview
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50003, 'philmart.shop_application_review is append-only. All application decisions and reasons are retained as audit history regardless of outcome (BR-06-R05).', 1;
END;
GO

/* ------------------------------------------------------- Shop_Shop setup -------
   BR-07. Nine setup surfaces. Setup validates during completion; when all
   mandatory setup is complete and valid the Shop activates AUTOMATICALLY.
   There is no second PHILMART activation approval (D005).                    */
CREATE TABLE philmart.Shop_SetupSection (
    Code       VARCHAR(60)   NOT NULL CONSTRAINT PK_shop_setup_section PRIMARY KEY,
    Name       NVARCHAR(200) NOT NULL,
    Mandatory  BIT           NOT NULL CONSTRAINT DF_sss_mandatory DEFAULT (1),
    SortOrder INT           NOT NULL CONSTRAINT DF_sss_sort DEFAULT (0)
);
GO

CREATE TABLE philmart.Shop_SetupProgress (
    ShopID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ssp_shop REFERENCES philmart.Shop_Shop(ID),
    SectionCode      VARCHAR(60)      NOT NULL
                      CONSTRAINT FK_ssp_section REFERENCES philmart.Shop_SetupSection(Code),
    IsValid          BIT              NOT NULL CONSTRAINT DF_ssp_valid DEFAULT (0),
    ValidationErrors NVARCHAR(MAX)    NULL,
    CompletedAt      DATETIMEOFFSET(7) NULL,
    UpdatedAt        DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ssp_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT PK_shop_setup_progress PRIMARY KEY (ShopID, SectionCode),
    CONSTRAINT CK_ssp_errors_json CHECK (ValidationErrors IS NULL OR ISJSON(ValidationErrors) = 1)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D005. Setup validates during completion. When every mandatory section is complete and valid, activation fires automatically via trigger (part 9). PHILMART may scrutinise setup afterwards, which does not block activation. There is no second PHILMART activation approval step.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_SetupProgress';
GO

/* D006/D052: Setup initialises the ongoing Shop-controlled settings; Shop
   Settings maintains the SAME persisted values afterwards. One underlying
   setting has exactly one source of truth — hence ONE table, not two.        */
CREATE TABLE philmart.Shop_Settings (
    ShopID                  UNIQUEIDENTIFIER NOT NULL
                             CONSTRAINT PK_shop_settings PRIMARY KEY
                             CONSTRAINT FK_ss_shop REFERENCES philmart.Shop_Shop(ID),
    PublicProfileName      NVARCHAR(200)    NULL,
    PublicProfileBlurb     NVARCHAR(MAX)    NULL,
    LogoAssetID            UNIQUEIDENTIFIER NULL,
    ContactEmail            NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    ContactPhone            VARCHAR(40)      NULL,

    /* Shop-controlled operational values, subject only to explicit platform
       constraints (D052, configuration rules).                              */
    PaidItemAttentionDays INT              NOT NULL CONSTRAINT DF_ss_attention DEFAULT (7),
    InvoiceDueDays         INT              NOT NULL CONSTRAINT DF_ss_due DEFAULT (7),
    CombinedShippingEnabled BIT             NOT NULL CONSTRAINT DF_ss_combined DEFAULT (1),
    DefaultCommissionPct   DECIMAL(9,6)     NULL,

    CreatedAt               DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ss_created DEFAULT (philmart.ServerNow()),
    UpdatedAt               DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ss_updated DEFAULT (philmart.ServerNow()),

    CONSTRAINT CK_ss_attention CHECK (PaidItemAttentionDays BETWEEN 1 AND 90),
    CONSTRAINT CK_ss_due CHECK (InvoiceDueDays BETWEEN 1 AND 90),
    CONSTRAINT CK_ss_commission CHECK (DefaultCommissionPct IS NULL
                                       OR (DefaultCommissionPct >= 0 AND DefaultCommissionPct <= 100))
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D006/D052. ONE table for Shop-controlled values. Shop Setup initialises these rows; Shop Settings maintains the same rows afterwards. Do not create a separate "setup" copy — one underlying setting has one source of truth. D024: paid_item_attention_days is the Shop-controlled Paid Item Attention threshold, subject only to explicit platform constraints; the alert never changes workflow state.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_Settings';
GO

/* Commercial and Sale_Payment arrangements surface (BR-07-R08). */
CREATE TABLE philmart.Shop_CommercialTerms (
    ID                     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sct_id DEFAULT NEWSEQUENTIALID()
                                            CONSTRAINT PK_shop_commercial_terms PRIMARY KEY,
    ShopID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sct_shop REFERENCES philmart.Shop_Shop(ID),
    BankingReferenceNote NVARCHAR(500)    NULL,
    PaymentInstructions   NVARCHAR(MAX)    NULL,
    EffectiveFrom         DATE             NOT NULL CONSTRAINT DF_sct_from DEFAULT (CAST(SYSUTCDATETIME() AS DATE)),
    EffectiveTo           DATE             NULL,
    CreatedAt             DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sct_created DEFAULT (philmart.ServerNow()),
    CONSTRAINT CK_sct_effective CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Agreement clause 9.3. PaymentInstructions is free text telling the Buy_Buyer how to pay the Shop DIRECTLY, outside PHILMART. It must not become a stored Sale_Payment instrument, and no gateway integration may be attached to it.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_CommercialTerms';
GO

/* ------------------------------------------- locations & delivery --------- */
CREATE TABLE philmart.Shop_Location (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sl_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_shop_location PRIMARY KEY,
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sl_shop REFERENCES philmart.Shop_Shop(ID),
    Name                NVARCHAR(200)    NOT NULL,
    IsCollectionPoint BIT              NOT NULL CONSTRAINT DF_sl_collection DEFAULT (0),
    AddressLine1       NVARCHAR(200)    NULL,
    AddressLine2       NVARCHAR(200)    NULL,
    City                NVARCHAR(120)    NULL,
    Province            NVARCHAR(120)    NULL,
    PostalCode         VARCHAR(20)      NULL,
    CountryCode        CHAR(2)          NOT NULL CONSTRAINT DF_sl_country DEFAULT ('ZA'),
    CollectionHours    NVARCHAR(500)    NULL,
    ArchivedAt         DATETIMEOFFSET(7) NULL,
    CreatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sl_created DEFAULT (philmart.ServerNow()),
    UpdatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sl_updated DEFAULT (philmart.ServerNow())
);
GO

/* Where stock physically sits. Distinct from a collection point. */
CREATE TABLE philmart.Shop_StockLocation (
    ID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ssl_id DEFAULT NEWSEQUENTIALID()
                                 CONSTRAINT PK_shop_stock_location PRIMARY KEY,
    ShopID     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_ssl_shop REFERENCES philmart.Shop_Shop(ID),
    Code        VARCHAR(40)      NOT NULL,
    Name        NVARCHAR(200)    NOT NULL,
    ArchivedAt DATETIMEOFFSET(7) NULL,
    CreatedAt  DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_ssl_created DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_ssl_shop_code UNIQUE (ShopID, Code)
);
GO

/* Which platform delivery methods this Shop offers, and its notes. */
CREATE TABLE philmart.Shop_DeliveryMethod (
    ID                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sdm_id DEFAULT NEWSEQUENTIALID()
                                         CONSTRAINT PK_shop_delivery_method PRIMARY KEY,
    ShopID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sdm_shop REFERENCES philmart.Shop_Shop(ID),
    DeliveryMethodID  UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT FK_sdm_method REFERENCES philmart.Sys_DeliveryMethod(ID),
    Enabled             BIT              NOT NULL CONSTRAINT DF_sdm_enabled DEFAULT (1),
    SupplementaryNotes NVARCHAR(MAX)    NULL,
    CreatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sdm_created DEFAULT (philmart.ServerNow()),
    UpdatedAt          DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sdm_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_sdm_shop_method UNIQUE (ShopID, DeliveryMethodID)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D071. SupplementaryNotes holds optional Supplementary Delivery Notes: practical information ONLY. PHILMART-controlled delivery wording remains authoritative. Shop notes must not alter or contradict Sale_Payment, workflow, Sale_Fulfilment, delivery method, tariff, pickup point, timing or other controlled transaction rules. Render them BELOW the controlled wording, never in place of it.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_DeliveryMethod';
GO

/* --------------------------------------------------- sellers / consignors --
   Not platform users in V1. The Shop maintains the relationship; the Seller
   receives the monthly EML-008 statement.                                    */
CREATE TABLE philmart.Sell_Seller (
    ID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sel_id DEFAULT NEWSEQUENTIALID()
                                       CONSTRAINT PK_seller PRIMARY KEY,
    ShopID           UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_sel_shop REFERENCES philmart.Shop_Shop(ID),
    Reference         VARCHAR(40)      NOT NULL,
    FullName         NVARCHAR(200)    NOT NULL,
    Email             NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Mobile            VARCHAR(40)      NULL,
    AddressLine1     NVARCHAR(200)    NULL,
    City              NVARCHAR(120)    NULL,
    PostalCode       VARCHAR(20)      NULL,
    CountryCode      CHAR(2)          NOT NULL CONSTRAINT DF_sel_country DEFAULT ('ZA'),
    StatementEnabled BIT              NOT NULL CONSTRAINT DF_sel_statement DEFAULT (1),
    ArchivedAt       DATETIMEOFFSET(7) NULL,
    CreatedAt        DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sel_created DEFAULT (philmart.ServerNow()),
    UpdatedAt        DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sel_updated DEFAULT (philmart.ServerNow()),
    CONSTRAINT UQ_sel_shop_reference UNIQUE (ShopID, Reference)
);
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D057/D059. Seller or Consignor: owner of consigned stock held by a Shop. NOT a platform user in V1 — no login. Receives EML-008 monthly where they have financial activity, an outstanding balance, or consignment stock still held. No empty report is required.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Sell_Seller';
GO

/* ========================================================================
   PART 4 OF 10 : 004_items.sql
   items, transition rules, state history, images, bulk upload
   ===================================================================== */
PRINT '>>> PHILMART part 4 of 10: 004_items.sql';
GO

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

/* ========================================================================
   PART 5 OF 10 : 005_listings.sql
   listings, bids, outbid throttle, auction events
   ===================================================================== */
PRINT '>>> PHILMART part 5 of 10: 005_listings.sql';
GO

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

/* ========================================================================
   PART 6 OF 10 : 006_money.sql
   sales, invoices, payments, allocation, buyer ledger
   ===================================================================== */
PRINT '>>> PHILMART part 6 of 10: 006_money.sql';
GO

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

/* ========================================================================
   PART 7 OF 10 : 007_fulfilment_fees.sql
   fulfilment, seller proceeds and payments, PHILMART fees
   ===================================================================== */
PRINT '>>> PHILMART part 7 of 10: 007_fulfilment_fees.sql';
GO

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

/* ========================================================================
   PART 8 OF 10 : 008_service_comms.sql
   buyer queries, notifications, email catalogue, reports
   ===================================================================== */
PRINT '>>> PHILMART part 8 of 10: 008_service_comms.sql';
GO

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

/* ========================================================================
   PART 9 OF 10 : 009_enforcement.sql
   security, RLS, immutability triggers, state guard, procedures
   ===================================================================== */
PRINT '>>> PHILMART part 9 of 10: 009_enforcement.sql';
GO

/* ===========================================================================
   PHILMART V1 — MS SQL Server
   Part 9 of 9 : security, Row Level Security, immutability triggers,
                 state machine guard, auction and money procedures

   Agreement clause 9.1: a failure of Shop isolation is a CRITICAL Severity
   Defect. RLS here is defence in depth — the API must ALSO authorise every
   operation server-side. Neither layer alone is sufficient.

   EVERY trigger below is SET-BASED. SQL Server fires triggers once per
   STATEMENT, not once per row. A row-at-a-time guard silently passes
   multi-row writes, which is the single most dangerous difference from the
   PostgreSQL original.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------- application security ---- */
IF DATABASE_PRINCIPAL_ID('philmart_app') IS NULL
    CREATE ROLE philmart_app;
GO
IF DATABASE_PRINCIPAL_ID('philmart_migrator') IS NULL
    CREATE ROLE philmart_migrator;
GO

GRANT SELECT, INSERT, UPDATE ON SCHEMA::philmart TO philmart_app;
GRANT EXECUTE ON SCHEMA::philmart TO philmart_app;
/* Deliberately NOT granted: DELETE. Nothing in this system is hard-deleted. */
DENY DELETE ON SCHEMA::philmart TO philmart_app;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'The runtime role. DELETE is explicitly DENIED across the schema: corrections are linked reversals, adjustments or superseding records (Agreement clause 8). It must NOT be granted db_owner, sysadmin, or any membership that bypasses Row Level Security — RLS does not apply to members of db_owner.',
 @level0type=N'USER',@level0name=N'philmart_app';
GO

/* --------------------------------------------------- Row Level Security ----
   SQL Server RLS is an inline table-valued predicate function plus a security
   policy. The predicate is evaluated for every row, so it must be cheap and
   must be schemabound.

   IMPORTANT: RLS does NOT apply to members of db_owner or to sysadmin. The
   application must connect as a principal in philmart_app and nothing more.  */
CREATE FUNCTION philmart.FN_ShopTenantPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

CREATE FUNCTION philmart.FN_BuyerSelfPredicate (@buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* Rows whose ShopID is NULL are PLATFORM-scoped and legitimately visible to
   every Shop: a PHILMART-run auction event, and a platform-wide Buy_Buyer
   restriction which takes precedence over a Shop's own (D045). Using the strict
   predicate here would hide exactly the rows a Shop must obey.               */
CREATE FUNCTION philmart.FN_ShopOrPlatformPredicate (@shopId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR @shopId IS NULL
       OR @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER)
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* Rows a Shop reads by tenancy AND a Buy_Buyer reads about themselves: a legal
   acceptance, an outbound email. SQL Server permits only one filter predicate
   per table, so the two audiences are combined into one function rather than
   two policies.                                                              */
CREATE FUNCTION philmart.FN_ShopOrBuyerPredicate
    (@shopId AS UNIQUEIDENTIFIER, @buyerId AS UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS FnResult
    WHERE CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'platform_admin'
       OR (@shopId IS NOT NULL
           AND @shopId = CAST(SESSION_CONTEXT(N'philmart.shop_id') AS UNIQUEIDENTIFIER))
       OR (@buyerId IS NOT NULL
           AND CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'Buy_Buyer'
           AND @buyerId = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER))
       OR DATABASE_PRINCIPAL_ID() = DATABASE_PRINCIPAL_ID('philmart_migrator');
GO

/* One policy over every Shop-owned table. FILTER hides rows on read; BLOCK
   refuses writes that would place a row outside the caller's tenant.         */
CREATE SECURITY POLICY philmart.ShopTenantPolicy
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_User,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_User,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_UserPermission,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_UserPermission,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Settings,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Settings,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_CommercialTerms,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_CommercialTerms,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Location,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Location,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_StockLocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_StockLocation,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_DeliveryMethod,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_DeliveryMethod,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_SetupProgress,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Seller,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Item,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Item,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Image,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_Image,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_StateHistory,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadBatch,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Item_BulkUploadRow,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Listing,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Listing,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Bid,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_Bid,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Transaction,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Transaction,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_FulfilmentSnapshot,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_FulfilmentSnapshot,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Fulfilment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Fulfilment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaidItemAttention,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaidItemAttention,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_CombinedShippingGroup,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_CombinedShippingGroup,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Invoice,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Invoice,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_InvoiceLine,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_InvoiceLine,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Payment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_Payment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaymentAllocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sale_PaymentAllocation,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Account,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Account,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_AccountEntry,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_AccountEntry,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_ProceedsEntry,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_ProceedsEntry,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Payment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sell_Payment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopConfig,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopConfig,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Accrual,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Accrual,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Invoice,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_Invoice,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_InvoiceLine,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_InvoiceLine,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopPayment,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopPayment,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopAllocation,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Fee_ShopAllocation,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Query,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_Query,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_QueryMessage,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Buy_QueryMessage,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Notification,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Notification,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_SettingValidationFlag,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_SettingValidationFlag,
    /* Strict: a NULL ShopID on these tables is platform-scoped and stays
       admin-only, because "ShopID = current" is UNKNOWN against NULL and the
       row is filtered out. That is the intended behaviour here.              */
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_AuditEvent,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Sys_AuditEvent,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_GovernanceException,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_GovernanceException,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_Run,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Rpt_Run,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Application,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.Shop_Application,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_AuctionEventShop,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_AuctionEventShop,
    ADD FILTER PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_OutbidAlertLog,
    ADD BLOCK  PREDICATE philmart.FN_ShopTenantPredicate(ShopID) ON philmart.List_OutbidAlertLog
WITH (STATE = ON);
GO

CREATE SECURITY POLICY philmart.BuyerSelfPolicy
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_Address,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_Address,
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_ShippingPreference,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_ShippingPreference,
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_CommunicationPreference,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_CommunicationPreference
WITH (STATE = ON);
GO

/* PHILMART-run auction events (ShopID NULL) must be visible to participating
   Shops; a platform-wide Buy_Buyer restriction (ShopID NULL) must be visible to
   every Shop because it takes precedence over their own (D045).             */
CREATE SECURITY POLICY philmart.PlatformVisiblePolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrPlatformPredicate(ShopID) ON philmart.List_AuctionEvent
WITH (STATE = ON);
GO

/* Read by a Shop for its own rows, and by a Buy_Buyer for their own. */
CREATE SECURITY POLICY philmart.ShopOrBuyerPolicy
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_LegalAcceptance,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Sys_EmailMessage,
    ADD FILTER PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction,
    ADD BLOCK  PREDICATE philmart.FN_ShopOrBuyerPredicate(ShopID, BuyerID) ON philmart.Buy_Restriction
WITH (STATE = ON);
GO

/* Note on Buy_Query: the Shop tenant predicate above governs Shop access.
   The Buy_Buyer's own view of the SAME case row (D046 — one case, two lawful
   readers) is served through a dedicated API path that runs with
   actor_kind = 'Buy_Buyer'; because SQL Server applies one predicate per table,
   that path reads through philmart.v_buyer_query_self below rather than a
   second policy.                                                            */
CREATE VIEW philmart.VW_BuyerQuerySelf
WITH SCHEMABINDING
AS
SELECT q.ID, q.ShopID, q.BuyerID, q.Reference, q.Subject, q.Status,
       q.OpenedAt, q.LastMessageAt, q.ClosedAt, q.ReopenedCount
FROM philmart.Buy_Query AS q
WHERE q.BuyerID = CAST(SESSION_CONTEXT(N'philmart.actor_id') AS UNIQUEIDENTIFIER)
  AND CAST(SESSION_CONTEXT(N'philmart.actor_kind') AS VARCHAR(20)) = 'Buy_Buyer';
GO

/* --------------------------------------------- immutability enforcement ---
   D019 / BR-15-R02: an ISSUED Sale_Invoice is immutable. Only the supersede link and
   a cancellation may be set, and only once. Set-based.                       */
CREATE TRIGGER philmart.TR_invoice_immutable_when_issued
ON philmart.Sale_Invoice
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    IF EXISTS (
        SELECT 1
        FROM deleted  AS d
        JOIN inserted AS i ON i.ID = d.ID
        WHERE d.State = 'issued'
          /* permitted: a single cancellation */
          AND NOT (i.State = 'cancelled' AND d.State <> 'cancelled')
          /* permitted: linking a superseding Sale_Invoice, once */
          AND NOT (d.SupersededByID IS NULL AND i.SupersededByID IS NOT NULL
                   AND i.State = d.State
                   AND i.TotalMinor = d.TotalMinor
                   AND i.SubtotalMinor = d.SubtotalMinor
                   AND i.ShippingMinor = d.ShippingMinor
                   AND i.AdjustmentMinor = d.AdjustmentMinor))
    BEGIN
        THROW 50021, 'An issued Sale_Invoice is immutable (D019). Correct it with a linked credit, adjustment or superseding Sale_Invoice — never by editing. Only a cancellation or a one-time supersede link is permitted.', 1;
    END
END;
GO

CREATE TRIGGER philmart.TR_invoice_no_delete
ON philmart.Sale_Invoice
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50022, 'philmart.invoice is never deleted (D019).', 1;
END;
GO

/* Invoice lines follow the Sale_Invoice: mutable only while the Sale_Invoice is draft. */
CREATE TRIGGER philmart.TR_invoice_line_immutable
ON philmart.Sale_InvoiceLine
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1 FROM deleted AS d
        JOIN philmart.Sale_Invoice AS inv ON inv.ID = d.InvoiceID
        WHERE inv.State <> 'draft')
    BEGIN
        THROW 50023, 'Invoice lines are immutable once the Sale_Invoice is issued (D019).', 1;
    END
END;
GO

/* D012/D013: a historical Listing is read-only and is NEVER reopened. */
CREATE TRIGGER philmart.TR_listing_historical_readonly
ON philmart.List_Listing
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1 FROM deleted AS d
        WHERE d.State IN ('sold','unsold','withdrawn','expired','cancelled'))
    BEGIN
        THROW 50024, 'A historical Listing (sold, unsold, withdrawn, expired or cancelled) is read-only. It is never reopened — a further offer of the Item uses a NEW Listing (D012, D013).', 1;
    END
END;
GO

CREATE TRIGGER philmart.TR_listing_no_delete
ON philmart.List_Listing
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50025, 'philmart.listing is never deleted.', 1;
END;
GO

/* D039: identity fields are read-only after registration completes. */
CREATE TRIGGER philmart.TR_buyer_identity_readonly
ON philmart.Buy_Buyer
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF EXISTS (
        SELECT 1
        FROM deleted AS d JOIN inserted AS i ON i.ID = d.ID
        WHERE d.RegistrationCompletedAt IS NOT NULL
          AND (ISNULL(i.IdentificationType,'')   <> ISNULL(d.IdentificationType,'')
            OR ISNULL(i.IdentificationNumber,'') <> ISNULL(d.IdentificationNumber,'')
            OR ISNULL(i.DateOfBirth,'1900-01-01') <> ISNULL(d.DateOfBirth,'1900-01-01')))
    BEGIN
        THROW 50026, 'Identification type, identification number and date of birth are read-only account and audit information after registration (D039).', 1;
    END
END;
GO

/* --------------------------------------------- Item_Item state machine guard ---
   Set-based. Validates every transition in the statement against
   Item_TransitionRule, then writes one history row per changed Item_Item.        */
CREATE TRIGGER philmart.TR_item_transition_guard
ON philmart.Item_Item
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    IF NOT UPDATE(State) RETURN;

    /* 1. Refuse any transition absent from the state machine. */
    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN inserted AS i ON i.ID = d.ID
        LEFT JOIN philmart.Item_TransitionRule AS r
               ON r.FromState = d.State AND r.ToState = i.State
        WHERE i.State <> d.State AND r.FromState IS NULL)
    BEGIN
        THROW 50027, 'Illegal Item state transition. The move is not present in philmart.item_transition_rule, which is the authoritative state machine. Note there is no exit from returned_to_seller or written_off (both terminal) and no Pending Return state (D065).', 1;
    END

    /* 2. Refuse a transition that requires a reason without one. */
    IF EXISTS (
        SELECT 1
        FROM deleted AS d
        JOIN inserted AS i ON i.ID = d.ID
        JOIN philmart.Item_TransitionRule AS r
          ON r.FromState = d.State AND r.ToState = i.State
        WHERE i.State <> d.State
          AND r.RequiresReason = 1
          AND (i.RemovalNote IS NULL OR LEN(LTRIM(RTRIM(i.RemovalNote))) = 0))
    BEGIN
        THROW 50028, 'This Item state transition requires a recorded reason (see Item_TransitionRule.decision_ref). D066: Remove from Stock with reason Other requires a mandatory internal note.', 1;
    END

    /* 3. Maintain the D061 ageing clock and the state timestamp. */
    UPDATE it
       SET ReadyToListSince = CASE WHEN i.State = 'ready_to_list'
                                      THEN philmart.ServerNow() ELSE NULL END,
           StateChangedAt    = philmart.ServerNow()
    FROM philmart.Item_Item AS it
    JOIN inserted AS i ON i.ID = it.ID
    JOIN deleted  AS d ON d.ID = it.ID
    WHERE i.State <> d.State;

    /* 4. One history row per changed Item_Item (BR-10-R12). */
    INSERT INTO philmart.Item_StateHistory
        (ItemID, ShopID, FromState, ToState, Reason, ChangedBy, ActorKind)
    SELECT i.ID, i.ShopID, d.State, i.State,
           NULLIF(LTRIM(RTRIM(ISNULL(i.RemovalNote,''))), ''),
           philmart.CurrentActorID(),
           philmart.CurrentActorKind()
    FROM inserted AS i
    JOIN deleted  AS d ON d.ID = i.ID
    WHERE i.State <> d.State;
END;
GO

CREATE TRIGGER philmart.TR_item_no_delete
ON philmart.Item_Item
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;
    THROW 50029, 'philmart.item is never deleted. Item history survives every terminal state.', 1;
END;
GO

/* D062: no List_Listing may permit sale below the Seller Minimum Price. Set-based. */
CREATE TRIGGER philmart.TR_listing_seller_minimum_price
ON philmart.List_Listing
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN philmart.Item_Item AS it ON it.ID = i.ItemID
        WHERE it.SellerMinimumPriceMinor IS NOT NULL
          AND ((i.ListingType = 'fixed_price'
                AND i.PriceMinor IS NOT NULL
                AND i.PriceMinor < it.SellerMinimumPriceMinor)
            OR (i.ListingType = 'auction'
                AND ISNULL(i.ReservePriceMinor, i.StartingPriceMinor)
                    < it.SellerMinimumPriceMinor)))
    BEGIN
        THROW 50030, 'Price or effective auction minimum is below the Seller Minimum Price for this Item_Item (D062). Seller Minimum Price is the minimum GROSS selling price before Shop commission.', 1;
    END
END;
GO

/* --------------------------------------- automatic Shop_Shop activation --------
   D005: when every mandatory setup section is complete and valid, the Shop
   activates AUTOMATICALLY. There is no second PHILMART approval step.        */
CREATE TRIGGER philmart.TR_shop_setup_auto_activation
ON philmart.Shop_SetupProgress
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ready TABLE (ShopID UNIQUEIDENTIFIER PRIMARY KEY);

    INSERT INTO @ready (ShopID)
    SELECT DISTINCT s.ID
    FROM philmart.Shop_Shop AS s
    JOIN inserted AS i ON i.ShopID = s.ID
    WHERE s.Status = 'setup_access_granted'
      AND NOT EXISTS (
          SELECT 1
          FROM philmart.Shop_SetupSection AS sec
          LEFT JOIN philmart.Shop_SetupProgress AS p
                 ON p.SectionCode = sec.Code AND p.ShopID = s.ID
          WHERE sec.Mandatory = 1 AND ISNULL(p.IsValid, 0) = 0);

    IF NOT EXISTS (SELECT 1 FROM @ready) RETURN;

    UPDATE s
       SET Status = 'active',
           ActivatedAt = philmart.ServerNow(),
           UpdatedAt = philmart.ServerNow()
    FROM philmart.Shop_Shop AS s JOIN @ready AS r ON r.ShopID = s.ID;

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    SELECT philmart.CurrentActorID(), 'system', r.ShopID, 'Shop_Shop',
           CAST(r.ShopID AS VARCHAR(80)), 'Shop_Shop.activated_automatically',
           N'{"trigger":"valid_setup_completion","decision":"D005"}'
    FROM @ready AS r;
    /* EML-022 Shop Activated is queued by the application on this audit event. */
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D003/D005. Activation is automatic on valid setup completion, and EML-022 Shop Activated triggers HERE — not on application approval (D001, D003). EML-023 is retired and must not be sent (D004).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Shop_SetupProgress',
 @level2type=N'TRIGGER',@level2name=N'TR_shop_setup_auto_activation';
GO

/* ----------------------------------------------- auction List_Bid placement ----
   Must be called inside a SERIALIZABLE transaction. Agreement clause 9.2:
   concurrent requests must not silently overwrite or invalidate one another.
   The caller retries on error 1205 (deadlock victim).                        */
CREATE PROCEDURE philmart.P_List_Bid_Place
    @listingId      UNIQUEIDENTIFIER,
    @buyerId        UNIQUEIDENTIFIER,
    @amountMinor    BIGINT,
    @idempotencyKey VARCHAR(80),
    @bidId          UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();
    DECLARE @shopId UNIQUEIDENTIFIER, @type VARCHAR(20), @state VARCHAR(20),
            @startsAt DATETIMEOFFSET(7), @endsAt DATETIMEOFFSET(7),
            @startPrice BIGINT, @increment BIGINT,
            @soft INT, @softExt INT, @reference VARCHAR(40);

    /* Lock the List_Listing row for the duration of the decision. */
    SELECT @shopId = ShopID, @type = ListingType, @state = State,
           @startsAt = StartsAt, @endsAt = EndsAt,
           @startPrice = StartingPriceMinor, @increment = BidIncrementMinor,
           @soft = SoftCloseSeconds, @softExt = SoftCloseExtensionSeconds,
           @reference = Reference
    FROM philmart.List_Listing WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @listingId;

    IF @shopId IS NULL THROW 50031, 'Listing not found.', 1;

    /* Idempotent replay returns the original List_Bid rather than creating a second. */
    SELECT @bidId = ID FROM philmart.List_Bid
    WHERE ListingID = @listingId AND IdempotencyKey = @idempotencyKey;
    IF @bidId IS NOT NULL RETURN 0;

    IF @type <> 'auction' THROW 50032, 'Listing is not an auction.', 1;
    IF @state <> 'live' OR @now < @startsAt
        THROW 50033, 'Auction is not open for bidding.', 1;
    IF @now >= @endsAt THROW 50034, 'Auction has closed.', 1;

    /* D044/D045: restriction is enforced HERE, server-side, at the commitment
       point. A hidden button is not enforcement.                            */
    IF philmart.BuyerIsRestricted(@buyerId, @shopId) = 1
        THROW 50035, 'Buyer is restricted from bidding with this Shop (D044).', 1;

    DECLARE @currentHigh BIGINT, @nextSeq BIGINT;
    SELECT @currentHigh = ISNULL(MAX(AmountMinor), 0),
           @nextSeq     = ISNULL(MAX(SequenceNo), 0)
    FROM philmart.List_Bid WHERE ListingID = @listingId;

    IF @amountMinor < CASE WHEN @startPrice > @currentHigh + ISNULL(@increment, 1)
                            THEN @startPrice ELSE @currentHigh + ISNULL(@increment, 1) END
        THROW 50036, 'Bid does not meet the minimum next List_Bid.', 1;

    SET @nextSeq = @nextSeq + 1;
    SET @bidId = NEWID();

    INSERT INTO philmart.List_Bid
        (ID, ListingID, ShopID, BuyerID, AmountMinor, PlacedAt, SequenceNo, IdempotencyKey)
    VALUES (@bidId, @listingId, @shopId, @buyerId, @amountMinor, @now, @nextSeq, @idempotencyKey);

    /* D064 soft close: a qualifying late List_Bid extends the close, computed
       server-side against authoritative time.                              */
    DECLARE @extended BIT = 0;
    IF @soft IS NOT NULL AND DATEDIFF(SECOND, @now, @endsAt) <= @soft
    BEGIN
        UPDATE philmart.List_Listing
           SET EndsAt = DATEADD(SECOND, ISNULL(@softExt, @soft), @now),
               ExtensionCount = ExtensionCount + 1,
               OriginalEndsAt = ISNULL(OriginalEndsAt, @endsAt)
        WHERE ID = @listingId;

        UPDATE philmart.List_Bid SET TriggeredExtension = 1 WHERE ID = @bidId;
        SET @extended = 1;
    END

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    VALUES (@buyerId, 'Buy_Buyer', @shopId, 'List_Bid', CAST(@bidId AS VARCHAR(80)), 'List_Bid.placed',
            (SELECT @amountMinor AS AmountMinor, @nextSeq AS SequenceNo,
                    @extended AS extended_close FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'Agreement clause 9.2. MUST be called in a SERIALIZABLE transaction; the caller retries on error 1205 (deadlock victim). Covers simultaneous bids (UPDLOCK/HOLDLOCK plus SequenceNo), duplicate submission (idempotency_key), authoritative ordering, last-second bids and soft-close extension. Never trust a client timestamp.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_List_Bid_Place';
GO

/* --------------------------------------------------- auction close --------
   Idempotent: safe to re-run after an outage (clause 9.2 recovery). */
CREATE PROCEDURE philmart.P_List_Auction_Close
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
        UPDATE philmart.Item_Item SET State = 'ready_to_list' WHERE ID = @itemId;
        SET @outcome = 'unsold';
    END
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D012/D064. Idempotent by design: returns already_closed rather than raising, so multiple simultaneous closings and post-outage recovery converge on one outcome. EML-014 Seller Auction Result is RETIRED and must not be sent (D056).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_List_Auction_Close';
GO

/* ------------------------------------------- financial trigger firing -----
   D023. The single place proceeds and fees are created. Both Sale_Fulfilment paths
   call this one procedure (NF-06) so they cannot drift apart.               */
CREATE PROCEDURE philmart.P_Sale_Fulfilment_FireFinancialTrigger
    @fulfilmentId UNIQUEIDENTIFIER,
    @fired         BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @fired = 0;

    DECLARE @shopId UNIQUEIDENTIFIER, @saleId UNIQUEIDENTIFIER,
            @kind VARCHAR(20), @triggerAt DATETIMEOFFSET(7),
            @dispatched DATETIMEOFFSET(7), @ready DATETIMEOFFSET(7);

    SELECT @shopId = ShopID, @saleId = SaleTransactionID, @kind = MethodKind,
           @triggerAt = FinancialTriggerAt,
           @dispatched = DispatchedAt, @ready = ReadyForCollectionAt
    FROM philmart.Sale_Fulfilment WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
    WHERE ID = @fulfilmentId;

    IF @shopId IS NULL THROW 50038, 'Fulfilment not found.', 1;
    IF @triggerAt IS NOT NULL RETURN 0;          -- already fired; idempotent

    DECLARE @invoiceId UNIQUEIDENTIFIER =
        (SELECT TOP (1) InvoiceID FROM philmart.Sale_InvoiceLine WHERE SaleTransactionID = @saleId);

    /* D020: full Sale_Payment of the relevant Sale_Invoice is required. */
    IF @invoiceId IS NULL OR philmart.InvoiceIsFullyPaid(@invoiceId) = 0
        THROW 50039, 'Financial trigger refused: the relevant Sale_Invoice is not fully paid (D020). Dispatch and Ready for Collection require full Sale_Payment.', 1;

    /* D023: the Sale_Fulfilment event must have happened on the matching path. */
    IF NOT ((@kind = 'shipping'   AND @dispatched IS NOT NULL)
         OR (@kind = 'collection' AND @ready IS NOT NULL))
        THROW 50040, 'Financial trigger refused: shipping requires Dispatch, collection requires Ready for Collection (D023). Actual collection does not count.', 1;

    UPDATE philmart.Sale_Fulfilment
       SET FinancialTriggerAt = philmart.ServerNow(),
           FinancialTriggerEvent = CASE WHEN @kind = 'shipping'
                                          THEN 'dispatch' ELSE 'ready_for_collection' END
    WHERE ID = @fulfilmentId;

    DECLARE @itemId UNIQUEIDENTIFIER, @price BIGINT, @consigned BIT, @sellerId UNIQUEIDENTIFIER;
    SELECT @itemId = st.ItemID, @price = st.SalePriceMinor,
           @consigned = it.IsConsigned, @sellerId = it.SellerID
    FROM philmart.Sale_Transaction AS st
    JOIN philmart.Item_Item AS it ON it.ID = st.ItemID
    WHERE st.ID = @saleId;

    /* D025: Seller proceeds post here (consigned stock only). */
    IF @consigned = 1
    BEGIN
        DECLARE @pct DECIMAL(9,6) =
            ISNULL((SELECT DefaultCommissionPct FROM philmart.Shop_Settings WHERE ShopID = @shopId), 0);
        DECLARE @commission BIGINT = CAST(ROUND(@price * @pct / 100.0, 0) AS BIGINT);

        INSERT INTO philmart.Sell_ProceedsEntry
            (SellerID, ShopID, ItemID, SaleTransactionID, FulfilmentID,
             EntryKind, Direction, GrossAmountMinor, CommissionMinor,
             NetAmountMinor, CommissionPct)
        VALUES (@sellerId, @shopId, @itemId, @saleId, @fulfilmentId,
                'proceeds', 'credit', @price, @commission, @price - @commission, @pct);
    END

    /* D028: PHILMART transaction fee accrues on the same trigger. */
    DECLARE @feePct DECIMAL(9,6) =
        (SELECT TransactionFeePct FROM philmart.Fee_ShopConfig
         WHERE ShopID = @shopId AND EffectiveTo IS NULL);

    IF @feePct IS NOT NULL
    BEGIN
        DECLARE @today DATE = CAST(philmart.ServerNow() AS DATE);
        INSERT INTO philmart.Fee_Accrual
            (ShopID, SaleTransactionID, FulfilmentID, BaseAmountMinor,
             FeePct, FeeAmountMinor, AccrualPeriod)
        VALUES (@shopId, @saleId, @fulfilmentId, @price, @feePct,
                CAST(ROUND(@price * @feePct / 100.0, 0) AS BIGINT),
                DATEFROMPARTS(YEAR(@today), MONTH(@today), 1));
    END

    INSERT INTO philmart.Sys_AuditEvent
        (ActorID, ActorKind, ShopID, EntityTable, EntityID, Action, AfterValue)
    VALUES (philmart.CurrentActorID(), philmart.CurrentActorKind(), @shopId,
            'Sale_Fulfilment', CAST(@fulfilmentId AS VARCHAR(80)),
            'Sale_Fulfilment.financial_trigger_fired',
            N'{"path":"' + @kind + N'","decision":"D023"}');

    SET @fired = 1;
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D020/D023/D025/D028. THE single implementation of the financial trigger. Both Sale_Fulfilment paths call it, so they cannot diverge (NF-06, RK-08). It is idempotent — a second call returns fired = 0 rather than double-posting — and the filtered unique indexes on Sell_ProceedsEntry(FulfilmentID) and Fee_Accrual(FulfilmentID) make double-posting impossible even under a race.',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_Sale_Fulfilment_FireFinancialTrigger';
GO

/* ------------------------------------------------ Sale_Payment allocation ------
   D021: specific reference first; otherwise oldest outstanding first.       */
CREATE PROCEDURE philmart.P_Sale_Payment_Allocate
    @paymentId UNIQUEIDENTIFIER,
    @residual   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @shopId UNIQUEIDENTIFIER, @accountId UNIQUEIDENTIFIER,
            @amount BIGINT, @specific UNIQUEIDENTIFIER;

    SELECT @shopId = ShopID, @accountId = BuyerAccountID,
           @amount = AmountMinor, @specific = SpecificInvoiceID
    FROM philmart.Sale_Payment WHERE ID = @paymentId;

    IF @shopId IS NULL THROW 50041, 'Payment not found.', 1;

    SET @residual = @amount - ISNULL(
        (SELECT SUM(AmountMinor) FROM philmart.Sale_PaymentAllocation WHERE PaymentID = @paymentId), 0);
    IF @residual <= 0 RETURN 0;

    DECLARE @take BIGINT, @outstanding BIGINT;

    /* Specific reference wins outright (D021). */
    IF @specific IS NOT NULL
    BEGIN
        SET @outstanding = (SELECT TotalMinor - philmart.InvoicePaidMinor(ID)
                            FROM philmart.Sale_Invoice WHERE ID = @specific);
        SET @take = CASE WHEN @residual < @outstanding THEN @residual ELSE @outstanding END;
        IF @take > 0
        BEGIN
            INSERT INTO philmart.Sale_PaymentAllocation
                (PaymentID, InvoiceID, ShopID, BuyerAccountID, AmountMinor, AllocationRule)
            VALUES (@paymentId, @specific, @shopId, @accountId, @take, 'specific_reference');
            SET @residual = @residual - @take;
        END
    END

    /* Then oldest outstanding first, then next-oldest, until exhausted (D021).
       Deterministic tie-break on id so equal issue times cannot reorder.     */
    DECLARE @invId UNIQUEIDENTIFIER;
    DECLARE inv_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.ID, i.TotalMinor - philmart.InvoicePaidMinor(i.ID)
        FROM philmart.Sale_Invoice AS i
        WHERE i.BuyerAccountID = @accountId
          AND i.State = 'issued'
          AND i.TotalMinor > philmart.InvoicePaidMinor(i.ID)
        ORDER BY i.IssuedAt ASC, i.ID ASC;

    OPEN inv_cur;
    FETCH NEXT FROM inv_cur INTO @invId, @outstanding;
    WHILE @@FETCH_STATUS = 0 AND @residual > 0
    BEGIN
        SET @take = CASE WHEN @residual < @outstanding THEN @residual ELSE @outstanding END;
        INSERT INTO philmart.Sale_PaymentAllocation
            (PaymentID, InvoiceID, ShopID, BuyerAccountID, AmountMinor, AllocationRule)
        VALUES (@paymentId, @invId, @shopId, @accountId, @take, 'oldest_outstanding');
        SET @residual = @residual - @take;
        FETCH NEXT FROM inv_cur INTO @invId, @outstanding;
    END
    CLOSE inv_cur; DEALLOCATE inv_cur;

    /* D021: residual credit exists ONLY after all outstanding invoices settle. */
    IF @residual > 0
    BEGIN
        INSERT INTO philmart.Buy_AccountEntry
            (BuyerAccountID, ShopID, EntryKind, Direction, AmountMinor, PaymentID, Description)
        VALUES (@accountId, @shopId, 'credit_note', 'credit', @residual, @paymentId,
                N'Residual credit after all outstanding invoices settled');
    END
    RETURN 0;
END;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'D021/D022. Ordering: specific reference, then oldest outstanding first, then next-oldest until exhausted. Residual credit only after ALL outstanding invoices are settled. Credit is written to the Shop-scoped Buy_Buyer account and can never cross Shops (clause 9.3).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'PROCEDURE',@level1name=N'P_Sale_Payment_Allocate';
GO

/* ------------------------------------------------------- catalogue search --
   SQL Server Full-Text Search replaces the Postgres tsvector/trigram pair.
   Requires the Full-Text Search feature to be installed on the instance; on
   Azure SQL Database it is available by default.

   Guarded, with the DDL deferred through EXEC, because CREATE FULLTEXT CATALOG
   and CREATE FULLTEXT INDEX raise error 7609 on an instance without the
   feature at the point the batch is normalised - even inside an IF branch that
   is never taken. Unguarded, that error aborts everything after it, which on
   the single-file deploy takes the reference seed down with it. Catalogue
   search is then unavailable until the feature is installed and this block is
   re-run; nothing else in the schema depends on it.                         */
IF SERVERPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'philmart_ft')
        EXEC(N'CREATE FULLTEXT CATALOG philmart_ft AS DEFAULT;');

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes
                    WHERE object_id = OBJECT_ID('philmart.Item_Item'))
        EXEC(N'CREATE FULLTEXT INDEX ON philmart.Item_Item
                   (Title LANGUAGE 1033, Description LANGUAGE 1033)
               KEY INDEX PK_item ON philmart_ft
               WITH CHANGE_TRACKING AUTO;');
END
ELSE
    PRINT 'WARNING: Full-Text Search is not installed on this instance. The philmart_ft catalogue and the Item_Item full-text index were SKIPPED. Item catalogue search will not work until the feature is installed and this block is re-run.';
GO

/* ========================================================================
   PART 10 OF 10 : 010_seed.sql
   controlled reference seed
   ===================================================================== */
PRINT '>>> PHILMART part 10 of 10: 010_seed.sql';
GO

/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 10 of 10 : controlled reference seed

   GENERATED FILE - DO NOT EDIT BY HAND.
   Produced by tools/gen_seed.py from the controlled artefacts listed below.
   Re-run the generator after any controlled-pack revision.

   02_Database/README.md, "Run order": seeding belongs with project setup and
   must load the controlled catalogues DIRECTLY from their source files. Typing
   the 24 email rows by hand is how a RETIRED template gets marked current;
   typing 659 classification rows by hand is worse.

   Controlled sources, with the SHA-256 of the file this seed was built from:
     PHILMART_CURRENT_CONSTRUCTION_MASTER_PACK_v1.0_2026-09-07 (1)/PHILMART_CURRENT_CONSTRUCTION_MASTER_PACK_v1.0_2026-09-07/04_CURRENT_CONTROLS/classification/09_PHILMART_ITEM_CLASSIFICATION_MASTER_SEED_v3.11.8.csv
       c9b7dacd0ab627f1be3f4c2882341ea5ff9ae1934e6221e2140b4e2b587ec901
     PHILMART_DEVELOPER_SLIM_D076_2026-09-17/PHILMART_DEVELOPER_SLIM/04_CURRENT_EMAILS/PHILMART_CURRENT_EMAIL_CATALOGUE_2026-09-16.csv
       2c61f52a2c1dca3725114154feeefcb3acf259af9eb5d9cb67ac9dc206c3d2d2
     PHILMART_DEVELOPER_SLIM_D076_2026-09-17/PHILMART_DEVELOPER_SLIM/07_PROPOSED_CURRENT_LEGAL/LEGAL_DOCUMENT_MANIFEST.csv
       a428571452dccc5d7351d98a7b83ab9e6f600e1dbd5b4388e4ca4e89894a29f9

   RUN AS:  philmart_migrator (or db_owner). NOT philmart_app - that role is
            denied DELETE and is subject to Row Level Security, and everything
            seeded here is platform-scoped reference data.

   IDEMPOTENT: every section is a MERGE on the natural key. Re-running updates
   controlled attributes in place and inserts anything new. Nothing is ever
   deleted: a value withdrawn from a controlled master is deactivated, never
   removed, because historical Items still point at it (D055, and Agreement
   clause 8 - history is never destroyed).

   CODES: the controlled masters are keyed by NAME. The Code columns here are an
   implementation artefact derived deterministically by tools/gen_seed.py -
   accents stripped, '&' -> AMP, non-alphanumerics -> '_', upper-cased, and a
   name too long for VARCHAR(40) truncated with a 6-hex digest of the full name
   appended. '&' maps to AMP and not AND deliberately: the controlled
   Area/Country seed uses '<X> & <Y>' for a collecting group and '<X> and <Y>'
   for an issuing area beneath it, and folding both to AND merges two distinct
   nodes into one.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

/* This seed writes platform-scoped reference data. philmart_app is deliberately
   unprivileged and must never be the principal that loads it. */
IF IS_ROLEMEMBER('philmart_app') = 1
   AND IS_ROLEMEMBER('db_owner') = 0
   AND IS_ROLEMEMBER('philmart_migrator') = 0
BEGIN
    THROW 50100, 'Run 010_seed.sql as philmart_migrator or db_owner, not philmart_app.', 1;
END;
GO

/* ------------------------------------------------------------ permissions ---
   D050. Permissions are assigned DIRECTLY to users. There is no role table and
   none may be introduced - the custom role layer was removed by decision. A
   Shop Administrator receives the full set via Shop_User.IsAdministrator rather
   than through rows in Shop_UserPermission.

   These codes are the contract with the API: Philmart.Domain.Constants
   .PhilmartConstants.Permission holds exactly this set, and adding one means
   changing both. AdminOnly marks a permission that may only ever be held by a
   Shop Administrator - user administration (D049) and the Shop-Administrator-
   only fee statement (SCR-SHP-015).                                          */
MERGE philmart.Sys_Permission AS tgt
USING (VALUES
    ('shop.settings.view', N'View Shop Settings', N'Shop Settings', N'View the Shop-controlled operational settings.', 0),
    ('shop.settings.manage', N'Manage Shop Settings', N'Shop Settings', N'Change the Shop-controlled operational settings. Settings is the sole Administration menu entry (SCR-SHP-012).', 1),
    ('shop.users.view', N'View Shop Users', N'Users and Access', N'View Shop users and their assigned permissions (D049).', 1),
    ('shop.users.manage', N'Manage Shop Users', N'Users and Access', N'Invite, edit, disable and re-permission Shop users. Disabling removes access but preserves audit history (D049, D051).', 1),
    ('item.view', N'View Items', N'Items', N'View Items and Item detail.', 0),
    ('item.manage', N'Manage Items', N'Items', N'Create and edit Items, including classification and ownership/pricing.', 0),
    ('item.remove', N'Remove Items from Stock', N'Items', N'Remove from Stock, mark Missing/Damaged, Return to Seller and write off (D010, D016, D056, D065, D066).', 0),
    ('item.bulk_upload', N'Bulk Upload Items', N'Items', N'Generate, upload and import the Shop-specific bulk Item batch.', 0),
    ('listing.view', N'View Listings', N'Listings', N'View Listings in any state, including historical read-only Listings.', 0),
    ('listing.manage', N'Manage Listings', N'Listings', N'Create, schedule, edit and withdraw Fixed Price Listings.', 0),
    ('auction.manage', N'Manage Auctions', N'Auctions', N'Create and schedule Auctions and Auction Events, and cancel Auctions carrying no bids.', 0),
    ('auction.cancel_with_bids', N'Cancel Auction with Bids', N'Auctions', N'Exceptionally cancel an Auction that carries bids. Reason mandatory; bids and audit preserved (D016).', 0),
    ('invoice.view', N'View Invoices', N'Invoices', N'View Buyer Invoices and Invoice detail.', 0),
    ('invoice.manage', N'Manage Invoices', N'Invoices', N'Prepare, issue and cancel Buyer Invoices. An issued Invoice is immutable (D019).', 0),
    ('payment.record', N'Record Buyer Payments', N'Payments', N'Record a Buyer payment received directly by the Shop (Agreement clause 9.3).', 0),
    ('payment.reverse', N'Reverse Buyer Payments', N'Payments', N'Reverse or refund a recorded Buyer payment as a separate linked transaction (D022, D026).', 0),
    ('fulfilment.manage', N'Manage Fulfilment', N'Fulfilment', N'Record Dispatch, Ready for Collection and Collected. Requires full payment first (D020, D023).', 0),
    ('seller.view', N'View Sellers', N'Sellers', N'View Sellers/Consignors, consignment stock and Seller statements.', 0),
    ('seller.manage', N'Manage Sellers', N'Sellers', N'Create and edit Sellers/Consignors and their commercial terms.', 0),
    ('seller.pay', N'Record Seller Payments', N'Sellers', N'Settle outstanding Seller proceeds (D025).', 0),
    ('seller.reverse', N'Reverse Seller Payments', N'Sellers', N'Reverse a Seller payment as a separate linked entry. Reason mandatory (D026).', 0),
    ('query.view', N'View Buyer Queries', N'Buyer Queries', N'View Buyer Query cases and their message history.', 0),
    ('query.respond', N'Respond to Buyer Queries', N'Buyer Queries', N'Reply to and close Buyer Query cases (D046, D069).', 0),
    ('buyer.restrict', N'Restrict Buyers', N'Buyer Queries', N'Restrict a Buyer from new purchases or bids with this Shop. Reason mandatory (D044).', 0),
    ('fees.view', N'View PHILMART Fees', N'PHILMART Fees', N'View the read-only Shop PHILMART fee statement and supporting schedule (SCR-SHP-015, Shop Administrator only).', 1),
    ('report.view', N'View Reports', N'Reports', N'Run and view Shop reports and statements.', 0)
) AS src (Code, Name, Category, Description, AdminOnly)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.Category = src.Category,
     tgt.Description = src.Description, tgt.AdminOnly = src.AdminOnly
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, Category, Description, AdminOnly)
     VALUES (src.Code, src.Name, src.Category, src.Description, src.AdminOnly);
GO

/* -------------------------------------------------- Shop setup sections ---
   D005. THIS SECTION IS SAFETY-CRITICAL AND MUST NOT BE SKIPPED.

   TR_shop_setup_auto_activation activates a Shop when NO mandatory section is
   outstanding:

       NOT EXISTS (SELECT 1 FROM Shop_SetupSection sec
                   LEFT JOIN Shop_SetupProgress p ON ...
                    WHERE sec.Mandatory = 1 AND ISNULL(p.IsValid, 0) = 0)

   That NOT EXISTS is vacuously TRUE whenever no row has Mandatory = 1. Both
   failure modes were reproduced on SQL Server 2025 against this schema:

     - Shop_SetupSection EMPTY: FK_ssp_section rejects every Shop_SetupProgress
       row, because SectionCode must reference a section that exists. Shop
       Setup is inoperable - no progress can be recorded at all, so no Shop can
       ever activate. The trigger never fires.

     - Shop_SetupSection populated but with NO Mandatory = 1 row: the guard is
       vacuous, and the FIRST progress row flips the Shop straight to active
       EVEN WITH IsValid = 0. Verified: a Shop in setup_access_granted went to
       active on one invalid progress row.

   So this table must be seeded, and at least one row must be Mandatory, before
   any Shop exists. The verification block at the end of this file asserts
   exactly that.

   The eight sections are the controlled Shop Setup stages, evidenced as
   "Stage n of 8" in SCREEN_IMPLEMENTATION_INDEX_v1.0 (DEV-WI-027 to -032, -045
   and -046): SCR-SHP-003.1, .3, .4A, .4B, .5, .6, .7 and .8A. SCR-SHP-003.8B
   "Submitted, Awaiting PHILMART Review" is a post-submit STATE, not a section,
   and is deliberately absent - the schema comment above Shop_SetupSection says
   "nine setup surfaces" because it counts that state as one.

   All eight are Mandatory: no controlled decision makes any stage optional, and
   the safe failure mode is refusing to activate rather than activating early. */
MERGE philmart.Shop_SetupSection AS tgt
USING (VALUES
    ('SHOP_DETAILS_PEOPLE', N'Shop Details, People & Auctioneer', 1, 1),
    ('PUBLIC_PROFILE', N'Public Shop Profile', 1, 2),
    ('LOCATIONS_COLLECTION', N'Locations & Collection', 1, 3),
    ('DELIVERY_METHODS', N'Delivery Methods', 1, 4),
    ('STOCK_LOCATIONS', N'Item Stock Locations', 1, 5),
    ('OPERATIONAL_SETTINGS', N'Operational Settings', 1, 6),
    ('COMMERCIAL_PAYMENT', N'Commercial & Payment Arrangements', 1, 7),
    ('REVIEW_SIGN_SUBMIT', N'Review, Sign & Submit', 1, 8)
) AS src (Code, Name, Mandatory, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.Mandatory = src.Mandatory, tgt.SortOrder = src.SortOrder
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, Mandatory, SortOrder)
     VALUES (src.Code, src.Name, src.Mandatory, src.SortOrder);
GO

/* -------------------------------------------- Item classification masters ---
   Seeded from 09_PHILMART_ITEM_CLASSIFICATION_MASTER_SEED_v3.11.8.csv, the
   authoritative successor seed for Area/Country, Type, Subtype, Format, Stamp
   State and Theme. PHILMART-controlled and not Shop-editable (D052, BR-22-R08);
   PHILMART maintains them through SCR-ADM-007.4 Item Classification Masters.

   The controlled rule is that "inactive values remain historical but are
   unavailable for new classification", so this MERGE never deletes. Every row
   in the controlled seed carries Status = Active, and Active is re-asserted on
   re-run.

   Type - PHILMART-managed top-level list, 7 values.                          */
MERGE philmart.Sys_ClassificationType AS tgt
USING (VALUES
    ('STAMP_ISSUE', N'Stamp / Issue', 1),
    ('COVER', N'Cover', 2),
    ('POSTAL_STATIONERY', N'Postal Stationery', 3),
    ('COLLECTION', N'Collection', 4),
    ('PHILATELIC_LITERATURE', N'Philatelic Literature', 5),
    ('PHILATELIC_SUPPLIES_AMP_ACCESSORIES', N'Philatelic Supplies & Accessories', 6),
    ('OTHER_PHILATELIC_MATERIAL', N'Other Philatelic Material', 7)
) AS src (Code, Name, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, SortOrder, Active)
     VALUES (src.Code, src.Name, src.SortOrder, 1);
GO

/* Subtype - PHILMART-managed and dependent on Type, 60 values. The unique key
   is (TypeID, Code), so TypeID is resolved by joining the parent Type's derived
   code rather than hard-coding a GUID.                                       */
MERGE philmart.Sys_ClassificationSubtype AS tgt
USING (
    SELECT t.ID AS TypeID, s.Code, s.Name, s.SortOrder
    FROM (VALUES
        ('POSTAGE_GENERAL_ISSUE', N'Postage / General Issue', 'STAMP_ISSUE', 1),
        ('AIRMAIL', N'Airmail', 'STAMP_ISSUE', 2),
        ('OFFICIAL', N'Official', 'STAMP_ISSUE', 3),
        ('POSTAGE_DUE', N'Postage Due', 'STAMP_ISSUE', 4),
        ('SEMI_POSTAL_CHARITY', N'Semi-Postal / Charity', 'STAMP_ISSUE', 5),
        ('PARCEL_POST', N'Parcel Post', 'STAMP_ISSUE', 6),
        ('NEWSPAPER', N'Newspaper', 'STAMP_ISSUE', 7),
        ('SPECIAL_DELIVERY_EXPRESS', N'Special Delivery / Express', 'STAMP_ISSUE', 8),
        ('MILITARY', N'Military', 'STAMP_ISSUE', 9),
        ('OCCUPATION', N'Occupation', 'STAMP_ISSUE', 10),
        ('OFFICES_ABROAD', N'Offices Abroad', 'STAMP_ISSUE', 11),
        ('LOCAL_CARRIER', N'Local / Carrier', 'STAMP_ISSUE', 12),
        ('REVENUE_FISCAL', N'Revenue / Fiscal', 'STAMP_ISSUE', 13),
        ('CINDERELLA_NON_POSTAL', N'Cinderella / Non-Postal', 'STAMP_ISSUE', 14),
        ('OTHER_STAMP_ISSUE', N'Other Stamp / Issue', 'STAMP_ISSUE', 15),
        ('FIRST_DAY_COVER', N'First Day Cover', 'COVER', 16),
        ('COMMEMORATIVE_COVER', N'Commemorative Cover', 'COVER', 17),
        ('FLIGHT_COVER', N'Flight Cover', 'COVER', 18),
        ('ANTARCTIC_COVER', N'Antarctic Cover', 'COVER', 19),
        ('POSTAL_HISTORY_COVER', N'Postal History Cover', 'COVER', 20),
        ('REGISTERED_COVER', N'Registered Cover', 'COVER', 21),
        ('CENSORED_COVER', N'Censored Cover', 'COVER', 22),
        ('MILITARY_COVER', N'Military Cover', 'COVER', 23),
        ('EVENT_EXHIBITION_COVER', N'Event / Exhibition Cover', 'COVER', 24),
        ('OTHER_COVER', N'Other Cover', 'COVER', 25),
        ('POSTAL_CARD', N'Postal Card', 'POSTAL_STATIONERY', 26),
        ('POSTAL_ENVELOPE', N'Postal Envelope', 'POSTAL_STATIONERY', 27),
        ('LETTER_CARD', N'Letter Card', 'POSTAL_STATIONERY', 28),
        ('AEROGRAMME', N'Aerogramme', 'POSTAL_STATIONERY', 29),
        ('WRAPPER', N'Wrapper', 'POSTAL_STATIONERY', 30),
        ('REGISTERED_ENVELOPE', N'Registered Envelope', 'POSTAL_STATIONERY', 31),
        ('REPLY_POSTAL_CARD', N'Reply Postal Card', 'POSTAL_STATIONERY', 32),
        ('OTHER_POSTAL_STATIONERY', N'Other Postal Stationery', 'POSTAL_STATIONERY', 33),
        ('STAMP_COLLECTION', N'Stamp Collection', 'COLLECTION', 34),
        ('COVER_COLLECTION', N'Cover Collection', 'COLLECTION', 35),
        ('OTHER_COLLECTION', N'Other Collection', 'COLLECTION', 36),
        ('CATALOGUE', N'Catalogue', 'PHILATELIC_LITERATURE', 37),
        ('HANDBOOK_REFERENCE_BOOK', N'Handbook / Reference Book', 'PHILATELIC_LITERATURE', 38),
        ('SPECIALIST_STUDY_MONOGRAPH', N'Specialist Study / Monograph', 'PHILATELIC_LITERATURE', 39),
        ('JOURNAL_MAGAZINE', N'Journal / Magazine', 'PHILATELIC_LITERATURE', 40),
        ('AUCTION_CATALOGUE', N'Auction Catalogue', 'PHILATELIC_LITERATURE', 41),
        ('EXHIBITION_SOCIETY_PUBLICATION', N'Exhibition / Society Publication', 'PHILATELIC_LITERATURE', 42),
        ('POSTAL_HISTORY_REFERENCE', N'Postal History Reference', 'PHILATELIC_LITERATURE', 43),
        ('OTHER_PHILATELIC_LITERATURE', N'Other Philatelic Literature', 'PHILATELIC_LITERATURE', 44),
        ('STOCKBOOK', N'Stockbook', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 45),
        ('STAMP_ALBUM', N'Stamp Album', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 46),
        ('ALBUM_PAGES', N'Album Pages', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 47),
        ('GLASSINE_ENVELOPES', N'Glassine Envelopes', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 48),
        ('STOCK_CARDS', N'Stock Cards', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 49),
        ('APPROVAL_CARDS', N'Approval Cards', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 50),
        ('STAMP_MOUNTS', N'Stamp Mounts', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 51),
        ('STAMP_HINGES', N'Stamp Hinges', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 52),
        ('PROTECTIVE_SLEEVES', N'Protective Sleeves', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 53),
        ('STAMP_TONGS_TWEEZERS', N'Stamp Tongs / Tweezers', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 54),
        ('MAGNIFIER_LOUPE', N'Magnifier / Loupe', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 55),
        ('PERFORATION_GAUGE', N'Perforation Gauge', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 56),
        ('WATERMARK_DETECTOR', N'Watermark Detector', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 57),
        ('UV_LAMP', N'UV Lamp', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 58),
        ('COLOUR_GUIDE', N'Colour Guide', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 59),
        ('OTHER_PHILATELIC_SUPPLIES_AMP_ACC_D723D7', N'Other Philatelic Supplies & Accessories', 'PHILATELIC_SUPPLIES_AMP_ACCESSORIES', 60)
    ) AS s (Code, Name, TypeCode, SortOrder)
    JOIN philmart.Sys_ClassificationType AS t ON t.Code = s.TypeCode
) AS src
   ON tgt.TypeID = src.TypeID AND tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (TypeID, Code, Name, SortOrder, Active)
     VALUES (src.TypeID, src.Code, src.Name, src.SortOrder, 1);
GO

/* Theme - PHILMART-managed FLAT list. D-326 supplies the approved initial
   32-value seed. Later additions require controlled extension and must not
   repurpose or renumber existing values.                                     */
MERGE philmart.Sys_ClassificationTheme AS tgt
USING (VALUES
    ('AGRICULTURE', N'Agriculture', 1),
    ('ANIMALS_AMP_FAUNA', N'Animals & Fauna', 2),
    ('ARCHITECTURE_AMP_BUILDINGS', N'Architecture & Buildings', 3),
    ('ART', N'Art', 4),
    ('AWARDS_AMP_MEDALS', N'Awards & Medals', 5),
    ('CHILDREN_AMP_YOUTH', N'Children & Youth', 6),
    ('CULTURE_AMP_TRADITIONS', N'Culture & Traditions', 7),
    ('ENTERTAINMENT_AMP_POPULAR_CULTURE', N'Entertainment & Popular Culture', 8),
    ('ENVIRONMENT_AMP_NATURE', N'Environment & Nature', 9),
    ('FAMOUS_PEOPLE', N'Famous People', 10),
    ('FLAGS_AMP_COATS_OF_ARMS', N'Flags & Coats of Arms', 11),
    ('FLORA_AMP_PLANTS', N'Flora & Plants', 12),
    ('FOOD_AMP_DRINK', N'Food & Drink', 13),
    ('GAMES_AMP_HOBBIES', N'Games & Hobbies', 14),
    ('GEOGRAPHY_AMP_PLACES', N'Geography & Places', 15),
    ('HEALTH_AMP_MEDICINE', N'Health & Medicine', 16),
    ('HISTORY', N'History', 17),
    ('HOLIDAYS_AMP_CELEBRATIONS', N'Holidays & Celebrations', 18),
    ('INDUSTRY_AMP_COMMERCE', N'Industry & Commerce', 19),
    ('MILITARY_AMP_ARMED_FORCES', N'Military & Armed Forces', 20),
    ('MUSIC', N'Music', 21),
    ('MYTHOLOGY_AMP_FOLKLORE', N'Mythology & Folklore', 22),
    ('OLYMPIC_GAMES', N'Olympic Games', 23),
    ('ORGANIZATIONS_AMP_INSTITUTIONS', N'Organizations & Institutions', 24),
    ('PHILATELY_AMP_POSTAL', N'Philately & Postal', 25),
    ('RELIGION', N'Religion', 26),
    ('ROYALTY_AMP_MONARCHY', N'Royalty & Monarchy', 27),
    ('SCIENCE_AMP_TECHNOLOGY', N'Science & Technology', 28),
    ('SCOUTING', N'Scouting', 29),
    ('SPACE', N'Space', 30),
    ('SPORTS', N'Sports', 31),
    ('TRANSPORT', N'Transport', 32)
) AS src (Code, Name, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, SortOrder, Active)
     VALUES (src.Code, src.Name, src.SortOrder, 1);
GO

/* Stamp State - applies ONLY where Type = Stamp / Issue. The schema has no
   column tying these to Type, so that restriction has to be enforced by the
   application; see the applicability note under Format.                      */
MERGE philmart.Sys_ClassificationStampState AS tgt
USING (VALUES
    ('MINT_NEVER_HINGED_MNH', N'Mint Never Hinged (MNH)', 1),
    ('MINT_HINGED_MH', N'Mint Hinged (MH)', 2),
    ('UNUSED_NO_GUM', N'Unused / No Gum', 3),
    ('USED', N'Used', 4),
    ('CANCELLED_TO_ORDER_CTO', N'Cancelled to Order (CTO)', 5),
    ('MIXED', N'Mixed', 6),
    ('NOT_CLASSIFIED', N'Not Classified', 7)
) AS src (Code, Name, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, SortOrder, Active)
     VALUES (src.Code, src.Name, src.SortOrder, 1);
GO

/* Format - PHILMART-managed and FILTERED BY APPLICABILITY TO TYPE. The
   controlled seed supplies 37 "Format applicability rows" over 31 distinct
   names: 'Other' appears once per Type, and 'Sheet' and 'Single Item' each
   appear under two Types.

   KNOWN SCHEMA GAP - philmart.Sys_ClassificationFormat has no TypeID column and
   a globally UNIQUE Code, so it cannot express the applicability the controlled
   master defines. The 37 rows are seeded with type-qualified codes
   (STAMP__OTHER, COLL__OTHER, ...) to preserve every distinct row and keep the
   Type readable, but THE FILTER ITSELF IS NOT IN THE DATABASE and no constraint
   can enforce it: nothing stops an Item with Type = Cover being given
   FormatID = STAMP__BOOKLET_PANE. Until a migration adds
   Sys_ClassificationFormat.TypeID and a matching composite check on Item_Item,
   the application MUST filter the Format picker by Type and validate the pair
   server-side. The same gap applies to Stamp State, which the controlled master
   restricts to Type = Stamp / Issue.                                         */
MERGE philmart.Sys_ClassificationFormat AS tgt
USING (VALUES
    ('STAMP__SINGLE', N'Single', 1),
    ('STAMP__PAIR', N'Pair', 2),
    ('STAMP__STRIP', N'Strip', 3),
    ('STAMP__BLOCK', N'Block', 4),
    ('STAMP__SHEET', N'Sheet', 5),
    ('STAMP__PART_SHEET', N'Part Sheet', 6),
    ('STAMP__MINIATURE_SHEET', N'Miniature Sheet', 7),
    ('STAMP__SOUVENIR_SHEET', N'Souvenir Sheet', 8),
    ('STAMP__BOOKLET', N'Booklet', 9),
    ('STAMP__BOOKLET_PANE', N'Booklet Pane', 10),
    ('STAMP__COIL_ROLL', N'Coil / Roll', 11),
    ('STAMP__MULTIPLE_GROUP', N'Multiple / Group', 12),
    ('STAMP__OTHER', N'Other', 13),
    ('COVER__COVER_S', N'Cover(s)', 14),
    ('PSTAT__SINGLE_ITEM', N'Single Item', 15),
    ('PSTAT__MULTIPLE_ITEMS', N'Multiple Items', 16),
    ('COLL__ALBUM_S', N'Album(s)', 17),
    ('COLL__STOCKBOOK_S', N'Stockbook(s)', 18),
    ('COLL__LOOSE_PAGES', N'Loose Pages', 19),
    ('COLL__BINDER_S', N'Binder(s)', 20),
    ('COLL__BOX_ES_CARTON_S', N'Box(es) / Carton(s)', 21),
    ('COLL__PACKET_S', N'Packet(s)', 22),
    ('COLL__OTHER', N'Other', 23),
    ('LIT__BOOK_S', N'Book(s)', 24),
    ('LIT__MAGAZINE_JOURNAL', N'Magazine / Journal', 25),
    ('LIT__LOOSE_LEAF', N'Loose-leaf', 26),
    ('LIT__PAMPHLET_BOOKLET', N'Pamphlet / Booklet', 27),
    ('LIT__OTHER', N'Other', 28),
    ('SUPP__SINGLE_ITEM', N'Single Item', 29),
    ('SUPP__PACK', N'Pack', 30),
    ('SUPP__SET', N'Set', 31),
    ('SUPP__BOX_ES', N'Box(es)', 32),
    ('SUPP__BUNDLE', N'Bundle', 33),
    ('SUPP__ROLL', N'Roll', 34),
    ('SUPP__SHEET', N'Sheet', 35),
    ('SUPP__OTHER', N'Other', 36),
    ('OTHERMAT__OTHER', N'Other', 37)
) AS src (Code, Name, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, SortOrder, Active)
     VALUES (src.Code, src.Name, src.SortOrder, 1);
GO

/* Area/Country - hierarchical, 516 nodes, each with at most one parent. Rows
   are inserted flat and the hierarchy wired afterwards by code, so the MERGE
   does not depend on parents preceding children in the source order.

   KNOWN SCHEMA GAP - the controlled master carries 359 deterministic aliases
   over 283 nodes ('RSA' -> South Africa, 'ZAR' -> Transvaal, ...) and requires
   that each alias resolve to exactly one canonical node. There is no alias
   table in this schema, so the aliases are NOT loaded and alias search cannot
   work until one is added. Nothing is lost - they remain in the controlled CSV
   - but a migration must add the table before catalogue search can meet the
   controlled rule.                                                           */
MERGE philmart.Sys_ClassificationAreaCountry AS tgt
USING (VALUES
    ('AFRICA', N'Africa', 1),
    ('EUROPE', N'Europe', 2),
    ('ASIA_AMP_MIDDLE_EAST', N'Asia & Middle East', 3),
    ('AMERICAS', N'Americas', 4),
    ('OCEANIA_AMP_PACIFIC', N'Oceania & Pacific', 5),
    ('ANTARCTICA', N'Antarctica', 6),
    ('INTERNATIONAL_POSTAL_ADMINISTRATIONS', N'International Postal Administrations', 7),
    ('SOUTHERN_AFRICA', N'Southern Africa', 8),
    ('EAST_AFRICA', N'East Africa', 9),
    ('CENTRAL_AFRICA', N'Central Africa', 10),
    ('WEST_AFRICA', N'West Africa', 11),
    ('NORTH_AFRICA', N'North Africa', 12),
    ('INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS', N'Indian Ocean & Atlantic Islands', 13),
    ('SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614', N'South Africa — Pre-Union States & Territories', 14),
    ('HOMELANDS', N'Homelands', 15),
    ('RHODESIA_AMP_ZIMBABWE', N'Rhodesia & Zimbabwe', 16),
    ('BECHUANALAND_AMP_BOTSWANA', N'Bechuanaland & Botswana', 17),
    ('BASUTOLAND_AMP_LESOTHO', N'Basutoland & Lesotho', 18),
    ('SWAZILAND_AMP_ESWATINI', N'Swaziland & Eswatini', 19),
    ('SOUTH_WEST_AFRICA_AMP_NAMIBIA', N'South West Africa & Namibia', 20),
    ('SOUTH_AFRICA', N'South Africa', 21),
    ('UNION_OF_SOUTH_AFRICA', N'Union of South Africa', 22),
    ('NORTHERN_RHODESIA', N'Northern Rhodesia', 23),
    ('ZAMBIA', N'Zambia', 24),
    ('RHODESIA_AND_NYASALAND', N'Rhodesia and Nyasaland', 25),
    ('BRITISH_CENTRAL_AFRICA', N'British Central Africa', 26),
    ('NYASALAND', N'Nyasaland', 27),
    ('MALAWI', N'Malawi', 28),
    ('MOZAMBIQUE', N'Mozambique', 29),
    ('MOZAMBIQUE_COMPANY', N'Mozambique Company', 30),
    ('NYASSA_COMPANY', N'Nyassa Company', 31),
    ('ZAMBEZIA', N'Zambezia', 32),
    ('ANGOLA', N'Angola', 33),
    ('CAPE_OF_GOOD_HOPE', N'Cape of Good Hope', 34),
    ('NATAL', N'Natal', 35),
    ('ORANGE_FREE_STATE', N'Orange Free State', 36),
    ('ORANGE_RIVER_COLONY', N'Orange River Colony', 37),
    ('TRANSVAAL', N'Transvaal', 38),
    ('GRIQUALAND_WEST', N'Griqualand West', 39),
    ('ZULULAND', N'Zululand', 40),
    ('NEW_REPUBLIC', N'New Republic', 41),
    ('STELLALAND', N'Stellaland', 42),
    ('BOPHUTHATSWANA', N'Bophuthatswana', 43),
    ('CISKEI', N'Ciskei', 44),
    ('TRANSKEI', N'Transkei', 45),
    ('VENDA', N'Venda', 46),
    ('BRITISH_SOUTH_AFRICA_COMPANY', N'British South Africa Company', 47),
    ('SOUTHERN_RHODESIA', N'Southern Rhodesia', 48),
    ('RHODESIA', N'Rhodesia', 49),
    ('ZIMBABWE', N'Zimbabwe', 50),
    ('BRITISH_BECHUANALAND', N'British Bechuanaland', 51),
    ('BECHUANALAND_PROTECTORATE', N'Bechuanaland Protectorate', 52),
    ('BOTSWANA', N'Botswana', 53),
    ('BASUTOLAND', N'Basutoland', 54),
    ('LESOTHO', N'Lesotho', 55),
    ('SWAZILAND', N'Swaziland', 56),
    ('ESWATINI', N'Eswatini', 57),
    ('GERMAN_SOUTH_WEST_AFRICA', N'German South West Africa', 58),
    ('SOUTH_WEST_AFRICA', N'South West Africa', 59),
    ('NAMIBIA', N'Namibia', 60),
    ('KENYA_UGANDA_AMP_TANGANYIKA', N'Kenya, Uganda & Tanganyika', 61),
    ('RWANDA_AMP_BURUNDI', N'Rwanda & Burundi', 62),
    ('SOMALIA_AMP_SOMALILAND', N'Somalia & Somaliland', 63),
    ('TANZANIA', N'Tanzania', 64),
    ('ZANZIBAR', N'Zanzibar', 65),
    ('ETHIOPIA', N'Ethiopia', 66),
    ('ERITREA', N'Eritrea', 67),
    ('DJIBOUTI', N'Djibouti', 68),
    ('FRENCH_SOMALI_COAST', N'French Somali Coast', 69),
    ('AFARS_AND_ISSAS', N'Afars and Issas', 70),
    ('GERMAN_EAST_AFRICA', N'German East Africa', 71),
    ('ITALIAN_EAST_AFRICA', N'Italian East Africa', 72),
    ('KENYA', N'Kenya', 73),
    ('UGANDA', N'Uganda', 74),
    ('TANGANYIKA', N'Tanganyika', 75),
    ('BRITISH_EAST_AFRICA', N'British East Africa', 76),
    ('EAST_AFRICA_AMP_UGANDA_PROTECTORATES', N'East Africa & Uganda Protectorates', 77),
    ('RUANDA_URUNDI', N'Ruanda-Urundi', 78),
    ('RWANDA', N'Rwanda', 79),
    ('BURUNDI', N'Burundi', 80),
    ('SOMALIA', N'Somalia', 81),
    ('SOMALILAND_PROTECTORATE', N'Somaliland Protectorate', 82),
    ('ITALIAN_SOMALILAND', N'Italian Somaliland', 83),
    ('CONGO_AMP_ZAIRE', N'Congo & Zaire', 84),
    ('REPUBLIC_OF_THE_CONGO', N'Republic of the Congo', 85),
    ('FRENCH_CONGO', N'French Congo', 86),
    ('CENTRAL_AFRICAN_REPUBLIC', N'Central African Republic', 87),
    ('CENTRAL_AFRICAN_EMPIRE', N'Central African Empire', 88),
    ('CHAD', N'Chad', 89),
    ('GABON', N'Gabon', 90),
    ('CAMEROON', N'Cameroon', 91),
    ('FRENCH_CAMEROON', N'French Cameroon', 92),
    ('GERMAN_CAMEROON', N'German Cameroon', 93),
    ('SPANISH_GUINEA', N'Spanish Guinea', 94),
    ('EQUATORIAL_GUINEA', N'Equatorial Guinea', 95),
    ('FRENCH_EQUATORIAL_AFRICA', N'French Equatorial Africa', 96),
    ('BELGIAN_CONGO', N'Belgian Congo', 97),
    ('CONGO_LEOPOLDVILLE', N'Congo (Leopoldville)', 98),
    ('ZAIRE', N'Zaire', 99),
    ('DEMOCRATIC_REPUBLIC_OF_THE_CONGO', N'Democratic Republic of the Congo', 100),
    ('KATANGA', N'Katanga', 101),
    ('SOUTH_KASAI', N'South Kasai', 102),
    ('GOLD_COAST_AMP_GHANA', N'Gold Coast & Ghana', 103),
    ('DAHOMEY_AMP_BENIN', N'Dahomey & Benin', 104),
    ('UPPER_VOLTA_AMP_BURKINA_FASO', N'Upper Volta & Burkina Faso', 105),
    ('FRENCH_GUINEA_AMP_GUINEA', N'French Guinea & Guinea', 106),
    ('PORTUGUESE_GUINEA_AMP_GUINEA_BISSAU', N'Portuguese Guinea & Guinea-Bissau', 107),
    ('TOGO_HISTORICAL_AMP_CURRENT', N'Togo — Historical & Current', 108),
    ('NIGERIA_HISTORICAL_AMP_CURRENT', N'Nigeria — Historical & Current', 109),
    ('IVORY_COAST', N'Ivory Coast', 110),
    ('SENEGAL', N'Senegal', 111),
    ('MALI', N'Mali', 112),
    ('MAURITANIA', N'Mauritania', 113),
    ('NIGER', N'Niger', 114),
    ('LIBERIA', N'Liberia', 115),
    ('SIERRA_LEONE', N'Sierra Leone', 116),
    ('GAMBIA', N'Gambia', 117),
    ('CAPE_VERDE', N'Cape Verde', 118),
    ('FRENCH_WEST_AFRICA', N'French West Africa', 119),
    ('GOLD_COAST', N'Gold Coast', 120),
    ('GHANA', N'Ghana', 121),
    ('DAHOMEY', N'Dahomey', 122),
    ('BENIN', N'Benin', 123),
    ('UPPER_VOLTA', N'Upper Volta', 124),
    ('BURKINA_FASO', N'Burkina Faso', 125),
    ('FRENCH_GUINEA', N'French Guinea', 126),
    ('GUINEA', N'Guinea', 127),
    ('PORTUGUESE_GUINEA', N'Portuguese Guinea', 128),
    ('GUINEA_BISSAU', N'Guinea-Bissau', 129),
    ('GERMAN_TOGO', N'German Togo', 130),
    ('TOGO', N'Togo', 131),
    ('LAGOS', N'Lagos', 132),
    ('NORTHERN_NIGERIA', N'Northern Nigeria', 133),
    ('SOUTHERN_NIGERIA', N'Southern Nigeria', 134),
    ('NIGERIA', N'Nigeria', 135),
    ('MOROCCO_AMP_PROTECTORATES', N'Morocco & Protectorates', 136),
    ('SUDAN_AMP_SOUTH_SUDAN', N'Sudan & South Sudan', 137),
    ('ALGERIA', N'Algeria', 138),
    ('TUNISIA', N'Tunisia', 139),
    ('LIBYA', N'Libya', 140),
    ('EGYPT', N'Egypt', 141),
    ('WESTERN_SAHARA', N'Western Sahara', 142),
    ('MOROCCO', N'Morocco', 143),
    ('FRENCH_MOROCCO', N'French Morocco', 144),
    ('SPANISH_MOROCCO', N'Spanish Morocco', 145),
    ('SUDAN', N'Sudan', 146),
    ('SOUTH_SUDAN', N'South Sudan', 147),
    ('MAURITIUS', N'Mauritius', 148),
    ('SEYCHELLES', N'Seychelles', 149),
    ('MADAGASCAR', N'Madagascar', 150),
    ('COMOROS', N'Comoros', 151),
    ('REUNION', N'Réunion', 152),
    ('SAINT_HELENA', N'Saint Helena', 153),
    ('ASCENSION', N'Ascension', 154),
    ('TRISTAN_DA_CUNHA', N'Tristan da Cunha', 155),
    ('MAYOTTE', N'Mayotte', 156),
    ('SAO_TOME_AND_PRINCIPE', N'São Tomé and Príncipe', 157),
    ('BRITISH_ISLES_AMP_CROWN_DEPENDENCIES', N'British Isles & Crown Dependencies', 158),
    ('SCANDINAVIA_AMP_NORDIC', N'Scandinavia & Nordic', 159),
    ('BENELUX', N'Benelux', 160),
    ('GERMANY_HISTORICAL_AMP_CURRENT', N'Germany — Historical & Current', 161),
    ('ITALY_HISTORICAL_AMP_CURRENT', N'Italy — Historical & Current', 162),
    ('CZECHOSLOVAKIA_AMP_SUCCESSOR_STATES', N'Czechoslovakia & Successor States', 163),
    ('YUGOSLAVIA_AMP_SUCCESSOR_STATES', N'Yugoslavia & Successor States', 164),
    ('RUSSIA_AMP_USSR', N'Russia & USSR', 165),
    ('IBERIA', N'Iberia', 166),
    ('CENTRAL_EUROPE', N'Central Europe', 167),
    ('BALKANS_AMP_SOUTHEAST_EUROPE', N'Balkans & Southeast Europe', 168),
    ('WESTERN_EUROPE', N'Western Europe', 169),
    ('GREAT_BRITAIN', N'Great Britain', 170),
    ('IRELAND', N'Ireland', 171),
    ('ISLE_OF_MAN', N'Isle of Man', 172),
    ('JERSEY', N'Jersey', 173),
    ('GUERNSEY', N'Guernsey', 174),
    ('ALDERNEY', N'Alderney', 175),
    ('DENMARK', N'Denmark', 176),
    ('FAROE_ISLANDS', N'Faroe Islands', 177),
    ('GREENLAND', N'Greenland', 178),
    ('ICELAND', N'Iceland', 179),
    ('NORWAY', N'Norway', 180),
    ('SWEDEN', N'Sweden', 181),
    ('FINLAND', N'Finland', 182),
    ('ALAND', N'Åland', 183),
    ('BELGIUM', N'Belgium', 184),
    ('NETHERLANDS', N'Netherlands', 185),
    ('LUXEMBOURG', N'Luxembourg', 186),
    ('GERMAN_STATES', N'German States', 187),
    ('BADEN', N'Baden', 188),
    ('BAVARIA', N'Bavaria', 189),
    ('HANOVER', N'Hanover', 190),
    ('PRUSSIA', N'Prussia', 191),
    ('SAXONY', N'Saxony', 192),
    ('WURTTEMBERG', N'Württemberg', 193),
    ('BERGEDORF', N'Bergedorf', 194),
    ('BRUNSWICK', N'Brunswick', 195),
    ('BREMEN', N'Bremen', 196),
    ('HAMBURG', N'Hamburg', 197),
    ('HELIGOLAND', N'Heligoland', 198),
    ('LUBECK', N'Lübeck', 199),
    ('MECKLENBURG_SCHWERIN', N'Mecklenburg-Schwerin', 200),
    ('MECKLENBURG_STRELITZ', N'Mecklenburg-Strelitz', 201),
    ('OLDENBURG', N'Oldenburg', 202),
    ('THURN_AND_TAXIS', N'Thurn and Taxis', 203),
    ('NORTH_GERMAN_CONFEDERATION', N'North German Confederation', 204),
    ('GERMAN_EMPIRE', N'German Empire', 205),
    ('WEIMAR_GERMANY', N'Weimar Germany', 206),
    ('GERMANY_THIRD_REICH', N'Germany — Third Reich', 207),
    ('GERMANY_ALLIED_OCCUPATION', N'Germany — Allied Occupation', 208),
    ('WEST_GERMANY', N'West Germany', 209),
    ('EAST_GERMANY', N'East Germany', 210),
    ('WEST_BERLIN', N'West Berlin', 211),
    ('GERMANY', N'Germany', 212),
    ('DANZIG', N'Danzig', 213),
    ('SAAR', N'Saar', 214),
    ('MEMEL', N'Memel', 215),
    ('UPPER_SILESIA', N'Upper Silesia', 216),
    ('SCHLESWIG', N'Schleswig', 217),
    ('ALLENSTEIN', N'Allenstein', 218),
    ('MARIENWERDER', N'Marienwerder', 219),
    ('ITALIAN_STATES', N'Italian States', 220),
    ('PAPAL_STATES', N'Papal States', 221),
    ('SARDINIA', N'Sardinia', 222),
    ('TUSCANY', N'Tuscany', 223),
    ('MODENA', N'Modena', 224),
    ('PARMA', N'Parma', 225),
    ('TWO_SICILIES', N'Two Sicilies', 226),
    ('LOMBARDY_AMP_VENETIA', N'Lombardy & Venetia', 227),
    ('FIUME', N'Fiume', 228),
    ('TRIESTE', N'Trieste', 229),
    ('VENEZIA_GIULIA_AMP_ISTRIA', N'Venezia Giulia & Istria', 230),
    ('ITALY', N'Italy', 231),
    ('SAN_MARINO', N'San Marino', 232),
    ('VATICAN_CITY', N'Vatican City', 233),
    ('CZECHOSLOVAKIA', N'Czechoslovakia', 234),
    ('CZECH_REPUBLIC', N'Czech Republic', 235),
    ('SLOVAKIA', N'Slovakia', 236),
    ('YUGOSLAVIA', N'Yugoslavia', 237),
    ('SLOVENIA', N'Slovenia', 238),
    ('CROATIA', N'Croatia', 239),
    ('BOSNIA_AND_HERZEGOVINA', N'Bosnia and Herzegovina', 240),
    ('SERBIA', N'Serbia', 241),
    ('MONTENEGRO', N'Montenegro', 242),
    ('NORTH_MACEDONIA', N'North Macedonia', 243),
    ('KOSOVO', N'Kosovo', 244),
    ('RUSSIAN_EMPIRE', N'Russian Empire', 245),
    ('SOVIET_UNION', N'Soviet Union', 246),
    ('RUSSIA', N'Russia', 247),
    ('BELARUS', N'Belarus', 248),
    ('UKRAINE', N'Ukraine', 249),
    ('MOLDOVA', N'Moldova', 250),
    ('ESTONIA', N'Estonia', 251),
    ('LATVIA', N'Latvia', 252),
    ('LITHUANIA', N'Lithuania', 253),
    ('SPAIN', N'Spain', 254),
    ('PORTUGAL', N'Portugal', 255),
    ('ANDORRA', N'Andorra', 256),
    ('GIBRALTAR', N'Gibraltar', 257),
    ('AUSTRIA', N'Austria', 258),
    ('HUNGARY', N'Hungary', 259),
    ('LIECHTENSTEIN', N'Liechtenstein', 260),
    ('SWITZERLAND', N'Switzerland', 261),
    ('ALBANIA', N'Albania', 262),
    ('BULGARIA', N'Bulgaria', 263),
    ('GREECE', N'Greece', 264),
    ('CRETE', N'Crete', 265),
    ('CYPRUS', N'Cyprus', 266),
    ('ROMANIA', N'Romania', 267),
    ('FRANCE', N'France', 268),
    ('MONACO', N'Monaco', 269),
    ('MALTA', N'Malta', 270),
    ('INDIAN_SUBCONTINENT', N'Indian Subcontinent', 271),
    ('SOUTHEAST_ASIA', N'Southeast Asia', 272),
    ('MALAYA_AMP_STRAITS_SETTLEMENTS', N'Malaya & Straits Settlements', 273),
    ('CHINA_HISTORICAL_AMP_CURRENT', N'China — Historical & Current', 274),
    ('EAST_ASIA', N'East Asia', 275),
    ('KOREA_HISTORICAL_AMP_CURRENT', N'Korea — Historical & Current', 276),
    ('CENTRAL_ASIA', N'Central Asia', 277),
    ('CAUCASUS', N'Caucasus', 278),
    ('PALESTINE_AMP_JORDAN', N'Palestine & Jordan', 279),
    ('MIDDLE_EAST', N'Middle East', 280),
    ('ARABIAN_PENINSULA_AMP_GULF', N'Arabian Peninsula & Gulf', 281),
    ('TURKEY_HISTORICAL_AMP_CURRENT', N'Turkey — Historical & Current', 282),
    ('INDIA', N'India', 283),
    ('BRITISH_INDIA', N'British India', 284),
    ('INDIAN_STATES', N'Indian States', 285),
    ('PAKISTAN', N'Pakistan', 286),
    ('BANGLADESH', N'Bangladesh', 287),
    ('NEPAL', N'Nepal', 288),
    ('BHUTAN', N'Bhutan', 289),
    ('CEYLON', N'Ceylon', 290),
    ('SRI_LANKA', N'Sri Lanka', 291),
    ('MALDIVES', N'Maldives', 292),
    ('PORTUGUESE_INDIA', N'Portuguese India', 293),
    ('FRENCH_INDIA', N'French India', 294),
    ('CONVENTION_STATES', N'Convention States', 295),
    ('FEUDATORY_STATES', N'Feudatory States', 296),
    ('BURMA', N'Burma', 297),
    ('MYANMAR', N'Myanmar', 298),
    ('SIAM', N'Siam', 299),
    ('THAILAND', N'Thailand', 300),
    ('CAMBODIA', N'Cambodia', 301),
    ('KAMPUCHEA', N'Kampuchea', 302),
    ('LAOS', N'Laos', 303),
    ('FRENCH_INDOCHINA', N'French Indochina', 304),
    ('NORTH_VIETNAM', N'North Vietnam', 305),
    ('SOUTH_VIETNAM', N'South Vietnam', 306),
    ('VIETNAM', N'Vietnam', 307),
    ('DUTCH_EAST_INDIES', N'Dutch East Indies', 308),
    ('INDONESIA', N'Indonesia', 309),
    ('PORTUGUESE_TIMOR', N'Portuguese Timor', 310),
    ('TIMOR_LESTE', N'Timor-Leste', 311),
    ('PHILIPPINES', N'Philippines', 312),
    ('STRAITS_SETTLEMENTS', N'Straits Settlements', 313),
    ('MALAYA', N'Malaya', 314),
    ('MALAYSIA', N'Malaysia', 315),
    ('SINGAPORE', N'Singapore', 316),
    ('NORTH_BORNEO', N'North Borneo', 317),
    ('SARAWAK', N'Sarawak', 318),
    ('LABUAN', N'Labuan', 319),
    ('BRUNEI', N'Brunei', 320),
    ('CHINESE_EMPIRE', N'Chinese Empire', 321),
    ('REPUBLIC_OF_CHINA', N'Republic of China', 322),
    ('PEOPLE_S_REPUBLIC_OF_CHINA', N'People''s Republic of China', 323),
    ('TAIWAN', N'Taiwan', 324),
    ('HONG_KONG', N'Hong Kong', 325),
    ('MACAU', N'Macau', 326),
    ('MANCHUKUO', N'Manchukuo', 327),
    ('MONGOLIA', N'Mongolia', 328),
    ('JAPAN', N'Japan', 329),
    ('KOREA', N'Korea', 330),
    ('NORTH_KOREA', N'North Korea', 331),
    ('SOUTH_KOREA', N'South Korea', 332),
    ('KAZAKHSTAN', N'Kazakhstan', 333),
    ('KYRGYZSTAN', N'Kyrgyzstan', 334),
    ('TAJIKISTAN', N'Tajikistan', 335),
    ('TURKMENISTAN', N'Turkmenistan', 336),
    ('UZBEKISTAN', N'Uzbekistan', 337),
    ('TUVA', N'Tuva', 338),
    ('ARMENIA', N'Armenia', 339),
    ('AZERBAIJAN', N'Azerbaijan', 340),
    ('GEORGIA', N'Georgia', 341),
    ('PALESTINE_BRITISH_MANDATE', N'Palestine — British Mandate', 342),
    ('PALESTINE', N'Palestine', 343),
    ('TRANSJORDAN', N'Transjordan', 344),
    ('JORDAN', N'Jordan', 345),
    ('AFGHANISTAN', N'Afghanistan', 346),
    ('IRAN', N'Iran', 347),
    ('IRAQ', N'Iraq', 348),
    ('ISRAEL', N'Israel', 349),
    ('LEBANON', N'Lebanon', 350),
    ('SYRIA', N'Syria', 351),
    ('SAUDI_ARABIA', N'Saudi Arabia', 352),
    ('HEJAZ', N'Hejaz', 353),
    ('NEJD', N'Nejd', 354),
    ('YEMEN', N'Yemen', 355),
    ('ADEN', N'Aden', 356),
    ('ADEN_STATES', N'Aden States', 357),
    ('OMAN', N'Oman', 358),
    ('MUSCAT', N'Muscat', 359),
    ('TRUCIAL_STATES', N'Trucial States', 360),
    ('UNITED_ARAB_EMIRATES', N'United Arab Emirates', 361),
    ('ABU_DHABI', N'Abu Dhabi', 362),
    ('DUBAI', N'Dubai', 363),
    ('BAHRAIN', N'Bahrain', 364),
    ('KUWAIT', N'Kuwait', 365),
    ('QATAR', N'Qatar', 366),
    ('OTTOMAN_EMPIRE', N'Ottoman Empire', 367),
    ('TURKEY', N'Turkey', 368),
    ('BRITISH_INDIAN_OCEAN_TERRITORY', N'British Indian Ocean Territory', 369),
    ('NORTH_AMERICA', N'North America', 370),
    ('CENTRAL_AMERICA', N'Central America', 371),
    ('CARIBBEAN', N'Caribbean', 372),
    ('SOUTH_AMERICA', N'South America', 373),
    ('UNITED_STATES_HISTORICAL_AMP_CURRENT', N'United States — Historical & Current', 374),
    ('CANADA_HISTORICAL_AMP_CURRENT', N'Canada — Historical & Current', 375),
    ('UNITED_STATES', N'United States', 376),
    ('HAWAII', N'Hawaii', 377),
    ('CONFEDERATE_STATES', N'Confederate States', 378),
    ('CANAL_ZONE', N'Canal Zone', 379),
    ('CANADA', N'Canada', 380),
    ('NEWFOUNDLAND', N'Newfoundland', 381),
    ('NEW_BRUNSWICK', N'New Brunswick', 382),
    ('NOVA_SCOTIA', N'Nova Scotia', 383),
    ('PRINCE_EDWARD_ISLAND', N'Prince Edward Island', 384),
    ('BRITISH_COLUMBIA', N'British Columbia', 385),
    ('VANCOUVER_ISLAND', N'Vancouver Island', 386),
    ('MEXICO', N'Mexico', 387),
    ('SAINT_PIERRE_AND_MIQUELON', N'Saint Pierre and Miquelon', 388),
    ('BRITISH_HONDURAS_AMP_BELIZE', N'British Honduras & Belize', 389),
    ('BRITISH_HONDURAS', N'British Honduras', 390),
    ('BELIZE', N'Belize', 391),
    ('GUATEMALA', N'Guatemala', 392),
    ('HONDURAS', N'Honduras', 393),
    ('EL_SALVADOR', N'El Salvador', 394),
    ('NICARAGUA', N'Nicaragua', 395),
    ('COSTA_RICA', N'Costa Rica', 396),
    ('PANAMA', N'Panama', 397),
    ('ANTIGUA_AMP_BARBUDA', N'Antigua & Barbuda', 398),
    ('SAINT_KITTS_AMP_NEVIS', N'Saint Kitts & Nevis', 399),
    ('SAINT_VINCENT_HISTORICAL_AMP_CURRENT', N'Saint Vincent — Historical & Current', 400),
    ('TRINIDAD_AMP_TOBAGO', N'Trinidad & Tobago', 401),
    ('DUTCH_CARIBBEAN', N'Dutch Caribbean', 402),
    ('BAHAMAS', N'Bahamas', 403),
    ('BERMUDA', N'Bermuda', 404),
    ('JAMAICA', N'Jamaica', 405),
    ('CAYMAN_ISLANDS', N'Cayman Islands', 406),
    ('TURKS_AND_CAICOS_ISLANDS', N'Turks and Caicos Islands', 407),
    ('BRITISH_VIRGIN_ISLANDS', N'British Virgin Islands', 408),
    ('ANGUILLA', N'Anguilla', 409),
    ('MONTSERRAT', N'Montserrat', 410),
    ('DOMINICA', N'Dominica', 411),
    ('SAINT_LUCIA', N'Saint Lucia', 412),
    ('GRENADA', N'Grenada', 413),
    ('BARBADOS', N'Barbados', 414),
    ('CUBA', N'Cuba', 415),
    ('HAITI', N'Haiti', 416),
    ('DOMINICAN_REPUBLIC', N'Dominican Republic', 417),
    ('DANISH_WEST_INDIES', N'Danish West Indies', 418),
    ('LEEWARD_ISLANDS', N'Leeward Islands', 419),
    ('PUERTO_RICO', N'Puerto Rico', 420),
    ('ANTIGUA', N'Antigua', 421),
    ('BARBUDA', N'Barbuda', 422),
    ('ANTIGUA_AND_BARBUDA', N'Antigua and Barbuda', 423),
    ('SAINT_KITTS', N'Saint Kitts', 424),
    ('NEVIS', N'Nevis', 425),
    ('SAINT_KITTS_AND_NEVIS', N'Saint Kitts and Nevis', 426),
    ('SAINT_VINCENT', N'Saint Vincent', 427),
    ('SAINT_VINCENT_AND_THE_GRENADINES', N'Saint Vincent and the Grenadines', 428),
    ('TRINIDAD', N'Trinidad', 429),
    ('TOBAGO', N'Tobago', 430),
    ('TRINIDAD_AND_TOBAGO', N'Trinidad and Tobago', 431),
    ('ARUBA', N'Aruba', 432),
    ('BONAIRE', N'Bonaire', 433),
    ('CURACAO', N'Curaçao', 434),
    ('NETHERLANDS_ANTILLES', N'Netherlands Antilles', 435),
    ('SABA', N'Saba', 436),
    ('SINT_EUSTATIUS', N'Sint Eustatius', 437),
    ('SINT_MAARTEN', N'Sint Maarten', 438),
    ('BRITISH_GUIANA_AMP_GUYANA', N'British Guiana & Guyana', 439),
    ('SURINAME_HISTORICAL_AMP_CURRENT', N'Suriname — Historical & Current', 440),
    ('BRITISH_GUIANA', N'British Guiana', 441),
    ('GUYANA', N'Guyana', 442),
    ('DUTCH_GUIANA', N'Dutch Guiana', 443),
    ('SURINAME', N'Suriname', 444),
    ('ARGENTINA', N'Argentina', 445),
    ('BOLIVIA', N'Bolivia', 446),
    ('BRAZIL', N'Brazil', 447),
    ('CHILE', N'Chile', 448),
    ('COLOMBIA', N'Colombia', 449),
    ('ECUADOR', N'Ecuador', 450),
    ('PARAGUAY', N'Paraguay', 451),
    ('PERU', N'Peru', 452),
    ('URUGUAY', N'Uruguay', 453),
    ('VENEZUELA', N'Venezuela', 454),
    ('FRENCH_GUIANA', N'French Guiana', 455),
    ('FALKLAND_ISLANDS', N'Falkland Islands', 456),
    ('SOUTH_GEORGIA_AND_THE_SOUTH_SANDW_4EA016', N'South Georgia and the South Sandwich Islands', 457),
    ('AUSTRALIA_HISTORICAL_AMP_CURRENT', N'Australia — Historical & Current', 458),
    ('NEW_ZEALAND_AMP_DEPENDENCIES', N'New Zealand & Dependencies', 459),
    ('PAPUA_AMP_NEW_GUINEA', N'Papua & New Guinea', 460),
    ('MELANESIA', N'Melanesia', 461),
    ('GILBERT_ELLICE_KIRIBATI_AMP_TUVALU', N'Gilbert, Ellice, Kiribati & Tuvalu', 462),
    ('POLYNESIA', N'Polynesia', 463),
    ('MICRONESIA', N'Micronesia', 464),
    ('AUSTRALIA', N'Australia', 465),
    ('NEW_SOUTH_WALES', N'New South Wales', 466),
    ('VICTORIA', N'Victoria', 467),
    ('QUEENSLAND', N'Queensland', 468),
    ('SOUTH_AUSTRALIA', N'South Australia', 469),
    ('WESTERN_AUSTRALIA', N'Western Australia', 470),
    ('TASMANIA', N'Tasmania', 471),
    ('NORFOLK_ISLAND', N'Norfolk Island', 472),
    ('CHRISTMAS_ISLAND', N'Christmas Island', 473),
    ('COCOS_KEELING_ISLANDS', N'Cocos (Keeling) Islands', 474),
    ('BRITISH_COMMONWEALTH_OCCUPATION_FORCE', N'British Commonwealth Occupation Force', 475),
    ('NEW_ZEALAND', N'New Zealand', 476),
    ('COOK_ISLANDS', N'Cook Islands', 477),
    ('AITUTAKI', N'Aitutaki', 478),
    ('PENRHYN', N'Penrhyn', 479),
    ('NIUE', N'Niue', 480),
    ('TOKELAU', N'Tokelau', 481),
    ('BRITISH_NEW_GUINEA', N'British New Guinea', 482),
    ('PAPUA', N'Papua', 483),
    ('GERMAN_NEW_GUINEA', N'German New Guinea', 484),
    ('TERRITORY_OF_NEW_GUINEA', N'Territory of New Guinea', 485),
    ('PAPUA_NEW_GUINEA', N'Papua New Guinea', 486),
    ('NORTH_WEST_PACIFIC_ISLANDS', N'North West Pacific Islands', 487),
    ('FIJI', N'Fiji', 488),
    ('SOLOMON_ISLANDS', N'Solomon Islands', 489),
    ('BRITISH_SOLOMON_ISLANDS', N'British Solomon Islands', 490),
    ('NEW_HEBRIDES', N'New Hebrides', 491),
    ('VANUATU', N'Vanuatu', 492),
    ('NEW_CALEDONIA', N'New Caledonia', 493),
    ('GILBERT_AND_ELLICE_ISLANDS', N'Gilbert and Ellice Islands', 494),
    ('GILBERT_ISLANDS', N'Gilbert Islands', 495),
    ('KIRIBATI', N'Kiribati', 496),
    ('TUVALU', N'Tuvalu', 497),
    ('SAMOA', N'Samoa', 498),
    ('WESTERN_SAMOA', N'Western Samoa', 499),
    ('TONGA', N'Tonga', 500),
    ('FRENCH_POLYNESIA', N'French Polynesia', 501),
    ('WALLIS_AND_FUTUNA', N'Wallis and Futuna', 502),
    ('PITCAIRN_ISLANDS', N'Pitcairn Islands', 503),
    ('FEDERATED_STATES_OF_MICRONESIA', N'Federated States of Micronesia', 504),
    ('MARSHALL_ISLANDS', N'Marshall Islands', 505),
    ('PALAU', N'Palau', 506),
    ('GUAM', N'Guam', 507),
    ('NORTHERN_MARIANA_ISLANDS', N'Northern Mariana Islands', 508),
    ('NAURU', N'Nauru', 509),
    ('AUSTRALIAN_ANTARCTIC_TERRITORY', N'Australian Antarctic Territory', 510),
    ('BRITISH_ANTARCTIC_TERRITORY', N'British Antarctic Territory', 511),
    ('ROSS_DEPENDENCY', N'Ross Dependency', 512),
    ('FRENCH_SOUTHERN_AND_ANTARCTIC_TER_F5FBD2', N'French Southern and Antarctic Territories', 513),
    ('UNITED_NATIONS_NEW_YORK', N'United Nations — New York', 514),
    ('UNITED_NATIONS_GENEVA', N'United Nations — Geneva', 515),
    ('UNITED_NATIONS_VIENNA', N'United Nations — Vienna', 516)
) AS src (Code, Name, SortOrder)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.SortOrder = src.SortOrder, tgt.Active = 1
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, SortOrder, Active)
     VALUES (src.Code, src.Name, src.SortOrder, 1);
GO

/* Wire the hierarchy. The root nodes keep ParentID NULL. */
UPDATE child
   SET ParentID = parent.ID
  FROM philmart.Sys_ClassificationAreaCountry AS child
  JOIN (VALUES
        ('SOUTHERN_AFRICA', 'AFRICA'),
        ('EAST_AFRICA', 'AFRICA'),
        ('CENTRAL_AFRICA', 'AFRICA'),
        ('WEST_AFRICA', 'AFRICA'),
        ('NORTH_AFRICA', 'AFRICA'),
        ('INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS', 'AFRICA'),
        ('SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614', 'SOUTHERN_AFRICA'),
        ('HOMELANDS', 'SOUTHERN_AFRICA'),
        ('RHODESIA_AMP_ZIMBABWE', 'SOUTHERN_AFRICA'),
        ('BECHUANALAND_AMP_BOTSWANA', 'SOUTHERN_AFRICA'),
        ('BASUTOLAND_AMP_LESOTHO', 'SOUTHERN_AFRICA'),
        ('SWAZILAND_AMP_ESWATINI', 'SOUTHERN_AFRICA'),
        ('SOUTH_WEST_AFRICA_AMP_NAMIBIA', 'SOUTHERN_AFRICA'),
        ('SOUTH_AFRICA', 'SOUTHERN_AFRICA'),
        ('UNION_OF_SOUTH_AFRICA', 'SOUTHERN_AFRICA'),
        ('NORTHERN_RHODESIA', 'SOUTHERN_AFRICA'),
        ('ZAMBIA', 'SOUTHERN_AFRICA'),
        ('RHODESIA_AND_NYASALAND', 'SOUTHERN_AFRICA'),
        ('BRITISH_CENTRAL_AFRICA', 'SOUTHERN_AFRICA'),
        ('NYASALAND', 'SOUTHERN_AFRICA'),
        ('MALAWI', 'SOUTHERN_AFRICA'),
        ('MOZAMBIQUE', 'SOUTHERN_AFRICA'),
        ('MOZAMBIQUE_COMPANY', 'SOUTHERN_AFRICA'),
        ('NYASSA_COMPANY', 'SOUTHERN_AFRICA'),
        ('ZAMBEZIA', 'SOUTHERN_AFRICA'),
        ('ANGOLA', 'SOUTHERN_AFRICA'),
        ('CAPE_OF_GOOD_HOPE', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('NATAL', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('ORANGE_FREE_STATE', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('ORANGE_RIVER_COLONY', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('TRANSVAAL', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('GRIQUALAND_WEST', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('ZULULAND', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('NEW_REPUBLIC', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('STELLALAND', 'SOUTH_AFRICA_PRE_UNION_STATES_AMP_25A614'),
        ('BOPHUTHATSWANA', 'HOMELANDS'),
        ('CISKEI', 'HOMELANDS'),
        ('TRANSKEI', 'HOMELANDS'),
        ('VENDA', 'HOMELANDS'),
        ('BRITISH_SOUTH_AFRICA_COMPANY', 'RHODESIA_AMP_ZIMBABWE'),
        ('SOUTHERN_RHODESIA', 'RHODESIA_AMP_ZIMBABWE'),
        ('RHODESIA', 'RHODESIA_AMP_ZIMBABWE'),
        ('ZIMBABWE', 'RHODESIA_AMP_ZIMBABWE'),
        ('BRITISH_BECHUANALAND', 'BECHUANALAND_AMP_BOTSWANA'),
        ('BECHUANALAND_PROTECTORATE', 'BECHUANALAND_AMP_BOTSWANA'),
        ('BOTSWANA', 'BECHUANALAND_AMP_BOTSWANA'),
        ('BASUTOLAND', 'BASUTOLAND_AMP_LESOTHO'),
        ('LESOTHO', 'BASUTOLAND_AMP_LESOTHO'),
        ('SWAZILAND', 'SWAZILAND_AMP_ESWATINI'),
        ('ESWATINI', 'SWAZILAND_AMP_ESWATINI'),
        ('GERMAN_SOUTH_WEST_AFRICA', 'SOUTH_WEST_AFRICA_AMP_NAMIBIA'),
        ('SOUTH_WEST_AFRICA', 'SOUTH_WEST_AFRICA_AMP_NAMIBIA'),
        ('NAMIBIA', 'SOUTH_WEST_AFRICA_AMP_NAMIBIA'),
        ('KENYA_UGANDA_AMP_TANGANYIKA', 'EAST_AFRICA'),
        ('RWANDA_AMP_BURUNDI', 'EAST_AFRICA'),
        ('SOMALIA_AMP_SOMALILAND', 'EAST_AFRICA'),
        ('TANZANIA', 'EAST_AFRICA'),
        ('ZANZIBAR', 'EAST_AFRICA'),
        ('ETHIOPIA', 'EAST_AFRICA'),
        ('ERITREA', 'EAST_AFRICA'),
        ('DJIBOUTI', 'EAST_AFRICA'),
        ('FRENCH_SOMALI_COAST', 'EAST_AFRICA'),
        ('AFARS_AND_ISSAS', 'EAST_AFRICA'),
        ('GERMAN_EAST_AFRICA', 'EAST_AFRICA'),
        ('ITALIAN_EAST_AFRICA', 'EAST_AFRICA'),
        ('KENYA', 'KENYA_UGANDA_AMP_TANGANYIKA'),
        ('UGANDA', 'KENYA_UGANDA_AMP_TANGANYIKA'),
        ('TANGANYIKA', 'KENYA_UGANDA_AMP_TANGANYIKA'),
        ('BRITISH_EAST_AFRICA', 'KENYA_UGANDA_AMP_TANGANYIKA'),
        ('EAST_AFRICA_AMP_UGANDA_PROTECTORATES', 'KENYA_UGANDA_AMP_TANGANYIKA'),
        ('RUANDA_URUNDI', 'RWANDA_AMP_BURUNDI'),
        ('RWANDA', 'RWANDA_AMP_BURUNDI'),
        ('BURUNDI', 'RWANDA_AMP_BURUNDI'),
        ('SOMALIA', 'SOMALIA_AMP_SOMALILAND'),
        ('SOMALILAND_PROTECTORATE', 'SOMALIA_AMP_SOMALILAND'),
        ('ITALIAN_SOMALILAND', 'SOMALIA_AMP_SOMALILAND'),
        ('CONGO_AMP_ZAIRE', 'CENTRAL_AFRICA'),
        ('REPUBLIC_OF_THE_CONGO', 'CENTRAL_AFRICA'),
        ('FRENCH_CONGO', 'CENTRAL_AFRICA'),
        ('CENTRAL_AFRICAN_REPUBLIC', 'CENTRAL_AFRICA'),
        ('CENTRAL_AFRICAN_EMPIRE', 'CENTRAL_AFRICA'),
        ('CHAD', 'CENTRAL_AFRICA'),
        ('GABON', 'CENTRAL_AFRICA'),
        ('CAMEROON', 'CENTRAL_AFRICA'),
        ('FRENCH_CAMEROON', 'CENTRAL_AFRICA'),
        ('GERMAN_CAMEROON', 'CENTRAL_AFRICA'),
        ('SPANISH_GUINEA', 'CENTRAL_AFRICA'),
        ('EQUATORIAL_GUINEA', 'CENTRAL_AFRICA'),
        ('FRENCH_EQUATORIAL_AFRICA', 'CENTRAL_AFRICA'),
        ('BELGIAN_CONGO', 'CONGO_AMP_ZAIRE'),
        ('CONGO_LEOPOLDVILLE', 'CONGO_AMP_ZAIRE'),
        ('ZAIRE', 'CONGO_AMP_ZAIRE'),
        ('DEMOCRATIC_REPUBLIC_OF_THE_CONGO', 'CONGO_AMP_ZAIRE'),
        ('KATANGA', 'CONGO_AMP_ZAIRE'),
        ('SOUTH_KASAI', 'CONGO_AMP_ZAIRE'),
        ('GOLD_COAST_AMP_GHANA', 'WEST_AFRICA'),
        ('DAHOMEY_AMP_BENIN', 'WEST_AFRICA'),
        ('UPPER_VOLTA_AMP_BURKINA_FASO', 'WEST_AFRICA'),
        ('FRENCH_GUINEA_AMP_GUINEA', 'WEST_AFRICA'),
        ('PORTUGUESE_GUINEA_AMP_GUINEA_BISSAU', 'WEST_AFRICA'),
        ('TOGO_HISTORICAL_AMP_CURRENT', 'WEST_AFRICA'),
        ('NIGERIA_HISTORICAL_AMP_CURRENT', 'WEST_AFRICA'),
        ('IVORY_COAST', 'WEST_AFRICA'),
        ('SENEGAL', 'WEST_AFRICA'),
        ('MALI', 'WEST_AFRICA'),
        ('MAURITANIA', 'WEST_AFRICA'),
        ('NIGER', 'WEST_AFRICA'),
        ('LIBERIA', 'WEST_AFRICA'),
        ('SIERRA_LEONE', 'WEST_AFRICA'),
        ('GAMBIA', 'WEST_AFRICA'),
        ('CAPE_VERDE', 'WEST_AFRICA'),
        ('FRENCH_WEST_AFRICA', 'WEST_AFRICA'),
        ('GOLD_COAST', 'GOLD_COAST_AMP_GHANA'),
        ('GHANA', 'GOLD_COAST_AMP_GHANA'),
        ('DAHOMEY', 'DAHOMEY_AMP_BENIN'),
        ('BENIN', 'DAHOMEY_AMP_BENIN'),
        ('UPPER_VOLTA', 'UPPER_VOLTA_AMP_BURKINA_FASO'),
        ('BURKINA_FASO', 'UPPER_VOLTA_AMP_BURKINA_FASO'),
        ('FRENCH_GUINEA', 'FRENCH_GUINEA_AMP_GUINEA'),
        ('GUINEA', 'FRENCH_GUINEA_AMP_GUINEA'),
        ('PORTUGUESE_GUINEA', 'PORTUGUESE_GUINEA_AMP_GUINEA_BISSAU'),
        ('GUINEA_BISSAU', 'PORTUGUESE_GUINEA_AMP_GUINEA_BISSAU'),
        ('GERMAN_TOGO', 'TOGO_HISTORICAL_AMP_CURRENT'),
        ('TOGO', 'TOGO_HISTORICAL_AMP_CURRENT'),
        ('LAGOS', 'NIGERIA_HISTORICAL_AMP_CURRENT'),
        ('NORTHERN_NIGERIA', 'NIGERIA_HISTORICAL_AMP_CURRENT'),
        ('SOUTHERN_NIGERIA', 'NIGERIA_HISTORICAL_AMP_CURRENT'),
        ('NIGERIA', 'NIGERIA_HISTORICAL_AMP_CURRENT'),
        ('MOROCCO_AMP_PROTECTORATES', 'NORTH_AFRICA'),
        ('SUDAN_AMP_SOUTH_SUDAN', 'NORTH_AFRICA'),
        ('ALGERIA', 'NORTH_AFRICA'),
        ('TUNISIA', 'NORTH_AFRICA'),
        ('LIBYA', 'NORTH_AFRICA'),
        ('EGYPT', 'NORTH_AFRICA'),
        ('WESTERN_SAHARA', 'NORTH_AFRICA'),
        ('MOROCCO', 'MOROCCO_AMP_PROTECTORATES'),
        ('FRENCH_MOROCCO', 'MOROCCO_AMP_PROTECTORATES'),
        ('SPANISH_MOROCCO', 'MOROCCO_AMP_PROTECTORATES'),
        ('SUDAN', 'SUDAN_AMP_SOUTH_SUDAN'),
        ('SOUTH_SUDAN', 'SUDAN_AMP_SOUTH_SUDAN'),
        ('MAURITIUS', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('SEYCHELLES', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('MADAGASCAR', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('COMOROS', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('REUNION', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('SAINT_HELENA', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('ASCENSION', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('TRISTAN_DA_CUNHA', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('MAYOTTE', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('SAO_TOME_AND_PRINCIPE', 'INDIAN_OCEAN_AMP_ATLANTIC_ISLANDS'),
        ('BRITISH_ISLES_AMP_CROWN_DEPENDENCIES', 'EUROPE'),
        ('SCANDINAVIA_AMP_NORDIC', 'EUROPE'),
        ('BENELUX', 'EUROPE'),
        ('GERMANY_HISTORICAL_AMP_CURRENT', 'EUROPE'),
        ('ITALY_HISTORICAL_AMP_CURRENT', 'EUROPE'),
        ('CZECHOSLOVAKIA_AMP_SUCCESSOR_STATES', 'EUROPE'),
        ('YUGOSLAVIA_AMP_SUCCESSOR_STATES', 'EUROPE'),
        ('RUSSIA_AMP_USSR', 'EUROPE'),
        ('IBERIA', 'EUROPE'),
        ('CENTRAL_EUROPE', 'EUROPE'),
        ('BALKANS_AMP_SOUTHEAST_EUROPE', 'EUROPE'),
        ('WESTERN_EUROPE', 'EUROPE'),
        ('GREAT_BRITAIN', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('IRELAND', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('ISLE_OF_MAN', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('JERSEY', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('GUERNSEY', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('ALDERNEY', 'BRITISH_ISLES_AMP_CROWN_DEPENDENCIES'),
        ('DENMARK', 'SCANDINAVIA_AMP_NORDIC'),
        ('FAROE_ISLANDS', 'SCANDINAVIA_AMP_NORDIC'),
        ('GREENLAND', 'SCANDINAVIA_AMP_NORDIC'),
        ('ICELAND', 'SCANDINAVIA_AMP_NORDIC'),
        ('NORWAY', 'SCANDINAVIA_AMP_NORDIC'),
        ('SWEDEN', 'SCANDINAVIA_AMP_NORDIC'),
        ('FINLAND', 'SCANDINAVIA_AMP_NORDIC'),
        ('ALAND', 'SCANDINAVIA_AMP_NORDIC'),
        ('BELGIUM', 'BENELUX'),
        ('NETHERLANDS', 'BENELUX'),
        ('LUXEMBOURG', 'BENELUX'),
        ('GERMAN_STATES', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('BADEN', 'GERMAN_STATES'),
        ('BAVARIA', 'GERMAN_STATES'),
        ('HANOVER', 'GERMAN_STATES'),
        ('PRUSSIA', 'GERMAN_STATES'),
        ('SAXONY', 'GERMAN_STATES'),
        ('WURTTEMBERG', 'GERMAN_STATES'),
        ('BERGEDORF', 'GERMAN_STATES'),
        ('BRUNSWICK', 'GERMAN_STATES'),
        ('BREMEN', 'GERMAN_STATES'),
        ('HAMBURG', 'GERMAN_STATES'),
        ('HELIGOLAND', 'GERMAN_STATES'),
        ('LUBECK', 'GERMAN_STATES'),
        ('MECKLENBURG_SCHWERIN', 'GERMAN_STATES'),
        ('MECKLENBURG_STRELITZ', 'GERMAN_STATES'),
        ('OLDENBURG', 'GERMAN_STATES'),
        ('THURN_AND_TAXIS', 'GERMAN_STATES'),
        ('NORTH_GERMAN_CONFEDERATION', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('GERMAN_EMPIRE', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('WEIMAR_GERMANY', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('GERMANY_THIRD_REICH', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('GERMANY_ALLIED_OCCUPATION', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('WEST_GERMANY', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('EAST_GERMANY', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('WEST_BERLIN', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('GERMANY', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('DANZIG', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('SAAR', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('MEMEL', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('UPPER_SILESIA', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('SCHLESWIG', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('ALLENSTEIN', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('MARIENWERDER', 'GERMANY_HISTORICAL_AMP_CURRENT'),
        ('ITALIAN_STATES', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('PAPAL_STATES', 'ITALIAN_STATES'),
        ('SARDINIA', 'ITALIAN_STATES'),
        ('TUSCANY', 'ITALIAN_STATES'),
        ('MODENA', 'ITALIAN_STATES'),
        ('PARMA', 'ITALIAN_STATES'),
        ('TWO_SICILIES', 'ITALIAN_STATES'),
        ('LOMBARDY_AMP_VENETIA', 'ITALIAN_STATES'),
        ('FIUME', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('TRIESTE', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('VENEZIA_GIULIA_AMP_ISTRIA', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('ITALY', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('SAN_MARINO', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('VATICAN_CITY', 'ITALY_HISTORICAL_AMP_CURRENT'),
        ('CZECHOSLOVAKIA', 'CZECHOSLOVAKIA_AMP_SUCCESSOR_STATES'),
        ('CZECH_REPUBLIC', 'CZECHOSLOVAKIA_AMP_SUCCESSOR_STATES'),
        ('SLOVAKIA', 'CZECHOSLOVAKIA_AMP_SUCCESSOR_STATES'),
        ('YUGOSLAVIA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('SLOVENIA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('CROATIA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('BOSNIA_AND_HERZEGOVINA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('SERBIA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('MONTENEGRO', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('NORTH_MACEDONIA', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('KOSOVO', 'YUGOSLAVIA_AMP_SUCCESSOR_STATES'),
        ('RUSSIAN_EMPIRE', 'RUSSIA_AMP_USSR'),
        ('SOVIET_UNION', 'RUSSIA_AMP_USSR'),
        ('RUSSIA', 'RUSSIA_AMP_USSR'),
        ('BELARUS', 'RUSSIA_AMP_USSR'),
        ('UKRAINE', 'RUSSIA_AMP_USSR'),
        ('MOLDOVA', 'RUSSIA_AMP_USSR'),
        ('ESTONIA', 'RUSSIA_AMP_USSR'),
        ('LATVIA', 'RUSSIA_AMP_USSR'),
        ('LITHUANIA', 'RUSSIA_AMP_USSR'),
        ('SPAIN', 'IBERIA'),
        ('PORTUGAL', 'IBERIA'),
        ('ANDORRA', 'IBERIA'),
        ('GIBRALTAR', 'IBERIA'),
        ('AUSTRIA', 'CENTRAL_EUROPE'),
        ('HUNGARY', 'CENTRAL_EUROPE'),
        ('LIECHTENSTEIN', 'CENTRAL_EUROPE'),
        ('SWITZERLAND', 'CENTRAL_EUROPE'),
        ('ALBANIA', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('BULGARIA', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('GREECE', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('CRETE', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('CYPRUS', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('ROMANIA', 'BALKANS_AMP_SOUTHEAST_EUROPE'),
        ('FRANCE', 'WESTERN_EUROPE'),
        ('MONACO', 'WESTERN_EUROPE'),
        ('MALTA', 'EUROPE'),
        ('INDIAN_SUBCONTINENT', 'ASIA_AMP_MIDDLE_EAST'),
        ('SOUTHEAST_ASIA', 'ASIA_AMP_MIDDLE_EAST'),
        ('MALAYA_AMP_STRAITS_SETTLEMENTS', 'ASIA_AMP_MIDDLE_EAST'),
        ('CHINA_HISTORICAL_AMP_CURRENT', 'ASIA_AMP_MIDDLE_EAST'),
        ('EAST_ASIA', 'ASIA_AMP_MIDDLE_EAST'),
        ('KOREA_HISTORICAL_AMP_CURRENT', 'ASIA_AMP_MIDDLE_EAST'),
        ('CENTRAL_ASIA', 'ASIA_AMP_MIDDLE_EAST'),
        ('CAUCASUS', 'ASIA_AMP_MIDDLE_EAST'),
        ('PALESTINE_AMP_JORDAN', 'ASIA_AMP_MIDDLE_EAST'),
        ('MIDDLE_EAST', 'ASIA_AMP_MIDDLE_EAST'),
        ('ARABIAN_PENINSULA_AMP_GULF', 'ASIA_AMP_MIDDLE_EAST'),
        ('TURKEY_HISTORICAL_AMP_CURRENT', 'ASIA_AMP_MIDDLE_EAST'),
        ('INDIA', 'INDIAN_SUBCONTINENT'),
        ('BRITISH_INDIA', 'INDIAN_SUBCONTINENT'),
        ('INDIAN_STATES', 'INDIAN_SUBCONTINENT'),
        ('PAKISTAN', 'INDIAN_SUBCONTINENT'),
        ('BANGLADESH', 'INDIAN_SUBCONTINENT'),
        ('NEPAL', 'INDIAN_SUBCONTINENT'),
        ('BHUTAN', 'INDIAN_SUBCONTINENT'),
        ('CEYLON', 'INDIAN_SUBCONTINENT'),
        ('SRI_LANKA', 'INDIAN_SUBCONTINENT'),
        ('MALDIVES', 'INDIAN_SUBCONTINENT'),
        ('PORTUGUESE_INDIA', 'INDIAN_SUBCONTINENT'),
        ('FRENCH_INDIA', 'INDIAN_SUBCONTINENT'),
        ('CONVENTION_STATES', 'INDIAN_STATES'),
        ('FEUDATORY_STATES', 'INDIAN_STATES'),
        ('BURMA', 'SOUTHEAST_ASIA'),
        ('MYANMAR', 'SOUTHEAST_ASIA'),
        ('SIAM', 'SOUTHEAST_ASIA'),
        ('THAILAND', 'SOUTHEAST_ASIA'),
        ('CAMBODIA', 'SOUTHEAST_ASIA'),
        ('KAMPUCHEA', 'SOUTHEAST_ASIA'),
        ('LAOS', 'SOUTHEAST_ASIA'),
        ('FRENCH_INDOCHINA', 'SOUTHEAST_ASIA'),
        ('NORTH_VIETNAM', 'SOUTHEAST_ASIA'),
        ('SOUTH_VIETNAM', 'SOUTHEAST_ASIA'),
        ('VIETNAM', 'SOUTHEAST_ASIA'),
        ('DUTCH_EAST_INDIES', 'SOUTHEAST_ASIA'),
        ('INDONESIA', 'SOUTHEAST_ASIA'),
        ('PORTUGUESE_TIMOR', 'SOUTHEAST_ASIA'),
        ('TIMOR_LESTE', 'SOUTHEAST_ASIA'),
        ('PHILIPPINES', 'SOUTHEAST_ASIA'),
        ('STRAITS_SETTLEMENTS', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('MALAYA', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('MALAYSIA', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('SINGAPORE', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('NORTH_BORNEO', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('SARAWAK', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('LABUAN', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('BRUNEI', 'MALAYA_AMP_STRAITS_SETTLEMENTS'),
        ('CHINESE_EMPIRE', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('REPUBLIC_OF_CHINA', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('PEOPLE_S_REPUBLIC_OF_CHINA', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('TAIWAN', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('HONG_KONG', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('MACAU', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('MANCHUKUO', 'CHINA_HISTORICAL_AMP_CURRENT'),
        ('MONGOLIA', 'EAST_ASIA'),
        ('JAPAN', 'EAST_ASIA'),
        ('KOREA', 'KOREA_HISTORICAL_AMP_CURRENT'),
        ('NORTH_KOREA', 'KOREA_HISTORICAL_AMP_CURRENT'),
        ('SOUTH_KOREA', 'KOREA_HISTORICAL_AMP_CURRENT'),
        ('KAZAKHSTAN', 'CENTRAL_ASIA'),
        ('KYRGYZSTAN', 'CENTRAL_ASIA'),
        ('TAJIKISTAN', 'CENTRAL_ASIA'),
        ('TURKMENISTAN', 'CENTRAL_ASIA'),
        ('UZBEKISTAN', 'CENTRAL_ASIA'),
        ('TUVA', 'CENTRAL_ASIA'),
        ('ARMENIA', 'CAUCASUS'),
        ('AZERBAIJAN', 'CAUCASUS'),
        ('GEORGIA', 'CAUCASUS'),
        ('PALESTINE_BRITISH_MANDATE', 'PALESTINE_AMP_JORDAN'),
        ('PALESTINE', 'PALESTINE_AMP_JORDAN'),
        ('TRANSJORDAN', 'PALESTINE_AMP_JORDAN'),
        ('JORDAN', 'PALESTINE_AMP_JORDAN'),
        ('AFGHANISTAN', 'MIDDLE_EAST'),
        ('IRAN', 'MIDDLE_EAST'),
        ('IRAQ', 'MIDDLE_EAST'),
        ('ISRAEL', 'MIDDLE_EAST'),
        ('LEBANON', 'MIDDLE_EAST'),
        ('SYRIA', 'MIDDLE_EAST'),
        ('SAUDI_ARABIA', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('HEJAZ', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('NEJD', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('YEMEN', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('ADEN', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('ADEN_STATES', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('OMAN', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('MUSCAT', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('TRUCIAL_STATES', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('UNITED_ARAB_EMIRATES', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('ABU_DHABI', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('DUBAI', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('BAHRAIN', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('KUWAIT', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('QATAR', 'ARABIAN_PENINSULA_AMP_GULF'),
        ('OTTOMAN_EMPIRE', 'TURKEY_HISTORICAL_AMP_CURRENT'),
        ('TURKEY', 'TURKEY_HISTORICAL_AMP_CURRENT'),
        ('BRITISH_INDIAN_OCEAN_TERRITORY', 'ASIA_AMP_MIDDLE_EAST'),
        ('NORTH_AMERICA', 'AMERICAS'),
        ('CENTRAL_AMERICA', 'AMERICAS'),
        ('CARIBBEAN', 'AMERICAS'),
        ('SOUTH_AMERICA', 'AMERICAS'),
        ('UNITED_STATES_HISTORICAL_AMP_CURRENT', 'NORTH_AMERICA'),
        ('CANADA_HISTORICAL_AMP_CURRENT', 'NORTH_AMERICA'),
        ('UNITED_STATES', 'UNITED_STATES_HISTORICAL_AMP_CURRENT'),
        ('HAWAII', 'UNITED_STATES_HISTORICAL_AMP_CURRENT'),
        ('CONFEDERATE_STATES', 'UNITED_STATES_HISTORICAL_AMP_CURRENT'),
        ('CANAL_ZONE', 'UNITED_STATES_HISTORICAL_AMP_CURRENT'),
        ('CANADA', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('NEWFOUNDLAND', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('NEW_BRUNSWICK', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('NOVA_SCOTIA', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('PRINCE_EDWARD_ISLAND', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('BRITISH_COLUMBIA', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('VANCOUVER_ISLAND', 'CANADA_HISTORICAL_AMP_CURRENT'),
        ('MEXICO', 'NORTH_AMERICA'),
        ('SAINT_PIERRE_AND_MIQUELON', 'NORTH_AMERICA'),
        ('BRITISH_HONDURAS_AMP_BELIZE', 'CENTRAL_AMERICA'),
        ('BRITISH_HONDURAS', 'BRITISH_HONDURAS_AMP_BELIZE'),
        ('BELIZE', 'BRITISH_HONDURAS_AMP_BELIZE'),
        ('GUATEMALA', 'CENTRAL_AMERICA'),
        ('HONDURAS', 'CENTRAL_AMERICA'),
        ('EL_SALVADOR', 'CENTRAL_AMERICA'),
        ('NICARAGUA', 'CENTRAL_AMERICA'),
        ('COSTA_RICA', 'CENTRAL_AMERICA'),
        ('PANAMA', 'CENTRAL_AMERICA'),
        ('ANTIGUA_AMP_BARBUDA', 'CARIBBEAN'),
        ('SAINT_KITTS_AMP_NEVIS', 'CARIBBEAN'),
        ('SAINT_VINCENT_HISTORICAL_AMP_CURRENT', 'CARIBBEAN'),
        ('TRINIDAD_AMP_TOBAGO', 'CARIBBEAN'),
        ('DUTCH_CARIBBEAN', 'CARIBBEAN'),
        ('BAHAMAS', 'CARIBBEAN'),
        ('BERMUDA', 'CARIBBEAN'),
        ('JAMAICA', 'CARIBBEAN'),
        ('CAYMAN_ISLANDS', 'CARIBBEAN'),
        ('TURKS_AND_CAICOS_ISLANDS', 'CARIBBEAN'),
        ('BRITISH_VIRGIN_ISLANDS', 'CARIBBEAN'),
        ('ANGUILLA', 'CARIBBEAN'),
        ('MONTSERRAT', 'CARIBBEAN'),
        ('DOMINICA', 'CARIBBEAN'),
        ('SAINT_LUCIA', 'CARIBBEAN'),
        ('GRENADA', 'CARIBBEAN'),
        ('BARBADOS', 'CARIBBEAN'),
        ('CUBA', 'CARIBBEAN'),
        ('HAITI', 'CARIBBEAN'),
        ('DOMINICAN_REPUBLIC', 'CARIBBEAN'),
        ('DANISH_WEST_INDIES', 'CARIBBEAN'),
        ('LEEWARD_ISLANDS', 'CARIBBEAN'),
        ('PUERTO_RICO', 'CARIBBEAN'),
        ('ANTIGUA', 'ANTIGUA_AMP_BARBUDA'),
        ('BARBUDA', 'ANTIGUA_AMP_BARBUDA'),
        ('ANTIGUA_AND_BARBUDA', 'ANTIGUA_AMP_BARBUDA'),
        ('SAINT_KITTS', 'SAINT_KITTS_AMP_NEVIS'),
        ('NEVIS', 'SAINT_KITTS_AMP_NEVIS'),
        ('SAINT_KITTS_AND_NEVIS', 'SAINT_KITTS_AMP_NEVIS'),
        ('SAINT_VINCENT', 'SAINT_VINCENT_HISTORICAL_AMP_CURRENT'),
        ('SAINT_VINCENT_AND_THE_GRENADINES', 'SAINT_VINCENT_HISTORICAL_AMP_CURRENT'),
        ('TRINIDAD', 'TRINIDAD_AMP_TOBAGO'),
        ('TOBAGO', 'TRINIDAD_AMP_TOBAGO'),
        ('TRINIDAD_AND_TOBAGO', 'TRINIDAD_AMP_TOBAGO'),
        ('ARUBA', 'DUTCH_CARIBBEAN'),
        ('BONAIRE', 'DUTCH_CARIBBEAN'),
        ('CURACAO', 'DUTCH_CARIBBEAN'),
        ('NETHERLANDS_ANTILLES', 'DUTCH_CARIBBEAN'),
        ('SABA', 'DUTCH_CARIBBEAN'),
        ('SINT_EUSTATIUS', 'DUTCH_CARIBBEAN'),
        ('SINT_MAARTEN', 'DUTCH_CARIBBEAN'),
        ('BRITISH_GUIANA_AMP_GUYANA', 'SOUTH_AMERICA'),
        ('SURINAME_HISTORICAL_AMP_CURRENT', 'SOUTH_AMERICA'),
        ('BRITISH_GUIANA', 'BRITISH_GUIANA_AMP_GUYANA'),
        ('GUYANA', 'BRITISH_GUIANA_AMP_GUYANA'),
        ('DUTCH_GUIANA', 'SURINAME_HISTORICAL_AMP_CURRENT'),
        ('SURINAME', 'SURINAME_HISTORICAL_AMP_CURRENT'),
        ('ARGENTINA', 'SOUTH_AMERICA'),
        ('BOLIVIA', 'SOUTH_AMERICA'),
        ('BRAZIL', 'SOUTH_AMERICA'),
        ('CHILE', 'SOUTH_AMERICA'),
        ('COLOMBIA', 'SOUTH_AMERICA'),
        ('ECUADOR', 'SOUTH_AMERICA'),
        ('PARAGUAY', 'SOUTH_AMERICA'),
        ('PERU', 'SOUTH_AMERICA'),
        ('URUGUAY', 'SOUTH_AMERICA'),
        ('VENEZUELA', 'SOUTH_AMERICA'),
        ('FRENCH_GUIANA', 'SOUTH_AMERICA'),
        ('FALKLAND_ISLANDS', 'SOUTH_AMERICA'),
        ('SOUTH_GEORGIA_AND_THE_SOUTH_SANDW_4EA016', 'SOUTH_AMERICA'),
        ('AUSTRALIA_HISTORICAL_AMP_CURRENT', 'OCEANIA_AMP_PACIFIC'),
        ('NEW_ZEALAND_AMP_DEPENDENCIES', 'OCEANIA_AMP_PACIFIC'),
        ('PAPUA_AMP_NEW_GUINEA', 'OCEANIA_AMP_PACIFIC'),
        ('MELANESIA', 'OCEANIA_AMP_PACIFIC'),
        ('GILBERT_ELLICE_KIRIBATI_AMP_TUVALU', 'OCEANIA_AMP_PACIFIC'),
        ('POLYNESIA', 'OCEANIA_AMP_PACIFIC'),
        ('MICRONESIA', 'OCEANIA_AMP_PACIFIC'),
        ('AUSTRALIA', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('NEW_SOUTH_WALES', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('VICTORIA', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('QUEENSLAND', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('SOUTH_AUSTRALIA', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('WESTERN_AUSTRALIA', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('TASMANIA', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('NORFOLK_ISLAND', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('CHRISTMAS_ISLAND', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('COCOS_KEELING_ISLANDS', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('BRITISH_COMMONWEALTH_OCCUPATION_FORCE', 'AUSTRALIA_HISTORICAL_AMP_CURRENT'),
        ('NEW_ZEALAND', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('COOK_ISLANDS', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('AITUTAKI', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('PENRHYN', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('NIUE', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('TOKELAU', 'NEW_ZEALAND_AMP_DEPENDENCIES'),
        ('BRITISH_NEW_GUINEA', 'PAPUA_AMP_NEW_GUINEA'),
        ('PAPUA', 'PAPUA_AMP_NEW_GUINEA'),
        ('GERMAN_NEW_GUINEA', 'PAPUA_AMP_NEW_GUINEA'),
        ('TERRITORY_OF_NEW_GUINEA', 'PAPUA_AMP_NEW_GUINEA'),
        ('PAPUA_NEW_GUINEA', 'PAPUA_AMP_NEW_GUINEA'),
        ('NORTH_WEST_PACIFIC_ISLANDS', 'PAPUA_AMP_NEW_GUINEA'),
        ('FIJI', 'MELANESIA'),
        ('SOLOMON_ISLANDS', 'MELANESIA'),
        ('BRITISH_SOLOMON_ISLANDS', 'MELANESIA'),
        ('NEW_HEBRIDES', 'MELANESIA'),
        ('VANUATU', 'MELANESIA'),
        ('NEW_CALEDONIA', 'MELANESIA'),
        ('GILBERT_AND_ELLICE_ISLANDS', 'GILBERT_ELLICE_KIRIBATI_AMP_TUVALU'),
        ('GILBERT_ISLANDS', 'GILBERT_ELLICE_KIRIBATI_AMP_TUVALU'),
        ('KIRIBATI', 'GILBERT_ELLICE_KIRIBATI_AMP_TUVALU'),
        ('TUVALU', 'GILBERT_ELLICE_KIRIBATI_AMP_TUVALU'),
        ('SAMOA', 'POLYNESIA'),
        ('WESTERN_SAMOA', 'POLYNESIA'),
        ('TONGA', 'POLYNESIA'),
        ('FRENCH_POLYNESIA', 'POLYNESIA'),
        ('WALLIS_AND_FUTUNA', 'POLYNESIA'),
        ('PITCAIRN_ISLANDS', 'POLYNESIA'),
        ('FEDERATED_STATES_OF_MICRONESIA', 'MICRONESIA'),
        ('MARSHALL_ISLANDS', 'MICRONESIA'),
        ('PALAU', 'MICRONESIA'),
        ('GUAM', 'MICRONESIA'),
        ('NORTHERN_MARIANA_ISLANDS', 'MICRONESIA'),
        ('NAURU', 'OCEANIA_AMP_PACIFIC'),
        ('AUSTRALIAN_ANTARCTIC_TERRITORY', 'ANTARCTICA'),
        ('BRITISH_ANTARCTIC_TERRITORY', 'ANTARCTICA'),
        ('ROSS_DEPENDENCY', 'ANTARCTICA'),
        ('FRENCH_SOUTHERN_AND_ANTARCTIC_TER_F5FBD2', 'ANTARCTICA'),
        ('UNITED_NATIONS_NEW_YORK', 'INTERNATIONAL_POSTAL_ADMINISTRATIONS'),
        ('UNITED_NATIONS_GENEVA', 'INTERNATIONAL_POSTAL_ADMINISTRATIONS'),
        ('UNITED_NATIONS_VIENNA', 'INTERNATIONAL_POSTAL_ADMINISTRATIONS')
  ) AS link (Code, ParentCode) ON link.Code = child.Code
  JOIN philmart.Sys_ClassificationAreaCountry AS parent ON parent.Code = link.ParentCode
 WHERE child.ParentID IS NULL OR child.ParentID <> parent.ID;
GO

/* ---------------------------------------------- controlled email catalogue ---
   D060. Loaded directly from PHILMART_CURRENT_EMAIL_CATALOGUE_2026-09-16.csv.

   Authority is the whole point of this table. RETIRED and PENDING_NOT_APPROVED
   mean DO NOT IMPLEMENT and DO NOT SEND: EML-006, 009, 011, 014 and 023 are
   retired and EML-024 is pending and not approved. All 24 rows are loaded,
   retired ones included, so an application looking up a code finds an explicit
   refusal rather than a missing row. The MERGE updates Authority on re-run,
   which is what demotes a template the controlled catalogue later retires.

   ReplyEnabled is set only for EML-007 Buyer Query Reply: the catalogue makes
   every other template transactional / no-reply, and a reply path is permitted
   only where the inbound reply updates or reopens the SAME Buyer Query (D046).
   IsOptional is set only for EML-013 Outbid Alert (D068, throttled).

   SubjectTemplate and BodyTemplate are deliberately left NULL. The D076
   catalogue controls each template's trigger and communication rule but not its
   wording. The COM-001.. wording in the 7 September construction pack belongs
   to the SUPERSEDED numbering and cites the old D-1xx decisions, so copying it
   here would attach unapproved wording to controlled trigger points. Load
   wording once it is approved.                                               */
MERGE philmart.Sys_EmailTemplate AS tgt
USING (VALUES
    ('EML-001', 'current', N'Invoice Issued', N'Invoice issued', N'Transactional / no-reply', 0, 0),
    ('EML-002', 'current', N'Payment Received, Balance Outstanding', N'Payment recorded while invoice balance remains', N'Transactional / no-reply', 0, 0),
    ('EML-003', 'current', N'Payment Reminder', N'Reminder driven by oldest outstanding invoice', N'Transactional / no-reply', 0, 0),
    ('EML-004', 'current', N'Item Dispatched', N'Dispatch recorded after full payment', N'Transactional / no-reply', 0, 0),
    ('EML-005', 'current', N'Ready for Collection', N'Ready for Collection recorded after full payment', N'Transactional / no-reply', 0, 0),
    ('EML-006', 'retired', NULL, NULL, N'Do not implement', 0, 0),
    ('EML-007', 'current', N'Buyer Query Reply', N'Shop posts new Buyer Query reply', N'Reply-enabled only if inbound reply updates/reopens same Buyer Query', 1, 0),
    ('EML-008', 'current', N'Seller Statement + Consignment Stock Report', N'Monthly where Seller has activity, balance or outstanding consignment stock', N'Transactional / no-reply', 0, 0),
    ('EML-009', 'retired', N'Seller Payment Recorded', NULL, N'Routine event appears on monthly Seller statement', 0, 0),
    ('EML-010', 'current_exception_only', N'Seller Payment Reversed', N'Material exceptional Seller payment reversal that should not await monthly statement', N'Transactional / no-reply', 0, 0),
    ('EML-011', 'retired', N'Seller Proceeds Update', NULL, N'Routine changes appear on monthly Seller statement', 0, 0),
    ('EML-012', 'current', N'Auction Won', N'Auction closes with valid winning bid', N'Transactional / no-reply', 0, 0),
    ('EML-013', 'current_optional', N'Outbid Alert', N'Buyer ceases to be leading bidder; 4h cooldown, max 3 per buyer/auction/24h', N'Optional preference', 0, 1),
    ('EML-014', 'retired', N'Seller Auction Result', NULL, N'Do not implement', 0, 0),
    ('EML-015', 'current_scoped', N'Exceptional Cancellation / Missing / Damaged', N'Affected buyer/bidders when exceptional cancellation occurs; Seller Missing notice only on permanent terminal removal/write-off', N'Transactional / no-reply', 0, 0),
    ('EML-016', 'current', N'Combined Shipping Pre-Invoicing Reminder', N'Controlled pre-invoicing Combined Shipping reminder', N'Transactional / no-reply', 0, 0),
    ('EML-017', 'current', N'PHILMART Fees Due', N'PHILMART fee invoice due notice — monthly transaction-fee invoice or Annual Shop Fee invoice', N'Transactional / no-reply; covers both monthly and annual PHILMART fee invoices', 0, 0),
    ('EML-018', 'current', N'PHILMART Fees Overdue', N'Any PHILMART fee invoice overdue after its due date with unpaid balance; include warning about controlled consequences/manual deactivation', N'Transactional / no-reply; covers both monthly and annual PHILMART fee invoices', 0, 0),
    ('EML-019', 'current_reword', N'Buyer Email Verification', N'Buyer starts registration and must verify email to continue', N'Transactional / no-reply; must not say verification completes registration', 0, 0),
    ('EML-020', 'current', N'Buyer Welcome', N'Full Buyer Registration successfully completed', N'Transactional / no-reply', 0, 0),
    ('EML-021', 'current', N'Shop Registration/Application Received', N'Shop Application successfully submitted and awaiting review', N'Transactional / no-reply', 0, 0),
    ('EML-022', 'current_redefined', N'Shop Activated', N'Automatic activation after valid Shop Setup completion', N'Transactional / no-reply', 0, 0),
    ('EML-023', 'retired', N'Shop Setup Incomplete / Trading Blocked', NULL, N'Do not implement', 0, 0),
    ('EML-024', 'pending_not_approved', NULL, NULL, N'Do not implement', 0, 0)
) AS src (Code, Authority, Name, ControlledTrigger, CommunicationRule, ReplyEnabled, IsOptional)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Authority = src.Authority, tgt.Name = src.Name,
     tgt.ControlledTrigger = src.ControlledTrigger,
     tgt.CommunicationRule = src.CommunicationRule,
     tgt.ReplyEnabled = src.ReplyEnabled, tgt.IsOptional = src.IsOptional,
     tgt.UpdatedAt = philmart.ServerNow()
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Authority, Name, ControlledTrigger, CommunicationRule,
             ReplyEnabled, IsOptional)
     VALUES (src.Code, src.Authority, src.Name, src.ControlledTrigger,
             src.CommunicationRule, src.ReplyEnabled, src.IsOptional);
GO

/* ---------------------------------------------------------- legal documents ---
   The DOCUMENT rows only. Buyer registration semantics: ACCEPT the Buyer Terms
   and the Rules of Auction; ACKNOWLEDGE the Privacy Policy version presented.

   Audience uses the literal values CK_ld_audience permits ('Buy_Buyer',
   'Shop_Shop', 'both'). Those spellings look wrong because they are - see the
   naming defect recorded at the end of this file - but the constraint is what
   the database enforces today, so the seed matches it.

   LEGAL-CTL-001 Legal Document Control Register is deliberately absent: it is
   an internal control artefact, not a document any Buyer or Shop accepts.

   NO VERSION ROWS ARE SEEDED HERE. Every wording in the controlled pack is
   DRAFT pending professional legal review, and Sys_LegalDocumentVersion has a
   UNIQUE filtered index allowing exactly one published version per document -
   so seeding a draft as published is one statement away from putting
   unapproved legal wording in front of a real Buyer (Agreement clause 24,
   Production Release gate). The optional loader below inserts the drafts with
   IsDraft = 1 and PublishedAt NULL, verifying each file against the SHA-256 in
   LEGAL_DOCUMENT_MANIFEST.csv first.                                         */
MERGE philmart.Sys_LegalDocument AS tgt
USING (VALUES
    ('LEGAL-BUY-001', N'PHILMART Buyer Terms and Conditions', 'Buy_Buyer', 'accept', N'Accepted at Buyer Registration step 4 of 4 (SCR-PUB-014.3).'),
    ('LEGAL-AUC-001', N'PHILMART Rules of Auction', 'Buy_Buyer', 'accept', N'Accepted at Buyer Registration alongside the Buyer Terms.'),
    ('LEGAL-PRV-001', N'PHILMART Privacy Policy', 'both', 'acknowledge', N'ACKNOWLEDGED, not accepted: the Buyer acknowledges the version presented.'),
    ('LEGAL-DEC-001', N'Buy Now Commitment', 'Buy_Buyer', 'accept', N'Accepted at Confirm Purchase (SCR-PUB-003A).'),
    ('LEGAL-DEC-002', N'Auction Bid Commitment', 'Buy_Buyer', 'accept', N'Accepted at Confirm Bid (SCR-PUB-003B).'),
    ('LEGAL-SHP-001', N'PHILMART Shop Agreement', 'Shop_Shop', 'accept', N'Accepted by the Shop at Review, Sign & Submit (SCR-SHP-003.8A).'),
    ('LEGAL-DEC-003', N'Shop Setup Declaration', 'Shop_Shop', 'accept', N'Signed by the Shop at Review, Sign & Submit (SCR-SHP-003.8A).')
) AS src (Code, Name, Audience, AcceptanceMode, Description)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.Audience = src.Audience,
     tgt.AcceptanceMode = src.AcceptanceMode, tgt.Description = src.Description
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, Audience, AcceptanceMode, Description)
     VALUES (src.Code, src.Name, src.Audience, src.AcceptanceMode, src.Description);
GO

/* ------------------------------------------------------ report definitions ---
   The controlled reports evidenced in the current screen manifest. Audience
   uses the literal values CK_rd_audience permits ('Shop_Shop', 'philmart',
   'both').

   Output formats: pdf is the only format with direct screen evidence - "View
   PDF / Send Statement" (SCR-SHP-009.2), "Statement PDF" (SCR-SHP-015) and the
   printable governance popup (SCR-ADM-008.2). xlsx and csv are NOT seeded for
   any report: D053 permits a platform option only where explicitly justified,
   and no current screen evidences an xlsx or csv export of these reports. Add
   them per report when a controlled decision or screen calls for one.        */
MERGE philmart.Rpt_Definition AS tgt
USING (VALUES
    ('RPT_RESPONSIBLE_PERSON_EXCEPTION', N'Monthly Responsible Person Exception Report', 'philmart', N'D070. Every exceptional condition the responsible person must know about, with summary and drill-through detail. The closed set of kinds is Rpt_GovernanceExceptionKind.', 'SCR-ADM-008.2'),
    ('RPT_MONTHLY_MARKETPLACE', N'Monthly Marketplace Report', 'philmart', N'Platform-wide monthly marketplace activity.', 'SCR-ADM-008.1'),
    ('RPT_EMAIL_DELIVERY_EXCEPTIONS', N'Email Delivery Exceptions', 'philmart', N'NF-12. Controlled communications that bounced or failed, open and resolved.', 'SCR-ADM-008.3'),
    ('RPT_BUYER_STATEMENT', N'Buyer Statement', 'Shop_Shop', N'D022. Buyer account ledger from the most recent nil balance, with a debit/credit running balance.', 'SCR-SHP-009.2'),
    ('RPT_SELLER_STATEMENT_CONSIGNMENT', N'Seller Statement + Consignment Stock Report', 'Shop_Shop', N'D057/D059. Seller financial statement plus all outstanding consignment stock not yet finally fulfilled, returned or written off, with Seller Minimum Price where applicable. Issued monthly as EML-008 to each Seller with activity, a balance or stock still held.', 'SCR-SHP-011.2'),
    ('RPT_PHILMART_FEES_STATEMENT', N'PHILMART Fees Statement', 'Shop_Shop', N'Read-only Shop fee statement. Shop Administrator only.', 'SCR-SHP-015'),
    ('RPT_FEE_INVOICE_SCHEDULE', N'Monthly Fee Invoice Supporting Schedule', 'Shop_Shop', N'D028. The detailed per-transaction schedule that must reconcile to the monthly PHILMART fee invoice.', 'SCR-SHP-015.1')
) AS src (Code, Name, Audience, Description, ScreenRef)
   ON tgt.Code = src.Code
WHEN MATCHED THEN UPDATE SET
     tgt.Name = src.Name, tgt.Audience = src.Audience,
     tgt.Description = src.Description, tgt.ScreenRef = src.ScreenRef
WHEN NOT MATCHED BY TARGET THEN
     INSERT (Code, Name, Audience, Description, ScreenRef)
     VALUES (src.Code, src.Name, src.Audience, src.Description, src.ScreenRef);
GO

MERGE philmart.Rpt_OutputFormat AS tgt
USING (VALUES
    ('RPT_RESPONSIBLE_PERSON_EXCEPTION', 'pdf'),
    ('RPT_MONTHLY_MARKETPLACE', 'pdf'),
    ('RPT_EMAIL_DELIVERY_EXCEPTIONS', 'pdf'),
    ('RPT_BUYER_STATEMENT', 'pdf'),
    ('RPT_SELLER_STATEMENT_CONSIGNMENT', 'pdf'),
    ('RPT_PHILMART_FEES_STATEMENT', 'pdf'),
    ('RPT_FEE_INVOICE_SCHEDULE', 'pdf')
) AS src (ReportCode, Format)
   ON tgt.ReportCode = src.ReportCode AND tgt.Format = src.Format
WHEN NOT MATCHED BY TARGET THEN
     INSERT (ReportCode, Format) VALUES (src.ReportCode, src.Format);
GO

/* --------------------------------------------------- platform configuration ---
   D052/D053. PHILMART Configuration holds ONLY explicit platform options,
   constraints, defaults/fallbacks and mandatory rules, and a value may exist
   here only with a DecisionRef justifying it. Sample values seen in screen
   evidence are NOT business rules and are not seeded.

   Every row cites the decision that puts it here. The thresholds duplicated in
   Philmart.Domain.Constants.PhilmartConstants.Thresholds must match these
   values - configuration is the source of truth, and the constants exist only
   so the application can name them.

   D054: where ShopOverridable = 1, MinValue/MaxValue are the platform bounds
   and Value is the DEFAULT for a new Shop. Changing a default here never
   overwrites a value a Shop has already saved; where a changed range
   invalidates an existing Shop value it is recorded in
   Sys_SettingValidationFlag for correction, never silently altered.

   NOT SEEDED, deliberately: Shop_Settings.DefaultCommissionPct has a 0-100
   check but no controlled default, and the Annual Shop Fee amount is per Shop
   (D073) and lives in Fee_ShopConfig, never here - R0.00 there means WAIVED for
   that Shop, not "no annual fee configured".                                 */
MERGE philmart.Sys_PlatformSetting AS tgt
USING (VALUES
    ('listing.fixed_price_max_live_days', N'90', 'int', 'days', N'Maximum live period of a Fixed Price Listing. At expiry the Listing becomes historical and read-only and the Item returns to Ready to List for deliberate positive relisting.', 'D063', 0, NULL, NULL),
    ('item.ready_to_list_attention_days', N'60', 'int', 'days', N'Age at which a Ready to List Item raises normal Shop attention. Does NOT change the Item state.', 'D061', 0, NULL, NULL),
    ('item.ready_to_list_escalation_days', N'75', 'int', 'days', N'Age at which a Ready to List Item escalates to the responsible person. Does NOT change the Item state.', 'D061', 0, NULL, NULL),
    ('query.awaiting_buyer_auto_close_days', N'14', 'int', 'days', N'Days without a Buyer reply before an Awaiting Buyer query auto-closes. Awaiting Shop NEVER auto-closes, and a later Buyer reply reopens the same query.', 'D069', 0, NULL, NULL),
    ('email.outbid_alert_cooldown_hours', N'4', 'int', 'hours', N'EML-013 Outbid Alert cooldown. Throttling affects email only, never bidding or in-platform state.', 'D068', 0, NULL, NULL),
    ('email.outbid_alert_max_per_24h', N'3', 'int', 'count', N'Maximum EML-013 Outbid Alerts per Buyer per Auction in any 24-hour period.', 'D068', 0, NULL, NULL),
    ('fee.annual_invoice_raise_month_day', N'01-01', 'text', NULL, N'Where an Annual Shop Fee applies, PHILMART raises the annual fee invoice on this month-day. No automatic proration.', 'D075', 0, NULL, NULL),
    ('fee.invoice_due_days.default', N'30', 'int', 'days', N'Default days from issue to due date on a PHILMART fee invoice. The operative value is Fee_ShopConfig.FeeInvoiceDueDays per Shop; these bounds match CK_sfc_due.', 'D030', 0, 1, 180),
    ('shop.paid_item_attention_days', N'7', 'int', 'days', N'Default Paid Item Attention threshold. Shop-controlled via Shop_Settings.PaidItemAttentionDays, subject only to these platform bounds, which match CK_ss_attention. The alert never changes workflow state.', 'D024', 1, 1, 90),
    ('shop.invoice_due_days', N'7', 'int', 'days', N'Default days from issue to due date on a Buyer invoice. Shop-controlled via Shop_Settings.InvoiceDueDays; bounds match CK_ss_due.', 'D019', 1, 1, 90)
) AS src ([key], Value, ValueType, Unit, Description, DecisionRef,
          ShopOverridable, MinValue, MaxValue)
   ON tgt.[key] = src.[key]
WHEN MATCHED THEN UPDATE SET
     tgt.Value = src.Value, tgt.ValueType = src.ValueType, tgt.Unit = src.Unit,
     tgt.Description = src.Description, tgt.DecisionRef = src.DecisionRef,
     tgt.ShopOverridable = src.ShopOverridable,
     tgt.MinValue = src.MinValue, tgt.MaxValue = src.MaxValue,
     tgt.UpdatedAt = philmart.ServerNow()
WHEN NOT MATCHED BY TARGET THEN
     INSERT ([key], Value, ValueType, Unit, Description, DecisionRef,
             ShopOverridable, MinValue, MaxValue)
     VALUES (src.[key], src.Value, src.ValueType, src.Unit, src.Description,
             src.DecisionRef, src.ShopOverridable, src.MinValue, src.MaxValue);
GO

/* ------------------------------------ optional: load DRAFT legal wording ---
   Disabled by default. Set @PackRoot to the absolute path of the developer slim
   pack's legal folder to load the draft bodies, for example:

       SET @PackRoot = N'D:\Raman\PhilMart\PHILMART_DEVELOPER_SLIM_D076_2026-09-17'
                     + N'\PHILMART_DEVELOPER_SLIM\07_PROPOSED_CURRENT_LEGAL';

   Every row is inserted with IsDraft = 1 and PublishedAt NULL, and each file is
   verified against the SHA-256 recorded in LEGAL_DOCUMENT_MANIFEST.csv before
   it is stored. A mismatch aborts: wording that does not match the manifest is
   not the controlled wording. Requires ADMINISTER BULK OPERATIONS and a server
   that can read the path.

   PUBLISHING ANY OF THESE IS A PRODUCTION RELEASE GATE VIOLATION until
   professional legal review completes (Agreement clause 24). The mechanics -
   placement, versioning, acceptance, audit - may be built and tested against
   these drafts now.                                                          */
DECLARE @PackRoot NVARCHAR(400) = NULL;   /* <- set to enable */

IF @PackRoot IS NOT NULL
BEGIN
    DECLARE @files TABLE (DocumentCode VARCHAR(40), Version VARCHAR(20),
                          FileName NVARCHAR(200), ExpectedSha CHAR(64));
    INSERT INTO @files (DocumentCode, Version, FileName, ExpectedSha) VALUES
        ('LEGAL-BUY-001', 'v2-DRAFT', N'LEGAL-BUY-001_PHILMART_Buyer_Terms_and_Conditions_v2_D076_DRAFT.md', '3f57de1d071d1b6a404dd53c623483c9ec0188f627718326d063b765239406c1'),
        ('LEGAL-AUC-001', 'v2-DRAFT', N'LEGAL-AUC-001_PHILMART_Rules_of_Auction_v2_D076_DRAFT.md', '05ab64f699992c258e849d9789935b9f9f19bee044579790e504d0e62795e605'),
        ('LEGAL-PRV-001', 'v2-DRAFT', N'LEGAL-PRV-001_PHILMART_Privacy_Policy_v2_D076_DRAFT.md', 'f3138744f8df29d053c4dc3a48227e955794cd761851667d9b1b65f52b0a8dec'),
        ('LEGAL-DEC-001', 'v2-DRAFT', N'LEGAL-DEC-001_Buy_Now_Commitment_v2_DRAFT.md', 'ab650ef2679745930a66f72cd4b51ddf662b65365c330501c11b2e758c2b2865'),
        ('LEGAL-DEC-002', 'v2-DRAFT', N'LEGAL-DEC-002_Auction_Bid_Commitment_v2_DRAFT.md', '22ededd28e7842c0ab1fe15c9e9e97452855c8333a5250aedc2a6ec940f09108'),
        ('LEGAL-SHP-001', 'v2-DRAFT', N'LEGAL-SHP-001_PHILMART_Shop_Agreement_v2_D076_DRAFT.md', '8881aa14d5cd9329f2ba4eae47499020b2f0659514ff978799712097baf53cdb'),
        ('LEGAL-DEC-003', 'v2-DRAFT', N'LEGAL-DEC-003_Shop_Setup_Declaration_v2_DRAFT.md', '6d1c727440799f4b7b07a3f9673f69ab06d375249fdcc59e7d4b20aa55abed01');

    DECLARE @code VARCHAR(40), @ver VARCHAR(20), @file NVARCHAR(200), @sha CHAR(64);
    DECLARE @path NVARCHAR(700), @sql NVARCHAR(MAX);
    DECLARE @blob VARBINARY(MAX), @body NVARCHAR(MAX);

    DECLARE legal_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT DocumentCode, Version, FileName, ExpectedSha FROM @files;
    OPEN legal_cur;
    FETCH NEXT FROM legal_cur INTO @code, @ver, @file, @sha;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @path = @PackRoot + N'\' + @file;
        /* OPENROWSET requires a literal path, hence dynamic SQL. */
        SET @sql = N'SELECT @b = BulkColumn FROM OPENROWSET(BULK '''
                 + REPLACE(@path, '''', '''''') + N''', SINGLE_BLOB) AS x;';
        EXEC sys.sp_executesql @sql, N'@b VARBINARY(MAX) OUTPUT', @b = @blob OUTPUT;

        IF LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', @blob), 2)) <> LOWER(@sha)
        BEGIN
            CLOSE legal_cur; DEALLOCATE legal_cur;
            THROW 50101, 'A legal draft file does not match LEGAL_DOCUMENT_MANIFEST.csv. Refusing to store uncontrolled wording.', 1;
        END;

        /* The controlled files are UTF-8; decode through a UTF-8 collation. */
        SET @body = CAST(CAST(@blob AS VARCHAR(MAX))
                         COLLATE Latin1_General_100_CI_AS_SC_UTF8 AS NVARCHAR(MAX));

        IF NOT EXISTS (SELECT 1 FROM philmart.Sys_LegalDocumentVersion
                        WHERE DocumentCode = @code AND Version = @ver)
            INSERT INTO philmart.Sys_LegalDocumentVersion
                   (DocumentCode, Version, Body, ContentSha256, IsDraft, PublishedAt)
            VALUES (@code, @ver, @body, LOWER(@sha), 1, NULL);

        FETCH NEXT FROM legal_cur INTO @code, @ver, @file, @sha;
    END;

    CLOSE legal_cur; DEALLOCATE legal_cur;
END;
GO

/* -------------------------------------------------------------- verification ---
   Fails loudly rather than leaving a half-seeded database looking healthy.
   NVARCHAR(2048) because THROW will not accept a wider message parameter.   */
DECLARE @err NVARCHAR(2048) = N'';

IF (SELECT COUNT(*) FROM philmart.Sys_Permission) < 26
    SET @err = @err + N'Sys_Permission: expected at least 26 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_Permission) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Shop_SetupSection) < 8
    SET @err = @err + N'Shop_SetupSection: expected at least 8 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Shop_SetupSection) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationType) < 7
    SET @err = @err + N'Sys_ClassificationType: expected at least 7 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationType) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationSubtype) < 60
    SET @err = @err + N'Sys_ClassificationSubtype: expected at least 60 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationSubtype) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationTheme) < 32
    SET @err = @err + N'Sys_ClassificationTheme: expected at least 32 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationTheme) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationFormat) < 37
    SET @err = @err + N'Sys_ClassificationFormat: expected at least 37 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationFormat) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationStampState) < 7
    SET @err = @err + N'Sys_ClassificationStampState: expected at least 7 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationStampState) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationAreaCountry) < 516
    SET @err = @err + N'Sys_ClassificationAreaCountry: expected at least 516 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationAreaCountry) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_EmailTemplate) < 24
    SET @err = @err + N'Sys_EmailTemplate: expected at least 24 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_EmailTemplate) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_LegalDocument) < 7
    SET @err = @err + N'Sys_LegalDocument: expected at least 7 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_LegalDocument) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Rpt_Definition) < 7
    SET @err = @err + N'Rpt_Definition: expected at least 7 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Rpt_Definition) AS NVARCHAR(20)) + N'. ';
IF (SELECT COUNT(*) FROM philmart.Sys_PlatformSetting) < 10
    SET @err = @err + N'Sys_PlatformSetting: expected at least 10 rows, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_PlatformSetting) AS NVARCHAR(20)) + N'. ';

/* The auto-activation guard is only a guard while a mandatory section exists. */
IF NOT EXISTS (SELECT 1 FROM philmart.Shop_SetupSection WHERE Mandatory = 1)
    SET @err = @err + N'Shop_SetupSection has no mandatory row: '
             + N'TR_shop_setup_auto_activation would activate every Shop on its '
             + N'first setup write. ';

/* Every Area/Country node but the roots must have resolved a parent. */
IF (SELECT COUNT(*) FROM philmart.Sys_ClassificationAreaCountry WHERE ParentID IS NULL) <> 7
    SET @err = @err + N'Area/Country root count is wrong: expected 7 nodes with '
             + N'no parent, found '
             + CAST((SELECT COUNT(*) FROM philmart.Sys_ClassificationAreaCountry
                      WHERE ParentID IS NULL) AS NVARCHAR(20))
             + N'. The hierarchy wiring did not complete. ';

/* A retired template must never come back as current. */
IF EXISTS (SELECT 1 FROM philmart.Sys_EmailTemplate
            WHERE Code IN ('EML-006','EML-009','EML-011','EML-014','EML-023')
              AND Authority <> 'retired')
    SET @err = @err + N'A retired email template is not marked retired (D060). ';

IF EXISTS (SELECT 1 FROM philmart.Sys_EmailTemplate
            WHERE Code = 'EML-024' AND Authority <> 'pending_not_approved')
    SET @err = @err + N'EML-024 must remain pending_not_approved (D060). ';

/* D007: Custom and Deferred Delivery are retired and must not be selectable. */
IF EXISTS (SELECT 1 FROM philmart.Sys_DeliveryMethod WHERE Code IN ('CUSTOM','DEFERRED'))
    SET @err = @err + N'A retired delivery method is present (D007). ';

/* Draft legal wording must never be seeded as published. */
IF EXISTS (SELECT 1 FROM philmart.Sys_LegalDocumentVersion
            WHERE IsDraft = 1 AND PublishedAt IS NOT NULL)
    SET @err = @err + N'A DRAFT legal version is marked published (Agreement clause 24). ';

IF LEN(@err) > 0 THROW 50102, @err, 1;
GO

PRINT 'PHILMART 010_seed: controlled reference seed loaded and verified.';
GO

/* ===========================================================================
   NOT SEEDED HERE - and why. Each of these is a real gap, not an oversight.

   philmart.Sys_DeliveryMethod / Sys_DeliveryTariff / Sys_PickupPoint
       No controlled list of named delivery methods exists anywhere in the D076
       pack. The decisions define the CONCEPT and retire Custom and Deferred
       Delivery (D007); SCR-ADM-007.2 "Delivery Methods" is the PHILMART
       administration screen through which the real list is maintained.
       Inventing courier names here would breach D052/D053 - a platform option
       exists only where explicitly justified.
       CONSEQUENCE: Shop Setup stage 4 (DELIVERY_METHODS) cannot be completed,
       so no Shop can activate, until PHILMART loads the real methods. That is
       the correct failure: it blocks on missing controlled data rather than
       trading on invented data.

   philmart.Sys_ItemCondition
       Genuinely unsourced. The classification master seed covers Area/Country,
       Type, Subtype, Format, Stamp State and Theme - Condition is not among
       them, and no decision D001-D076 defines its values.
       Sys_ClassificationStampState (Mint Never Hinged, Used, ...) is a
       DIFFERENT axis and is not a substitute. Item_Item.ConditionID is
       nullable so the schema tolerates this, but the values need a controlled
       decision before the field can be used.

   philmart.Sys_PlatformUser
       A bootstrap platform administrator needs a real PasswordHash and, per the
       schema's intent, an MfaSecret. Putting a known hash in a migration that
       ships in source control creates a default credential on every
       environment. Create the first administrator as a deployment step, then
       set IsResponsiblePerson (D070/D061) on the person who actually holds
       that role.

   philmart.Sys_EnumValue, Item_TransitionRule, Rpt_GovernanceExceptionKind
       Already seeded inline by 001, 004 and 008 respectively. Re-seeding them
       here would fight the migration that owns them.

   -------------------------------------------------------------------------
   DEFECTS OBSERVED WHILE WRITING THIS SEED - not fixed here, because fixing
   them changes the shipped schema and the application contract together.

   1. Identifier corruption inside string LITERALS in 001-009. A table-name
      find/replace has rewritten values inside quoted strings and CHECK
      constraints, so the database now enforces:
          CK_audit_actor_kind      IN ('anonymous','Buy_Buyer','Shop_User',...)
          CK_ld_audience           IN ('Buy_Buyer','Shop_Shop','both')
          CK_rd_audience           IN ('Shop_Shop','philmart','both')
          CK_audit_reason_required 'Item_Item.removed_from_stock.other',
                                   'Sell_Payment.reversed',
                                   'Sale_Invoice.cancelled'
      while Philmart.Domain.Constants.PhilmartConstants sends 'buyer',
      'shop_user', 'shop', 'item.removed_from_stock.other',
      'seller_payment.reversed' and 'invoice.cancelled'. Every audit write and
      every legal or report insert from the API will fail its CHECK constraint
      at runtime. philmart.Sys_EnumValue carries the same corrupted values
      (enum 'actor_kind' -> 'Buy_Buyer'), and MS_Description prose is affected
      throughout. This seed matches the constraints AS THEY ARE so that it
      runs; a migration must reconcile the two sides, and the API and database
      have to change together.

   2. Sys_ClassificationFormat cannot express Type applicability, and
      Sys_ClassificationStampState cannot express its restriction to
      Type = Stamp / Issue. Both are controlled rules in the classification
      master with nowhere to live in the schema. See the Format section above.

   3. There is no alias table. The controlled master carries 359 aliases over
      283 Area/Country nodes and requires deterministic resolution to a single
      canonical node. Catalogue search cannot meet that rule until one exists.
=========================================================================== */

PRINT '';
PRINT 'PHILMART: database build complete.';
GO
