using Philmart.Application.Registration;
using Philmart.Domain.Exceptions;

namespace Philmart.Infrastructure.Services;

// SCR-PUB-014.4: the Buyer's primary physical address. Line 1, Suburb/City,
// Province/Region, Postal Code and Country are all required (Line 2 is the
// only optional field). Registration step 3 and the profile both check here,
// so an API call can't save less than the screen asks for.
public static class PhysicalAddress
{
    public static readonly string[] SouthAfricanProvinces = new[]
    {
        "Eastern Cape", "Free State", "Gauteng", "KwaZulu-Natal", "Limpopo",
        "Mpumalanga", "North West", "Northern Cape", "Western Cape",
    };

    public static void Check(AddressDetailsRequest request)
    {
        var missing = new List<string>();

        if (string.IsNullOrWhiteSpace(request.AddressLine1))
        {
            missing.Add("address line 1");
        }

        if (string.IsNullOrWhiteSpace(request.City))
        {
            missing.Add("suburb or city");
        }

        if (string.IsNullOrWhiteSpace(request.Province))
        {
            missing.Add("province or region");
        }

        if (string.IsNullOrWhiteSpace(request.PostalCode))
        {
            missing.Add("postal code");
        }

        if (string.IsNullOrWhiteSpace(request.CountryCode))
        {
            missing.Add("country");
        }

        if (missing.Count > 0)
        {
            throw new BusinessRuleViolationException("Enter your " + string.Join(", ", missing) + ".");
        }

        string country = request.CountryCode!.Trim();
        if (country.Length != 2 || !country.All(char.IsLetter))
        {
            throw new BusinessRuleViolationException("Choose a country from the list.");
        }

        if (country.Equals("ZA", StringComparison.OrdinalIgnoreCase))
        {
            string postal = request.PostalCode!.Trim();
            if (postal.Length != 4 || !postal.All(char.IsDigit))
            {
                throw new BusinessRuleViolationException("A South African postal code has 4 digits.");
            }

            string province = request.Province!.Trim();
            if (!SouthAfricanProvinces.Contains(province, StringComparer.OrdinalIgnoreCase))
            {
                throw new BusinessRuleViolationException("Choose a South African province from the list.");
            }
        }
    }
}
