namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ShopShop
{
    public Guid ID { get; set; }

    public string Reference { get; set; } = null!;

    public string TradingName { get; set; } = null!;

    public string? LegalEntityName { get; set; }

    public string? RegistrationNumber { get; set; }

    public string? VatNumber { get; set; }

    public string Status { get; set; } = null!;

    public DateTimeOffset? SetupAccessGrantedAt { get; set; }

    public DateTimeOffset? ActivatedAt { get; set; }

    public DateTimeOffset? DeactivatedAt { get; set; }

    public string? DeactivationReason { get; set; }

    public DateTimeOffset? ReactivatedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public virtual ICollection<ItemItem> ItemItems { get; set; } = new List<ItemItem>();

    public virtual ICollection<ListListing> ListListings { get; set; } = new List<ListListing>();

    public virtual ICollection<ShopUser> ShopUsers { get; set; } = new List<ShopUser>();
}
