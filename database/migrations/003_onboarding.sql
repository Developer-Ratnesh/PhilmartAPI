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
