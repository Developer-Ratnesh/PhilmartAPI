namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ItemStateHistory
{
    public long ID { get; set; }

    public Guid ItemID { get; set; }

    public Guid ShopID { get; set; }

    public string? FromState { get; set; }

    public string ToState { get; set; } = null!;

    public string? Reason { get; set; }

    public Guid? ListingID { get; set; }

    public DateTimeOffset ChangedAt { get; set; }

    public Guid? ChangedBy { get; set; }

    public string ActorKind { get; set; } = null!;

    public virtual ItemItem Item { get; set; } = null!;
}
