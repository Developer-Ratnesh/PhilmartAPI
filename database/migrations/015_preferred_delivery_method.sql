/* ===========================================================================
   PHILMART V1 - MS SQL Server
   Part 15 : the buyer's preferred delivery method

   D009/D037 record, per delivery method, whether it is available where the
   buyer lives and the default pickup point or address for it. Registration
   Step 3 also asks the buyer to pick a preferred shipping method (M2 test
   checklist R.6), and the item page pre-fills it (B.4). Nothing held that
   choice, so the item page fell back to the Shop's first method.

   One preferred method per buyer, and it has to be one they marked available.
   The buyer can still choose any method the Shop offers at purchase (D009).
   Additive only: an older API that doesn't know the column is unaffected.
=========================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER TABLE philmart.Buy_ShippingPreference
    ADD IsPreferred BIT NOT NULL CONSTRAINT DF_bsp_preferred DEFAULT (0);
GO

ALTER TABLE philmart.Buy_ShippingPreference
    ADD CONSTRAINT CK_bsp_preferred_available CHECK (IsPreferred = 0 OR Available = 1);
GO

CREATE UNIQUE INDEX UX_bsp_one_preferred ON philmart.Buy_ShippingPreference (BuyerID)
    WHERE IsPreferred = 1;
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description',
 @value=N'The method pre-selected for this buyer at Buy Now and Confirm Bid (checklist R.6/B.4). At most one per buyer, and only an available one. A choice at purchase applies to that purchase only (D041).',
 @level0type=N'SCHEMA',@level0name=N'philmart',@level1type=N'TABLE',@level1name=N'Buy_ShippingPreference',
 @level2type=N'COLUMN',@level2name=N'IsPreferred';
GO
