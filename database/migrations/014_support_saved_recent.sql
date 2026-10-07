/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 14 : PHILMART support requests, saved items and recently viewed

   BR-02 lists three screens the controlled schema has no tables for:

   SCR-PUB-015  PHILMART Support Form and Confirmation (BR-02-R07). A public
                visitor or a signed-in buyer sends PHILMART an enquiry and gets
                a reference back. The screen says the support record is the
                authoritative copy and any email is only a copy, so the record
                can't be edited or deleted once it's in.
   SCR-PUB-009  Saved Items. A buyer keeps listings to come back to.
   SCR-PUB-008  Recently Viewed Items. The listings a buyer looked at last.

   Saved and recently viewed rows belong to one buyer and sit behind
   BuyerSelfPolicy like the buyer's addresses do. "Remove" on those screens
   sets RemovedAt, because DELETE is denied on the schema.

   The 100 on the Saved Items screen is a sample value, not a limit (D053).
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO philmart.Sys_EnumValue (EnumName, Value, SortOrder, DecisionRef, Note) VALUES
 ('support_category','account',   1,NULL,N'My account and signing in'),
 ('support_category','buying',    2,NULL,N'Buying and bidding'),
 ('support_category','payments',  3,NULL,N'Invoices and payments'),
 ('support_category','delivery',  4,NULL,N'Delivery and collection'),
 ('support_category','shops',     5,NULL,N'Opening a Shop'),
 ('support_category','technical', 6,NULL,N'Problem with the website'),
 ('support_category','other',     7,NULL,N'Something else'),
 ('support_status','open',  1,NULL,NULL),
 ('support_status','closed',2,NULL,NULL);
GO

CREATE SEQUENCE philmart.SEQ_Sys_SupportRequest AS INT START WITH 1 INCREMENT BY 1 NO CYCLE;
GO

CREATE TABLE philmart.Sys_SupportRequest (
    ID                UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_sr_id DEFAULT NEWSEQUENTIALID()
                                       CONSTRAINT PK_support_request PRIMARY KEY,
    Reference         VARCHAR(40)      NOT NULL CONSTRAINT UQ_sr_reference UNIQUE,
    Category          VARCHAR(30)      NOT NULL,
    Subject           NVARCHAR(400)    NOT NULL,
    RelatedReference  VARCHAR(60)      NULL,     -- PHILMART No. or invoice number, optional
    Message           NVARCHAR(4000)   NOT NULL,
    BuyerID           UNIQUEIDENTIFIER NULL CONSTRAINT FK_sr_buyer REFERENCES philmart.Buy_Buyer(ID),
    ContactName       NVARCHAR(200)    NOT NULL,
    ContactEmail      NVARCHAR(256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    Status            VARCHAR(20)      NOT NULL CONSTRAINT DF_sr_status DEFAULT ('open'),
    SubmittedAt       DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_sr_submitted DEFAULT (philmart.ServerNow()),
    ClosedAt          DATETIMEOFFSET(7) NULL,
    ClosedBy          UNIQUEIDENTIFIER NULL,
    CONSTRAINT CK_sr_category CHECK (Category IN
        ('account','buying','payments','delivery','shops','technical','other')),
    CONSTRAINT CK_sr_status CHECK (Status IN ('open','closed')),
    CONSTRAINT CK_sr_closed CHECK ((Status = 'open' AND ClosedAt IS NULL) OR (Status = 'closed' AND ClosedAt IS NOT NULL)),
    CONSTRAINT CK_sr_subject CHECK (LEN(LTRIM(RTRIM(Subject))) > 0),
    CONSTRAINT CK_sr_message CHECK (LEN(LTRIM(RTRIM(Message))) > 0)
);
GO

CREATE INDEX IX_sr_open ON philmart.Sys_SupportRequest (SubmittedAt) WHERE Status = 'open';
CREATE INDEX IX_sr_buyer ON philmart.Sys_SupportRequest (BuyerID) WHERE BuyerID IS NOT NULL;
GO

-- the request itself never changes, only its status
CREATE TRIGGER philmart.TR_support_request_immutable
ON philmart.Sys_SupportRequest
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        THROW 50042, 'A PHILMART support request is a permanent record and can''t be deleted.', 1;

    IF EXISTS (
        SELECT 1 FROM inserted AS i JOIN deleted AS d ON d.ID = i.ID
        WHERE i.Reference <> d.Reference OR i.Category <> d.Category OR i.Subject <> d.Subject
           OR ISNULL(i.RelatedReference, '') <> ISNULL(d.RelatedReference, '')
           OR i.Message <> d.Message OR ISNULL(CAST(i.BuyerID AS VARCHAR(36)), '') <> ISNULL(CAST(d.BuyerID AS VARCHAR(36)), '')
           OR i.ContactName <> d.ContactName OR i.ContactEmail <> d.ContactEmail OR i.SubmittedAt <> d.SubmittedAt)
        THROW 50042, 'A PHILMART support request can''t be changed after it''s submitted. Only its status can move.', 1;
END;
GO

CREATE TABLE philmart.Buy_SavedItem (
    ID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_bsi_id DEFAULT NEWSEQUENTIALID()
                                 CONSTRAINT PK_buyer_saved_item PRIMARY KEY,
    BuyerID     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bsi_buyer REFERENCES philmart.Buy_Buyer(ID),
    ListingID   UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_bsi_listing REFERENCES philmart.List_Listing(ID),
    SavedAt     DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_bsi_saved DEFAULT (philmart.ServerNow()),
    RemovedAt   DATETIMEOFFSET(7) NULL,
    CONSTRAINT CK_bsi_removed CHECK (RemovedAt IS NULL OR RemovedAt >= SavedAt)
);
GO

-- saving again after a remove adds a new row
CREATE UNIQUE INDEX UX_bsi_one_active ON philmart.Buy_SavedItem (BuyerID, ListingID) WHERE RemovedAt IS NULL;
CREATE INDEX IX_bsi_buyer ON philmart.Buy_SavedItem (BuyerID, SavedAt DESC) WHERE RemovedAt IS NULL;
GO

CREATE TABLE philmart.Buy_RecentlyViewed (
    ID             UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_brv_id DEFAULT NEWSEQUENTIALID()
                                    CONSTRAINT PK_buyer_recently_viewed PRIMARY KEY,
    BuyerID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_brv_buyer REFERENCES philmart.Buy_Buyer(ID),
    ListingID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_brv_listing REFERENCES philmart.List_Listing(ID),
    FirstViewedAt  DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_brv_first DEFAULT (philmart.ServerNow()),
    LastViewedAt   DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_brv_last DEFAULT (philmart.ServerNow()),
    RemovedAt      DATETIMEOFFSET(7) NULL,
    CONSTRAINT CK_brv_order CHECK (LastViewedAt >= FirstViewedAt)
);
GO

CREATE UNIQUE INDEX UX_brv_one_active ON philmart.Buy_RecentlyViewed (BuyerID, ListingID) WHERE RemovedAt IS NULL;
CREATE INDEX IX_brv_buyer ON philmart.Buy_RecentlyViewed (BuyerID, LastViewedAt DESC) WHERE RemovedAt IS NULL;
GO

ALTER SECURITY POLICY philmart.BuyerSelfPolicy
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_SavedItem,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_SavedItem,
    ADD FILTER PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_RecentlyViewed,
    ADD BLOCK  PREDICATE philmart.FN_BuyerSelfPredicate(BuyerID) ON philmart.Buy_RecentlyViewed;
GO

PRINT 'PHILMART 014: support requests, saved items and recently viewed added.';
GO
