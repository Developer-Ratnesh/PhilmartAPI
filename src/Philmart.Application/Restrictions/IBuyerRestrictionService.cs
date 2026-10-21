namespace Philmart.Application.Restrictions;

// D044/D045. A Shop restricts a buyer from new purchases and bids with that
// Shop; PHILMART restricts platform-wide. Each side lifts only its own. The
// block itself is enforced at Buy Now and Confirm Bid, not here.
public interface IBuyerRestrictionService
{
    // a Shop user sees its own Shop's; a PHILMART admin sees all of them
    Task<List<BuyerRestrictionDTO>> List(CancellationToken cancellationToken = default);

    Task<BuyerRestrictionDTO> Restrict(RestrictBuyerRequest request, CancellationToken cancellationToken = default);

    Task Lift(Guid restrictionId, LiftRestrictionRequest request, CancellationToken cancellationToken = default);
}

public class BuyerRestrictionDTO
{
    public Guid ID { get; set; }

    public Guid BuyerID { get; set; }

    public string BuyerEmail { get; set; } = null!;

    public string? BuyerName { get; set; }

    // 'Shop_Shop' or 'platform'
    public string Scope { get; set; } = null!;

    public string? ShopName { get; set; }

    public string Reason { get; set; } = null!;

    public DateTimeOffset ImposedAt { get; set; }

    public DateTimeOffset? LiftedAt { get; set; }

    public string? LiftReason { get; set; }

    // whether the person asking may lift it
    public bool CanLift { get; set; }
}

public class RestrictBuyerRequest
{
    public string Email { get; set; } = string.Empty;

    public string Reason { get; set; } = string.Empty;
}

public class LiftRestrictionRequest
{
    public string Reason { get; set; } = string.Empty;
}
