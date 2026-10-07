namespace Philmart.Application.Commitments;

public class BuyNowRequest
{
    // the Buy Now Commitment version shown on the confirm screen (BR-03-R02)
    public Guid CommitmentVersionID { get; set; }

    public Guid DeliveryMethodID { get; set; }

    // BR-03-R04: an override for this purchase only. The profile default stays.
    public Guid? PickupPointID { get; set; }

    public DeliveryAddressDTO? Address { get; set; }

    // the browser makes one per click, so a double submit buys once
    public string IdempotencyKey { get; set; } = string.Empty;
}

public class DeliveryAddressDTO
{
    public string AddressLine1 { get; set; } = string.Empty;

    public string? AddressLine2 { get; set; }

    public string City { get; set; } = string.Empty;

    public string? Province { get; set; }

    public string? PostalCode { get; set; }

    public string CountryCode { get; set; } = "ZA";
}

public class PlaceBidRequest
{
    public Guid CommitmentVersionID { get; set; }

    public long AmountMinor { get; set; }

    public string IdempotencyKey { get; set; } = string.Empty;
}

public class PurchaseResultDTO
{
    public Guid SaleTransactionID { get; set; }

    public long PriceMinor { get; set; }

    public string DeliveryMethod { get; set; } = string.Empty;
}

public class BidResultDTO
{
    public Guid BidID { get; set; }

    public long AmountMinor { get; set; }

    public bool Leading { get; set; }

    public DateTimeOffset EndsAt { get; set; }

    // true when this bid landed in the soft-close window and pushed the end out
    public bool ExtendedClose { get; set; }
}

// what the confirm screen pre-fills (D009): this buyer's saved default for
// each method the Shop offers
public class PurchaseDefaultsDTO
{
    public Guid DeliveryMethodID { get; set; }

    public Guid? PickupPointID { get; set; }

    public DeliveryAddressDTO? Address { get; set; }
}
