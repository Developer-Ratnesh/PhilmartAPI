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
