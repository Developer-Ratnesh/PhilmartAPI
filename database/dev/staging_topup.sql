/* ===========================================================================
   DEMO DATA TOP-UP for staging and local. Not a migration, migrate.sh doesn't
   touch it. Needs seed_demo.sql (the two demo Shops) to have run first.

   Testing uses demo listings up: Buy Now sells them, auctions close. Each run
   adds a fresh batch of live listings to the two demo Shops:

     per Shop  4 Buy Now listings, live for 60 days
               3 auctions, live now, ending in 3, 7 and 14 days

   References carry the batch time (yyMMddHHmm) so runs never clash, e.g.
   CST-2610091530-01 and L-CST-2610091530-01. Items CST-0004 and the other
   Ready to List stock are left alone for the "create an auction" checks.

   Run:  sqlcmd -S <server> -d <database> -U <login> -P <password> -C -I -f 65001 -i database/dev/staging_topup.sql
=========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

EXEC sp_set_session_context N'philmart.actor_kind', N'system';

DECLARE @shopA UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Shop_Shop WHERE Reference = 'DEMO-001' AND Status = 'active');
DECLARE @shopB UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Shop_Shop WHERE Reference = 'DEMO-002' AND Status = 'active');

IF @shopA IS NULL OR @shopB IS NULL
BEGIN
    PRINT 'DEMO-001 and DEMO-002 must exist and be active. Run seed_demo.sql first.';
    RETURN;
END;

DECLARE @now DATETIMEOFFSET(7) = philmart.ServerNow();
DECLARE @batch VARCHAR(10) = FORMAT(@now, 'yyMMddHHmm');

IF EXISTS (SELECT 1 FROM philmart.Item_Item WHERE Reference LIKE '%-' + @batch + '-%')
BEGIN
    PRINT 'A batch was already loaded this minute. Wait a minute and run again.';
    RETURN;
END;

DECLARE @stamp UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationType WHERE Code = 'STAMP_ISSUE');
DECLARE @cover UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationType WHERE Code = 'COVER');
DECLARE @stationery UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationType WHERE Code = 'POSTAL_STATIONERY');
DECLARE @africa UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Sys_ClassificationAreaCountry WHERE Code = 'AFRICA');

-- Kind: B = Buy Now, A = auction. Price is the Buy Now price or the auction
-- starting price, Step the bid increment, Days how long the auction runs.
DECLARE @batchItems TABLE (
    Seq INT IDENTITY(1, 1),
    ShopID UNIQUEIDENTIFIER, Prefix VARCHAR(3), Num INT, Kind CHAR(1),
    Title NVARCHAR(400), Description NVARCHAR(400), TypeID UNIQUEIDENTIFIER,
    PriceMinor BIGINT, StepMinor BIGINT, Days INT,
    ItemID UNIQUEIDENTIFIER DEFAULT NEWID());

INSERT INTO @batchItems (ShopID, Prefix, Num, Kind, Title, Description, TypeID, PriceMinor, StepMinor, Days) VALUES
    (@shopA, 'CST', 1, 'B', N'Union of South Africa 1910 2½d Coronation, mint', N'Lightly hinged, good colour.', @stamp, 45000, NULL, NULL),
    (@shopA, 'CST', 2, 'B', N'1926 London printing ½d pair, mint', N'Bilingual pair, fresh gum.', @stamp, 18000, NULL, NULL),
    (@shopA, 'CST', 3, 'B', N'1953 Coronation 2d single, mint', N'Never hinged.', @stamp, 2500, NULL, NULL),
    (@shopA, 'CST', 4, 'B', N'1952 Van Riebeeck Tercentenary first day cover', N'Cape Town cancel, addressed.', @cover, 9500, NULL, NULL),
    (@shopA, 'CST', 5, 'A', N'1930 Kingsway 1s pair, used', N'Good perforations, light cancel.', @stamp, 15000, 500, 3),
    (@shopA, 'CST', 6, 'A', N'1949 UPU Anniversary set, mint', N'Three values in bilingual pairs.', @stamp, 30000, 1000, 7),
    (@shopA, 'CST', 7, 'A', N'1938 Voortrekker Centenary cover, registered', N'Pretoria to Cape Town, registration label intact.', @cover, 40000, 2000, 14),
    (@shopB, 'HVP', 1, 'B', N'1935 Silver Jubilee set, mint', N'Full set of four.', @stamp, 120000, NULL, NULL),
    (@shopB, 'HVP', 2, 'B', N'Transvaal 1885 ½d grey, mint', N'Small hinge remnant.', @stamp, 6000, NULL, NULL),
    (@shopB, 'HVP', 3, 'B', N'Orange River Colony 1903 1d postal card', N'Unused, clean.', @stationery, 8500, NULL, NULL),
    (@shopB, 'HVP', 4, 'B', N'1961 Republic first day cover, Johannesburg', N'Full set on cover.', @cover, 12000, NULL, NULL),
    (@shopB, 'HVP', 5, 'A', N'Natal 1874 1d red, used', N'Clear numeral cancel.', @stamp, 7500, 500, 3),
    (@shopB, 'HVP', 6, 'A', N'Cape of Good Hope 1864 triangular 1d, used', N'Four margins, light crease.', @stamp, 250000, 10000, 7),
    (@shopB, 'HVP', 7, 'A', N'1925 Airmail set on flight cover', N'Cape Town to Durban first flight.', @cover, 60000, 2000, 14);

BEGIN TRANSACTION;

INSERT INTO philmart.Item_Item (ID, ShopID, Reference, Title, Description, TypeID, AreaCountryID, State, ReadyToListSince)
SELECT ItemID, ShopID, Prefix + '-' + @batch + '-' + FORMAT(Num, '00'), Title, Description, TypeID, @africa, 'listed', NULL
FROM @batchItems;

INSERT INTO philmart.List_Listing (ShopID, ItemID, ListingType, State, Reference, PriceMinor, ListedAt, ExpiresAt)
SELECT ShopID, ItemID, 'fixed_price', 'live', 'L-' + Prefix + '-' + @batch + '-' + FORMAT(Num, '00'),
       PriceMinor, @now, DATEADD(DAY, 60, @now)
FROM @batchItems
WHERE Kind = 'B';

INSERT INTO philmart.List_Listing (ShopID, ItemID, ListingType, State, Reference, StartingPriceMinor, BidIncrementMinor,
                                   StartsAt, EndsAt, OriginalEndsAt, SoftCloseSeconds, SoftCloseExtensionSeconds)
SELECT ShopID, ItemID, 'auction', 'live', 'A-' + Prefix + '-' + @batch + '-' + FORMAT(Num, '00'),
       PriceMinor, StepMinor, DATEADD(MINUTE, -5, @now), DATEADD(DAY, Days, @now), DATEADD(DAY, Days, @now), 120, 120
FROM @batchItems
WHERE Kind = 'A';

COMMIT;

SELECT l.Reference, s.TradingName AS Shop, i.Title,
       CASE l.ListingType WHEN 'fixed_price' THEN 'Buy Now' ELSE 'Auction' END AS Kind,
       FORMAT(COALESCE(l.PriceMinor, l.StartingPriceMinor) / 100.0, 'N2') AS PriceRand,
       FORMAT(l.BidIncrementMinor / 100.0, 'N2') AS StepRand,
       COALESCE(l.EndsAt, l.ExpiresAt) AS Ends
FROM philmart.List_Listing AS l
JOIN philmart.Item_Item AS i ON i.ID = l.ItemID
JOIN philmart.Shop_Shop AS s ON s.ID = l.ShopID
WHERE l.Reference LIKE '%-' + @batch + '-%'
ORDER BY s.Reference, l.Reference;

PRINT 'Batch ' + @batch + ' loaded: 8 Buy Now listings and 6 auctions.';
