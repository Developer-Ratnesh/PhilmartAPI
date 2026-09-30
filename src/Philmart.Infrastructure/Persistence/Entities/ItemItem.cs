namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ItemItem
{
    public Guid ID { get; set; }

    public Guid ShopID { get; set; }

    public string Reference { get; set; } = null!;

    public string Title { get; set; } = null!;

    public string? Description { get; set; }

    public Guid? AreaCountryID { get; set; }

    public Guid? TypeID { get; set; }

    public Guid? SubtypeID { get; set; }

    public Guid? ThemeID { get; set; }

    public Guid? FormatID { get; set; }

    public Guid? StampStateID { get; set; }

    public Guid? ConditionID { get; set; }

    public string? CatalogueReference { get; set; }

    public short? YearFrom { get; set; }

    public short? YearTo { get; set; }

    public Guid? StockLocationID { get; set; }

    public bool IsConsigned { get; set; }

    public Guid? SellerID { get; set; }

    public long? SellerMinimumPriceMinor { get; set; }   // gross, before commission

    public string State { get; set; } = null!;   // missing_damaged is a state, not a flag

    public DateTimeOffset? ReadyToListSince { get; set; }

    public string? RemovalReason { get; set; }

    public string? RemovalNote { get; set; }

    public DateTimeOffset StateChangedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public virtual ICollection<ItemImage> ItemImages { get; set; } = new List<ItemImage>();

    public virtual ICollection<ItemStateHistory> ItemStateHistories { get; set; } = new List<ItemStateHistory>();

    public virtual ICollection<ListListing> ListListings { get; set; } = new List<ListListing>();

    public virtual ShopShop Shop { get; set; } = null!;

    public virtual SellSeller? Seller { get; set; }
}
