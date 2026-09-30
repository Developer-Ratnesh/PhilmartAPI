namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ShopUser
{
    public Guid ID { get; set; }

    public Guid ShopID { get; set; }

    public string Email { get; set; } = null!;

    public string FullName { get; set; } = null!;

    public string? PasswordHash { get; set; }

    public bool IsAdministrator { get; set; }

    public DateTimeOffset? DisabledAt { get; set; }

    public DateTimeOffset? InvitedAt { get; set; }

    public DateTimeOffset? AcceptedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public virtual ShopShop Shop { get; set; } = null!;

    public virtual ICollection<ShopUserPermission> ShopUserPermissions { get; set; }
        = new List<ShopUserPermission>();
}
