namespace Philmart.Infrastructure.Persistence.Entities;

public partial class ItemImage
{
    public Guid ID { get; set; }

    public Guid ItemID { get; set; }

    public Guid ShopID { get; set; }

    public string StorageKey { get; set; } = null!;

    public string ContentType { get; set; } = null!;

    public long ByteSize { get; set; }

    public int? WidthPx { get; set; }

    public int? HeightPx { get; set; }

    public string ChecksumSha256 { get; set; } = null!;

    public int SortOrder { get; set; }

    public bool IsPrimary { get; set; }

    public DateTimeOffset UploadedAt { get; set; }

    public Guid? UploadedBy { get; set; }

    public virtual ItemItem Item { get; set; } = null!;
}
