namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ShopUserPermission
{
    public Guid ShopUserID { get; set; }

    public string PermissionCode { get; set; } = null!;

    public Guid ShopID { get; set; }

    public DateTimeOffset GrantedAt { get; set; }

    public Guid? GrantedBy { get; set; }

    public virtual ShopUser ShopUser { get; set; } = null!;
}
