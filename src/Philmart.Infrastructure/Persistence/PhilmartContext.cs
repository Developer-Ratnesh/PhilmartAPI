using Microsoft.EntityFrameworkCore;
using Philmart.Infrastructure.Persistence.Entities;

namespace Philmart.Infrastructure.Persistence;

// Hand written for now. Run tools/scaffold.ps1 to regenerate from the database
// once the migrations are applied. There are no EF migrations, the SQL owns the
// schema, so never call EnsureCreated.
public partial class PhilmartContext(DbContextOptions<PhilmartContext> options)
    : DbContext(options)
{
    public virtual DbSet<ItemItem> ItemItems { get; set; }

    public virtual DbSet<ItemImage> ItemImages { get; set; }

    public virtual DbSet<ItemStateHistory> ItemStateHistories { get; set; }

    public virtual DbSet<ItemTransitionRule> ItemTransitionRules { get; set; }

    public virtual DbSet<ListListing> ListListings { get; set; }

    public virtual DbSet<ListBid> ListBids { get; set; }

    public virtual DbSet<ShopShop> ShopShops { get; set; }

    public virtual DbSet<ShopUser> ShopUsers { get; set; }

    public virtual DbSet<ShopUserPermission> ShopUserPermissions { get; set; }

    public virtual DbSet<SellSeller> SellSellers { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("philmart");

        modelBuilder.Entity<ItemItem>(entity =>
        {
            entity.ToTable("Item_Item");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.SellerID).HasColumnName("SellerID");
            entity.Property(e => e.AreaCountryID).HasColumnName("AreaCountryID");
            entity.Property(e => e.TypeID).HasColumnName("TypeID");
            entity.Property(e => e.SubtypeID).HasColumnName("SubtypeID");
            entity.Property(e => e.ThemeID).HasColumnName("ThemeID");
            entity.Property(e => e.FormatID).HasColumnName("FormatID");
            entity.Property(e => e.StampStateID).HasColumnName("StampStateID");
            entity.Property(e => e.ConditionID).HasColumnName("ConditionID");
            entity.Property(e => e.StockLocationID).HasColumnName("StockLocationID");
            entity.Property(e => e.Reference).HasMaxLength(40).IsUnicode(false);
            entity.Property(e => e.Title).HasMaxLength(400);
            entity.Property(e => e.State).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.RemovalReason).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.RemovalNote).HasMaxLength(1000);
            entity.Property(e => e.CatalogueReference).HasMaxLength(120);

            // set by a trigger
            entity.Property(e => e.StateChangedAt).ValueGeneratedOnAddOrUpdate();
            entity.Property(e => e.ReadyToListSince).ValueGeneratedOnAddOrUpdate();

            entity.HasIndex(e => new { e.ShopID, e.State }, "IX_item_shop_state");
            entity.HasIndex(e => new { e.ShopID, e.Reference }, "UQ_item_shop_reference").IsUnique();

            entity.HasOne(d => d.Shop).WithMany(p => p.ItemItems)
                .HasForeignKey(d => d.ShopID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_item_shop");

            entity.HasOne(d => d.Seller).WithMany(p => p.ItemItems)
                .HasForeignKey(d => d.SellerID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_item_seller");
        });

        modelBuilder.Entity<ItemImage>(entity =>
        {
            entity.ToTable("Item_Image");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ItemID).HasColumnName("ItemID");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.StorageKey).HasMaxLength(500);
            entity.Property(e => e.ContentType).HasMaxLength(60).IsUnicode(false);
            entity.Property(e => e.ChecksumSha256).HasMaxLength(64).IsFixedLength().IsUnicode(false);

            entity.HasOne(d => d.Item).WithMany(p => p.ItemImages)
                .HasForeignKey(d => d.ItemID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_ii_item");
        });

        modelBuilder.Entity<ItemStateHistory>(entity =>
        {
            entity.ToTable("Item_StateHistory");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").ValueGeneratedOnAdd();
            entity.Property(e => e.ItemID).HasColumnName("ItemID");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.ListingID).HasColumnName("ListingID");
            entity.Property(e => e.FromState).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.ToState).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.ActorKind).HasMaxLength(20).IsUnicode(false);
            entity.Property(e => e.Reason).HasMaxLength(1000);

            entity.HasOne(d => d.Item).WithMany(p => p.ItemStateHistories)
                .HasForeignKey(d => d.ItemID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_ish_item");
        });

        modelBuilder.Entity<ItemTransitionRule>(entity =>
        {
            entity.ToTable("Item_TransitionRule");

            entity.HasKey(e => new { e.FromState, e.ToState });
            entity.Property(e => e.FromState).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.ToState).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.DecisionRef).HasMaxLength(60).IsUnicode(false);
            entity.Property(e => e.Note).HasMaxLength(400);
        });

        modelBuilder.Entity<ListListing>(entity =>
        {
            entity.ToTable("List_Listing");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.ItemID).HasColumnName("ItemID");
            entity.Property(e => e.AuctionEventID).HasColumnName("AuctionEventID");
            entity.Property(e => e.WinningBidID).HasColumnName("WinningBidID");
            entity.Property(e => e.ListingType).HasMaxLength(20).IsUnicode(false);
            entity.Property(e => e.State).HasMaxLength(20).IsUnicode(false);
            entity.Property(e => e.Reference).HasMaxLength(40).IsUnicode(false);
            entity.Property(e => e.CancellationReason).HasMaxLength(1000);

            entity.HasIndex(e => new { e.ShopID, e.State }, "IX_lst_shop_state");

            entity.HasOne(d => d.Item).WithMany(p => p.ListListings)
                .HasForeignKey(d => d.ItemID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_lst_item");

            entity.HasOne(d => d.Shop).WithMany(p => p.ListListings)
                .HasForeignKey(d => d.ShopID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_lst_shop");
        });

        modelBuilder.Entity<ListBid>(entity =>
        {
            entity.ToTable("List_Bid");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ListingID).HasColumnName("ListingID");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.BuyerID).HasColumnName("BuyerID");
            entity.Property(e => e.IdempotencyKey).HasMaxLength(80).IsUnicode(false);
            entity.Property(e => e.IpAddress).HasMaxLength(45).IsUnicode(false);

            // set inside P_List_Bid_Place
            entity.Property(e => e.PlacedAt).ValueGeneratedOnAdd();

            entity.HasIndex(e => new { e.ListingID, e.SequenceNo }, "UQ_bid_listing_sequence").IsUnique();

            entity.HasOne(d => d.Listing).WithMany(p => p.ListBids)
                .HasForeignKey(d => d.ListingID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_bid_listing");
        });

        modelBuilder.Entity<ShopShop>(entity =>
        {
            entity.ToTable("Shop_Shop");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.Reference).HasMaxLength(40).IsUnicode(false);
            entity.Property(e => e.TradingName).HasMaxLength(200);
            entity.Property(e => e.LegalEntityName).HasMaxLength(200);
            entity.Property(e => e.Status).HasMaxLength(30).IsUnicode(false);
            entity.Property(e => e.DeactivationReason).HasMaxLength(1000);
        });

        modelBuilder.Entity<ShopUser>(entity =>
        {
            entity.ToTable("Shop_User");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.Email).HasMaxLength(256);
            entity.Property(e => e.FullName).HasMaxLength(200);

            entity.HasOne(d => d.Shop).WithMany(p => p.ShopUsers)
                .HasForeignKey(d => d.ShopID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_su_shop");
        });

        modelBuilder.Entity<ShopUserPermission>(entity =>
        {
            entity.ToTable("Shop_UserPermission");

            entity.HasKey(e => new { e.ShopUserID, e.PermissionCode });
            entity.Property(e => e.ShopUserID).HasColumnName("ShopUserID");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.PermissionCode).HasMaxLength(60).IsUnicode(false);

            entity.HasOne(d => d.ShopUser).WithMany(p => p.ShopUserPermissions)
                .HasForeignKey(d => d.ShopUserID)
                .OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_sup_user");
        });

        modelBuilder.Entity<SellSeller>(entity =>
        {
            entity.ToTable("Sell_Seller");

            entity.HasKey(e => e.ID);
            entity.Property(e => e.ID).HasColumnName("ID").HasDefaultValueSql("(newsequentialid())");
            entity.Property(e => e.ShopID).HasColumnName("ShopID");
            entity.Property(e => e.Reference).HasMaxLength(40).IsUnicode(false);
            entity.Property(e => e.FullName).HasMaxLength(200);
            entity.Property(e => e.Email).HasMaxLength(256);
            entity.Property(e => e.CountryCode).HasMaxLength(2).IsFixedLength().IsUnicode(false);
        });

        OnModelCreatingPartial(modelBuilder);
    }

    partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
}
