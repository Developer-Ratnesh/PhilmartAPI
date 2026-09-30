namespace Philmart.Infrastructure.Persistence.Entities;

public partial class SellSeller
{
    public Guid ID { get; set; }

    public Guid ShopID { get; set; }

    public string Reference { get; set; } = null!;

    public string FullName { get; set; } = null!;

    public string? Email { get; set; }

    public string? Mobile { get; set; }

    public string? AddressLine1 { get; set; }

    public string? City { get; set; }

    public string? PostalCode { get; set; }

    public string CountryCode { get; set; } = null!;

    public bool StatementEnabled { get; set; }

    public DateTimeOffset? ArchivedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public virtual ICollection<ItemItem> ItemItems { get; set; } = new List<ItemItem>();
}
