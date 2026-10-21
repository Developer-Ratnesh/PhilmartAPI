using System.Data;
using Microsoft.EntityFrameworkCore;
using Philmart.Application.Account;
using Philmart.Application.Registration;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class BuyerProfileService(IDbContextFactory<PhilmartContext> contextFactory, ITenantContext tenant) : IBuyerProfileService
{
    public async Task<BuyerProfileDTO> GetProfile(CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            var row = await context.Database
                .SqlQuery<ProfileRow>($@"SELECT Email, FullName, Mobile, IdentificationType, IdentificationNumber, DateOfBirth, RegistrationCompletedAt
                                        FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
                .FirstOrDefaultAsync(cancellationToken);

            if (row == null)
            {
                throw new NotFoundException("Buyer", buyerId);
            }

            var profile = new BuyerProfileDTO();
            profile.Email = row.Email;
            profile.FullName = row.FullName;
            profile.Mobile = row.Mobile;
            profile.IdentificationType = row.IdentificationType;
            profile.IdentificationNumber = row.IdentificationNumber;
            profile.DateOfBirth = row.DateOfBirth == null ? null : DateOnly.FromDateTime(row.DateOfBirth.Value);
            profile.RegistrationCompletedAt = row.RegistrationCompletedAt;

            profile.Address = await context.Database
                .SqlQuery<BuyerAddressDTO>($@"SELECT AddressLine1, AddressLine2, City, Province, PostalCode, CountryCode
                                             FROM philmart.Buy_Address WHERE BuyerID = {buyerId} AND IsDefault = 1 AND ArchivedAt IS NULL")
                .FirstOrDefaultAsync(cancellationToken);

            profile.ShippingPreferences = await context.Database
                .SqlQuery<BuyerShippingPreferenceDTO>($@"SELECT DeliveryMethodID, Available, DefaultPickupPointID AS PickupPointID,
                                                               CAST(CASE WHEN DefaultAddressID IS NULL THEN 0 ELSE 1 END AS BIT) AS UseAddress,
                                                               IsPreferred AS Preferred
                                                        FROM philmart.Buy_ShippingPreference WHERE BuyerID = {buyerId}")
                .ToListAsync(cancellationToken);

            return profile;
        }
    }

    // D039: only the mobile number. Name, ID and date of birth stay as registered.
    public async Task UpdateMobile(UpdateMobileRequest request, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();
        string? mobile = string.IsNullOrWhiteSpace(request.Mobile) ? null : request.Mobile.Trim();

        if (!IsValidMobile(mobile))
        {
            throw new BusinessRuleViolationException("Enter a valid mobile number.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await RequireRegistered(context, buyerId, cancellationToken);

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Buy_Buyer SET Mobile = {mobile}, UpdatedAt = philmart.ServerNow() WHERE ID = {buyerId}",
                    cancellationToken);

                await Audit(context, buyerId, "Buy_Buyer.profile_updated", new { Field = "Mobile" }, cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    public async Task UpdateAddress(AddressDetailsRequest request, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        if (string.IsNullOrWhiteSpace(request.AddressLine1) || string.IsNullOrWhiteSpace(request.City))
        {
            throw new BusinessRuleViolationException("Enter your street address and city.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            await RequireRegistered(context, buyerId, cancellationToken);

            var methods = await DeliveryOptions.Load(context, null, cancellationToken);

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                await RegistrationService.SaveAddressAndShipping(context, buyerId, request, methods, cancellationToken);

                await Audit(context, buyerId, "Buy_Buyer.address_changed", null, cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    public async Task<CommunicationPreferencesDTO> GetPreferences(CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            // no row means it was never switched off
            var enabled = await context.Database
                .SqlQuery<bool>($"SELECT Enabled AS Value FROM philmart.Buy_CommunicationPreference WHERE BuyerID = {buyerId} AND EmailCode = {PhilmartConstants.Email.OutbidAlert}")
                .ToListAsync(cancellationToken);

            return new CommunicationPreferencesDTO { OutbidAlerts = enabled.Count == 0 || enabled[0] };
        }
    }

    public async Task SavePreferences(CommunicationPreferencesDTO request, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $@"MERGE philmart.Buy_CommunicationPreference AS t
                       USING (SELECT {buyerId} AS BuyerID, {PhilmartConstants.Email.OutbidAlert} AS EmailCode) AS s
                          ON t.BuyerID = s.BuyerID AND t.EmailCode = s.EmailCode
                       WHEN MATCHED THEN UPDATE SET Enabled = {request.OutbidAlerts}, UpdatedAt = philmart.ServerNow()
                       WHEN NOT MATCHED THEN INSERT (BuyerID, EmailCode, Enabled) VALUES ({buyerId}, {PhilmartConstants.Email.OutbidAlert}, {request.OutbidAlerts});",
                    cancellationToken);

                await Audit(context, buyerId, "Buy_Buyer.preferences_changed", new { request.OutbidAlerts }, cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    public async Task<List<LegalAcceptanceDTO>> GetLegalAcceptances(CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            return await context.Database
                .SqlQuery<LegalAcceptanceDTO>($@"SELECT a.DocumentCode, d.Name AS DocumentName, a.DocumentVersion AS Version, d.AcceptanceMode,
                                                        a.Context, a.AcceptedAt,
                                                        CAST(CASE WHEN v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL THEN 1 ELSE 0 END AS BIT) AS IsCurrent
                                                 FROM philmart.Sys_LegalAcceptance a
                                                 JOIN philmart.Sys_LegalDocument d ON d.Code = a.DocumentCode
                                                 JOIN philmart.Sys_LegalDocumentVersion v ON v.ID = a.VersionID
                                                 WHERE a.BuyerID = {buyerId}
                                                 ORDER BY a.AcceptedAt DESC, d.Name")
                .ToListAsync(cancellationToken);
        }
    }

    // Blank is allowed (the number is optional). Otherwise digits with the usual
    // separators, and between 9 and 15 digits so "0" or a typo doesn't get through.
    public static bool IsValidMobile(string? mobile)
    {
        if (string.IsNullOrWhiteSpace(mobile))
        {
            return true;
        }

        string value = mobile.Trim();
        int digits = value.Count(char.IsDigit);

        return value.Length <= 40
            && value.All(c => char.IsDigit(c) || c == '+' || c == ' ' || c == '-' || c == '(' || c == ')')
            && digits >= 9 && digits <= 15;
    }

    private Guid RequireBuyer()
    {
        if (!tenant.IsBuyer || tenant.ActorId == null)
        {
            throw new NotAuthorisedException("Sign in as a buyer to do this.");
        }

        return tenant.ActorId.Value;
    }

    // a half-registered buyer still edits through the registration steps
    private static async Task RequireRegistered(PhilmartContext context, Guid buyerId, CancellationToken cancellationToken)
    {
        var completed = await context.Database
            .SqlQuery<DateTimeOffset?>($"SELECT RegistrationCompletedAt AS Value FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
            .FirstOrDefaultAsync(cancellationToken);

        if (completed == null)
        {
            throw new BusinessRuleViolationException("Finish your registration first.");
        }
    }

    private static Task Audit(PhilmartContext context, Guid buyerId, string action, object? after, CancellationToken cancellationToken)
    {
        return context.AsSystem(PhilmartConstants.ActorKind.Buyer, () =>
            AuditSql.Add(context, buyerId, PhilmartConstants.ActorKind.Buyer, null, "Buy_Buyer", buyerId.ToString(),
                action, after, cancellationToken: cancellationToken),
            cancellationToken);
    }

    private class ProfileRow
    {
        public string Email { get; set; } = null!;

        public string? FullName { get; set; }

        public string? Mobile { get; set; }

        public string? IdentificationType { get; set; }

        public string? IdentificationNumber { get; set; }

        public DateTime? DateOfBirth { get; set; }

        public DateTimeOffset? RegistrationCompletedAt { get; set; }
    }
}
