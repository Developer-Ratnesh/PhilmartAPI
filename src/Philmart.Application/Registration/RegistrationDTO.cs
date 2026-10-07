namespace Philmart.Application.Registration;

public class StartRegistrationRequest
{
    public string Email { get; set; } = string.Empty;
}

public class PersonalDetailsRequest
{
    public string FullName { get; set; } = string.Empty;

    public string? Mobile { get; set; }

    // sa_id or passport
    public string IdentificationType { get; set; } = string.Empty;

    public string IdentificationNumber { get; set; } = string.Empty;

    public DateOnly DateOfBirth { get; set; }
}

public class AddressDetailsRequest
{
    public string AddressLine1 { get; set; } = string.Empty;

    public string? AddressLine2 { get; set; }

    public string City { get; set; } = string.Empty;

    public string? Province { get; set; }

    public string? PostalCode { get; set; }

    public string CountryCode { get; set; } = "ZA";

    public List<ShippingPreferenceRequest> ShippingPreferences { get; set; } = new List<ShippingPreferenceRequest>();

    // D040: the only optional email. Everything else can't be switched off.
    public bool OutbidAlerts { get; set; } = true;
}

public class ShippingPreferenceRequest
{
    public Guid DeliveryMethodID { get; set; }

    public bool Available { get; set; } = true;

    // one or the other, depending on whether the method needs a pickup point
    public Guid? PickupPointID { get; set; }

    public bool UseAddress { get; set; }
}

public class AcceptLegalRequest
{
    // the exact version IDs the buyer was shown (BR-01-R04)
    public List<Guid> VersionIDs { get; set; } = new List<Guid>();
}

public class LegalDocumentDTO
{
    public Guid VersionID { get; set; }

    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string Version { get; set; } = string.Empty;

    // accept or acknowledge
    public string AcceptanceMode { get; set; } = string.Empty;

    public string Body { get; set; } = string.Empty;
}

public class DeliveryOptionDTO
{
    public Guid ID { get; set; }

    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string MethodKind { get; set; } = string.Empty;

    public bool RequiresPickupPoint { get; set; }

    public bool RequiresAddress { get; set; }

    public List<PickupPointDTO> PickupPoints { get; set; } = new List<PickupPointDTO>();
}

public class PickupPointDTO
{
    public Guid ID { get; set; }

    public string Name { get; set; } = string.Empty;

    public string? Address { get; set; }
}

public class RegistrationStateDTO
{
    public int Step { get; set; }

    public bool EmailVerified { get; set; }

    public bool Completed { get; set; }

    public string Email { get; set; } = string.Empty;

    public string? FullName { get; set; }
}
