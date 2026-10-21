using Philmart.Application.Registration;

namespace Philmart.Application.Account;

// The buyer's own profile, email preferences and legal history (SCR-PUB-006).
// Always the buyer on the login token.
public interface IBuyerProfileService
{
    Task<BuyerProfileDTO> GetProfile(CancellationToken cancellationToken = default);

    Task UpdateMobile(UpdateMobileRequest request, CancellationToken cancellationToken = default);

    // replaces the address and delivery defaults for future purchases only
    // OutbidAlerts on the request is ignored here, that's SavePreferences
    Task UpdateAddress(AddressDetailsRequest request, CancellationToken cancellationToken = default);

    Task<CommunicationPreferencesDTO> GetPreferences(CancellationToken cancellationToken = default);

    Task SavePreferences(CommunicationPreferencesDTO request, CancellationToken cancellationToken = default);

    Task<List<LegalAcceptanceDTO>> GetLegalAcceptances(CancellationToken cancellationToken = default);
}
