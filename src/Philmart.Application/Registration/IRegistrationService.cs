using Philmart.Application.Auth;

namespace Philmart.Application.Registration;

// BR-01. Four steps: Buyer Registration, Personal Details, Address Details,
// Review and Accept. The buyer is registered only when step 4 succeeds.
public interface IRegistrationService
{
    // step 1 (SCR-PUB-014.1). Emails a 4-digit PIN with EML-019. Asking again
    // just sends a fresh PIN.
    Task<PinChallengeDTO> Start(StartRegistrationRequest request, CancellationToken cancellationToken = default);

    // "Verify email and continue". Returns the buyer's ID so they can be signed in.
    Task<Guid> VerifyEmail(PinVerifyRequest request, CancellationToken cancellationToken = default);

    Task<RegistrationStateDTO> GetState(CancellationToken cancellationToken = default);

    Task SavePersonalDetails(PersonalDetailsRequest request, CancellationToken cancellationToken = default);

    Task<List<DeliveryOptionDTO>> GetDeliveryOptions(CancellationToken cancellationToken = default);

    Task SaveAddressDetails(AddressDetailsRequest request, CancellationToken cancellationToken = default);

    Task<List<LegalDocumentDTO>> GetDocumentsToAccept(CancellationToken cancellationToken = default);

    // step 4, or a renewal after a document has been superseded (BR-01-R09)
    Task Accept(AcceptLegalRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default);
}
