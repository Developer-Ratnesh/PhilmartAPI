/* ===========================================================================
   DEVELOPMENT AND DEMO DATA ONLY. Never run this against staging or production.
   Not a migration, migrate.sh doesn't touch it.

   Gives a local database enough to try M2 end to end: two active Shops with
   users, delivery methods, items, a fixed price listing and auctions, a
   platform admin, and published legal documents.

   The legal document bodies below are placeholders. The real wording has to
   come from the Client. Delivery methods are PHILMART reference data that the
   admin screen (SCR-ADM-007.2) will maintain, these are just examples.

   Every login below uses the password  Philmart-dev-1

   Run:  sqlcmd -S localhost -E -C -I -f 65001 -d PhilmartDev -i database/dev/seed_demo.sql
   Safe to re-run: it does nothing if the demo Shop is already there.
=========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM philmart.Shop_Shop WHERE Reference = 'DEMO-001')
BEGIN
    PRINT 'Demo data already loaded.';
    RETURN;
END;

-- every Shop table is behind RLS
EXEC sp_set_session_context N'philmart.actor_kind', N'system';

DECLARE @hash VARCHAR(255) = 'AQAAAAIAAYagAAAAEN6U12obQWxtrYvgLX0ez0QYW+qG944NlnfQe22CwAG9s/tXHJSjPBYDwfIslw3mug==';
DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();

BEGIN TRANSACTION;

-- legal documents, placeholder text
INSERT INTO philmart.Sys_LegalDocumentVersion (DocumentCode, Version, Body, ContentSha256, IsDraft, PublishedAt, ApprovedBy)
SELECT d.Code, '0.1-dev',
       N'DEVELOPMENT PLACEHOLDER. This is not the PHILMART ' + d.Name + N'. The Client supplies the controlled wording.',
       CONVERT(CHAR(64), HASHBYTES('SHA2_256', N'DEVELOPMENT PLACEHOLDER ' + d.Code), 2),
       0, @now, N'development seed'
FROM philmart.Sys_LegalDocument d;

-- delivery methods and pickup points
DECLARE @courier UNIQUEIDENTIFIER = NEWID(), @pickup UNIQUEIDENTIFIER = NEWID(), @collect UNIQUEIDENTIFIER = NEWID();

INSERT INTO philmart.Sys_DeliveryMethod (ID, Code, Name, MethodKind, RequiresPickupPoint, RequiresAddress, SortOrder) VALUES
    (@courier, 'COURIER_DOOR', N'Courier to your door', 'shipping', 0, 1, 1),
    (@pickup,  'PICKUP_POINT', N'Pickup point delivery', 'shipping', 1, 0, 2),
    (@collect, 'SHOP_COLLECT', N'Collect from the Shop', 'collection', 0, 0, 3);

INSERT INTO philmart.Sys_PickupPoint (DeliveryMethodID, Code, Name, AddressLine1, City, Province, PostalCode) VALUES
    (@pickup, 'PP-CPT-01', N'Cape Town CBD pickup', N'12 Long Street', N'Cape Town', N'Western Cape', '8001'),
    (@pickup, 'PP-JHB-01', N'Rosebank pickup', N'5 Cradock Avenue', N'Johannesburg', N'Gauteng', '2196');

-- platform admin
INSERT INTO philmart.Sys_PlatformUser (Email, FullName, PasswordHash, IsResponsiblePerson)
VALUES (N'admin@philmart.test', N'Demo Admin', @hash, 1);

-- two Shops, so isolation can be tried
DECLARE @shopA UNIQUEIDENTIFIER = NEWID(), @shopB UNIQUEIDENTIFIER = NEWID();

INSERT INTO philmart.Shop_Shop (ID, Reference, TradingName, Status, SetupAccessGrantedAt, ActivatedAt) VALUES
    (@shopA, 'DEMO-001', N'Cape Stamp Traders', 'active', @now, @now),
    (@shopB, 'DEMO-002', N'Highveld Philatelics', 'active', @now, @now);

DECLARE @adminA UNIQUEIDENTIFIER = NEWID(), @staffA UNIQUEIDENTIFIER = NEWID(), @adminB UNIQUEIDENTIFIER = NEWID();

INSERT INTO philmart.Shop_User (ID, ShopID, Email, FullName, PasswordHash, IsAdministrator, AcceptedAt) VALUES
    (@adminA, @shopA, N'owner@capestamps.test', N'Anna Owner', @hash, 1, @now),
    (@staffA, @shopA, N'staff@capestamps.test', N'Sipho Staff', @hash, 0, @now),
    (@adminB, @shopB, N'owner@highveld.test', N'Ben Owner', @hash, 1, @now);

-- staff get a few direct grants (D050, no roles)
INSERT INTO philmart.Shop_UserPermission (ShopUserID, PermissionCode, ShopID, GrantedBy) VALUES
    (@staffA, 'item.view', @shopA, @adminA),
    (@staffA, 'listing.view', @shopA, @adminA),
    (@staffA, 'auction.manage', @shopA, @adminA);

INSERT INTO philmart.Shop_DeliveryMethod (ShopID, DeliveryMethodID, Enabled) VALUES
    (@shopA, @courier, 1), (@shopA, @pickup, 1), (@shopA, @collect, 1),
    (@shopB, @courier, 1), (@shopB, @collect, 1);

-- items and listings
DECLARE @stamp UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationType WHERE Code = 'STAMP_ISSUE');
DECLARE @cover UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationType WHERE Code = 'COVER');
DECLARE @africa UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationAreaCountry WHERE Code = 'AFRICA');

DECLARE @i1 UNIQUEIDENTIFIER = NEWID(), @i2 UNIQUEIDENTIFIER = NEWID(), @i3 UNIQUEIDENTIFIER = NEWID(),
        @i4 UNIQUEIDENTIFIER = NEWID(), @i5 UNIQUEIDENTIFIER = NEWID(), @i6 UNIQUEIDENTIFIER = NEWID();

INSERT INTO philmart.Item_Item (ID, ShopID, Reference, Title, Description, TypeID, AreaCountryID, State, ReadyToListSince) VALUES
    (@i1, @shopA, 'CST-0001', N'Union of South Africa 1910 2½d Coronation, mint', N'Lightly hinged, good colour.', @stamp, @africa, 'listed', NULL),
    (@i2, @shopA, 'CST-0002', N'1926 London printing 1d pair, used', N'Bilingual pair, clear cancel.', @stamp, @africa, 'listed', NULL),
    (@i3, @shopA, 'CST-0003', N'1947 Royal Visit first day cover', N'Cape Town cancel, clean cover.', @cover, @africa, 'listed', NULL),
    (@i4, @shopA, 'CST-0004', N'1961 Republic definitives, part set', NULL, @stamp, @africa, 'ready_to_list', @now),
    (@i5, @shopB, 'HVP-0001', N'1935 Silver Jubilee set, mint', N'Full set of four.', @stamp, @africa, 'listed', NULL),
    (@i6, @shopB, 'HVP-0002', N'Transvaal 1895 penny, used', NULL, @stamp, @africa, 'listed', NULL);

INSERT INTO philmart.List_Listing (ShopID, ItemID, ListingType, State, Reference, PriceMinor, ListedAt, ExpiresAt) VALUES
    (@shopA, @i1, 'fixed_price', 'live', 'L-CST-0001', 45000, @now, DATEADD(DAY, 60, @now)),
    (@shopB, @i5, 'fixed_price', 'live', 'L-HVP-0001', 120000, @now, DATEADD(DAY, 60, @now));

-- auctions: one closing in 10 minutes with a 2 minute soft close, one running a day
INSERT INTO philmart.List_Listing (ShopID, ItemID, ListingType, State, Reference, StartingPriceMinor, BidIncrementMinor,
                                   StartsAt, EndsAt, SoftCloseSeconds, SoftCloseExtensionSeconds) VALUES
    (@shopA, @i2, 'auction', 'live', 'A-CST-0002', 10000, 500, DATEADD(HOUR, -1, @now), DATEADD(MINUTE, 10, @now), 120, 120),
    (@shopA, @i3, 'auction', 'live', 'A-CST-0003', 25000, 1000, DATEADD(HOUR, -1, @now), DATEADD(DAY, 1, @now), 120, 120),
    (@shopB, @i6, 'auction', 'live', 'A-HVP-0002', 5000, 500, DATEADD(HOUR, -1, @now), DATEADD(DAY, 2, @now), 120, 120);

COMMIT;

PRINT 'Demo data loaded. Password for every login: Philmart-dev-1';
PRINT '  admin@philmart.test       PHILMART admin';
PRINT '  owner@capestamps.test     Shop admin, Cape Stamp Traders (DEMO-001)';
PRINT '  staff@capestamps.test     Shop staff with item.view, listing.view, auction.manage';
PRINT '  owner@highveld.test       Shop admin, Highveld Philatelics (DEMO-002)';
PRINT 'Register a buyer through the site.';
