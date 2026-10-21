namespace Philmart.Application.Account;

// SCR-PUB-006.1 Personal Details & Delivery Addresses
public class BuyerProfileDTO
{
    public string Email { get; set; } = string.Empty;

    public string? FullName { get; set; }

    public string? Mobile { get; set; }

    // D039: these three are shown but never edited after registration
    public string? IdentificationType { get; set; }

    public string? IdentificationNumber { get; set; }

    public DateOnly? DateOfBirth { get; set; }

    public DateTimeOffset? RegistrationCompletedAt { get; set; }

    public BuyerAddressDTO? Address { get; set; }

    public List<BuyerShippingPreferenceDTO> ShippingPreferences { get; set; } = new List<BuyerShippingPreferenceDTO>();
}

public class BuyerAddressDTO
{
    public string AddressLine1 { get; set; } = string.Empty;

    public string? AddressLine2 { get; set; }

    public string City { get; set; } = string.Empty;

    public string? Province { get; set; }

    public string? PostalCode { get; set; }

    public string CountryCode { get; set; } = "ZA";
}

public class BuyerShippingPreferenceDTO
{
    public Guid DeliveryMethodID { get; set; }

    public bool Available { get; set; }

    public Guid? PickupPointID { get; set; }

    public bool UseAddress { get; set; }

    public bool Preferred { get; set; }
}

public class UpdateMobileRequest
{
    public string? Mobile { get; set; }
}

// SCR-PUB-006.3. D040: only the outbid alert (EML-013) can be switched off.
public class CommunicationPreferencesDTO
{
    public bool OutbidAlerts { get; set; } = true;
}

// One row per acceptance, newest first. A renewal is a new row (BR-01-R05).
public class LegalAcceptanceDTO
{
    public string DocumentCode { get; set; } = string.Empty;

    public string DocumentName { get; set; } = string.Empty;

    public string Version { get; set; } = string.Empty;

    // accept or acknowledge
    public string AcceptanceMode { get; set; } = string.Empty;

    // registration, buy_now or confirm_bid
    public string Context { get; set; } = string.Empty;

    public DateTimeOffset AcceptedAt { get; set; }

    // false once a newer version has been published
    public bool IsCurrent { get; set; }
}
