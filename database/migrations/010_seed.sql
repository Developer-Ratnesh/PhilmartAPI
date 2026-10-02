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
