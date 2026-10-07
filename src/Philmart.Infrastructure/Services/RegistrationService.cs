using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Philmart.Application.Auth;
using Philmart.Application.Registration;
using Philmart.Domain.Abstractions;
using Philmart.Domain.Constants;
using Philmart.Domain.Exceptions;
using Philmart.Infrastructure.Persistence;

namespace Philmart.Infrastructure.Services;

public class RegistrationService(
    IDbContextFactory<PhilmartContext> contextFactory,
    ITenantContext tenant,
    IPinChallenges pins,
    IConfiguration configuration,
    ILogger<RegistrationService> logger) : IRegistrationService
{
    private static readonly string[] IdentificationTypes = new[] { "sa_id", "passport" };

    public async Task<PinChallengeDTO> Start(StartRegistrationRequest request, CancellationToken cancellationToken = default)
    {
        string email = request.Email.Trim();

        if (email.Length == 0 || !email.Contains('@'))
        {
            throw new BusinessRuleViolationException("Enter a valid email address.");
        }

        if (!pins.CanSend(email))
        {
            throw new BusinessRuleViolationException("Too many PINs have been asked for. Please wait an hour and try again.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            return await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                // nobody is signed in yet, and the email row has to carry the BuyerID
                await context.UseSystemSession(null, cancellationToken);

                var existing = await context.Database
                    .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep FROM philmart.Buy_Buyer WHERE Email = {email}")
                    .FirstOrDefaultAsync(cancellationToken);

                // Same answer whether the email is registered or not. A registered
                // email gets a challenge that never passes, so nobody can fish for accounts.
                if (existing != null && existing.RegistrationCompletedAt != null)
                {
                    return new PinChallengeDTO { Challenge = pins.Create(PinPurpose.Registration, email, null).Challenge };
                }

                Guid buyerId;

                if (existing == null)
                {
                    buyerId = Guid.NewGuid();

                    // no password, buyers sign in with an emailed PIN (SCR-PUB-014)
                    await context.Database.ExecuteSqlAsync(
                        $"INSERT INTO philmart.Buy_Buyer (ID, Email, RegistrationStep) VALUES ({buyerId}, {email}, 1)",
                        cancellationToken);

                    await AuditSql.Add(context, buyerId, PhilmartConstants.ActorKind.Buyer, null, "Buy_Buyer", buyerId.ToString(),
                        "Buy_Buyer.registration_started", new { Step = 1 }, cancellationToken: cancellationToken);
                }
                else
                {
                    // picking up a registration they started before
                    buyerId = existing.ID;
                }

                var challenge = pins.Create(PinPurpose.Registration, email, buyerId);

                // D035: the PIN lets them carry on. Don't say it finishes anything.
                await EmailSql.Queue(context, PhilmartConstants.Email.BuyerEmailVerification, email, buyerId, null,
                    "Your PHILMART verification PIN",
                    "Your verification PIN is " + challenge.Pin + ". It expires in 10 minutes.\n\n" +
                    "Enter it to verify your email and continue your registration. You'll still need to finish the remaining steps before you can buy or bid.\n",
                    new { pin = challenge.Pin },
                    cancellationToken);

                if (configuration.GetValue("Auth:LogPins", false))
                {
                    logger.LogInformation("EML-019 queued for {Email}. Verification PIN: {Pin}", email, challenge.Pin);
                }

                return new PinChallengeDTO { Challenge = challenge.Challenge };
            }, cancellationToken);
        }
    }

    public async Task<Guid> VerifyEmail(PinVerifyRequest request, CancellationToken cancellationToken = default)
    {
        var result = pins.Verify(PinPurpose.Registration, request.Challenge, request.Pin);

        if (result?.BuyerID == null)
        {
            throw new BusinessRuleViolationException("That PIN isn't right or has expired. Check the email we sent, or ask for a new PIN.");
        }

        Guid buyerId = result.BuyerID.Value;

        using (var context = contextFactory.CreateDbContext())
        {
            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.UseSystemSession(buyerId, cancellationToken);

                // D035: verifying only lets them carry on. It doesn't register
                // them and it must not send the welcome email.
                await context.Database.ExecuteSqlAsync(
                    $@"UPDATE philmart.Buy_Buyer
                          SET EmailVerifiedAt = ISNULL(EmailVerifiedAt, philmart.ServerNow()),
                              RegistrationStep = CASE WHEN RegistrationStep < 2 THEN 2 ELSE RegistrationStep END,
                              UpdatedAt = philmart.ServerNow()
                        WHERE ID = {buyerId}",
                    cancellationToken);

                await AuditSql.Add(context, buyerId, PhilmartConstants.ActorKind.Buyer, null, "Buy_Buyer", buyerId.ToString(),
                    "Buy_Buyer.email_verified", cancellationToken: cancellationToken);

                return true;
            }, cancellationToken);
        }

        return buyerId;
    }

    public async Task<RegistrationStateDTO> GetState(CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await LoadBuyer(context, buyerId, cancellationToken);

            var dto = new RegistrationStateDTO();
            dto.Step = buyer.RegistrationStep;
            dto.EmailVerified = buyer.EmailVerifiedAt != null;
            dto.Completed = buyer.RegistrationCompletedAt != null;
            dto.Email = buyer.Email;
            dto.FullName = buyer.FullName;
            return dto;
        }
    }

    public async Task SavePersonalDetails(PersonalDetailsRequest request, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        if (string.IsNullOrWhiteSpace(request.FullName))
        {
            throw new BusinessRuleViolationException("Enter your full name.");
        }

        if (!IdentificationTypes.Contains(request.IdentificationType))
        {
            throw new BusinessRuleViolationException("Choose SA ID or passport.");
        }

        if (string.IsNullOrWhiteSpace(request.IdentificationNumber))
        {
            throw new BusinessRuleViolationException("Enter your ID or passport number.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await LoadBuyer(context, buyerId, cancellationToken);
            CheckCanEdit(buyer);

            if (buyer.EmailVerifiedAt == null)
            {
                throw new BusinessRuleViolationException("Verify your email address first. We've sent you a link.", "D035");
            }

            string fullName = request.FullName.Trim();
            string? mobile = string.IsNullOrWhiteSpace(request.Mobile) ? null : request.Mobile.Trim();
            string idNumber = request.IdentificationNumber.Trim();
            DateTime dob = request.DateOfBirth.ToDateTime(TimeOnly.MinValue);

            await context.Database.ExecuteSqlAsync(
                $@"UPDATE philmart.Buy_Buyer
                      SET FullName = {fullName}, Mobile = {mobile},
                          IdentificationType = {request.IdentificationType}, IdentificationNumber = {idNumber},
                          DateOfBirth = {dob},
                          RegistrationStep = CASE WHEN RegistrationStep < 3 THEN 3 ELSE RegistrationStep END,
                          UpdatedAt = philmart.ServerNow()
                    WHERE ID = {buyerId}",
                cancellationToken);
        }
    }

    public async Task<List<DeliveryOptionDTO>> GetDeliveryOptions(CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            return await DeliveryOptions.Load(context, null, cancellationToken);
        }
    }

    public async Task SaveAddressDetails(AddressDetailsRequest request, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        if (string.IsNullOrWhiteSpace(request.AddressLine1) || string.IsNullOrWhiteSpace(request.City))
        {
            throw new BusinessRuleViolationException("Enter your street address and city.");
        }

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await LoadBuyer(context, buyerId, cancellationToken);
            CheckCanEdit(buyer);

            if (buyer.RegistrationStep < 3)
            {
                throw new BusinessRuleViolationException("Fill in your personal details first.");
            }

            var methods = await DeliveryOptions.Load(context, null, cancellationToken);

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                // Going back and changing the address replaces it. The old one is
                // archived rather than deleted because nothing here is deleted.
                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Buy_Address SET IsDefault = 0, ArchivedAt = philmart.ServerNow() WHERE BuyerID = {buyerId} AND ArchivedAt IS NULL",
                    cancellationToken);

                Guid addressId = Guid.NewGuid();
                string line1 = request.AddressLine1.Trim();
                string city = request.City.Trim();
                string country = string.IsNullOrWhiteSpace(request.CountryCode) ? "ZA" : request.CountryCode.Trim().ToUpperInvariant();

                await context.Database.ExecuteSqlAsync(
                    $@"INSERT INTO philmart.Buy_Address (ID, BuyerID, AddressLine1, AddressLine2, City, Province, PostalCode, CountryCode, IsDefault)
                       VALUES ({addressId}, {buyerId}, {line1}, {request.AddressLine2}, {city}, {request.Province}, {request.PostalCode}, {country}, 1)",
                    cancellationToken);

                foreach (var pref in request.ShippingPreferences)
                {
                    var method = methods.FirstOrDefault(x => x.ID == pref.DeliveryMethodID);
                    if (method == null)
                    {
                        throw new BusinessRuleViolationException("That delivery method isn't offered.");
                    }

                    Guid? pickupId = null;
                    Guid? defaultAddressId = null;

                    // D037/D009: each method gets its own default, a pickup point or the address
                    if (pref.Available && method.RequiresPickupPoint)
                    {
                        if (pref.PickupPointID == null || !method.PickupPoints.Any(x => x.ID == pref.PickupPointID))
                        {
                            throw new BusinessRuleViolationException("Choose a pickup point for " + method.Name + ".", "D037");
                        }

                        pickupId = pref.PickupPointID;
                    }
                    else if (pref.Available && (method.RequiresAddress || pref.UseAddress))
                    {
                        defaultAddressId = addressId;
                    }

                    await context.Database.ExecuteSqlAsync(
                        $@"MERGE philmart.Buy_ShippingPreference AS t
                           USING (SELECT {buyerId} AS BuyerID, {pref.DeliveryMethodID} AS DeliveryMethodID) AS s
                              ON t.BuyerID = s.BuyerID AND t.DeliveryMethodID = s.DeliveryMethodID
                           WHEN MATCHED THEN UPDATE SET Available = {pref.Available}, DefaultPickupPointID = {pickupId},
                                                        DefaultAddressID = {defaultAddressId}, UpdatedAt = philmart.ServerNow()
                           WHEN NOT MATCHED THEN INSERT (BuyerID, DeliveryMethodID, Available, DefaultPickupPointID, DefaultAddressID)
                                                 VALUES ({buyerId}, {pref.DeliveryMethodID}, {pref.Available}, {pickupId}, {defaultAddressId});",
                        cancellationToken);
                }

                await context.Database.ExecuteSqlAsync(
                    $@"MERGE philmart.Buy_CommunicationPreference AS t
                       USING (SELECT {buyerId} AS BuyerID, {PhilmartConstants.Email.OutbidAlert} AS EmailCode) AS s
                          ON t.BuyerID = s.BuyerID AND t.EmailCode = s.EmailCode
                       WHEN MATCHED THEN UPDATE SET Enabled = {request.OutbidAlerts}, UpdatedAt = philmart.ServerNow()
                       WHEN NOT MATCHED THEN INSERT (BuyerID, EmailCode, Enabled) VALUES ({buyerId}, {PhilmartConstants.Email.OutbidAlert}, {request.OutbidAlerts});",
                    cancellationToken);

                await context.Database.ExecuteSqlAsync(
                    $"UPDATE philmart.Buy_Buyer SET RegistrationStep = 4, UpdatedAt = philmart.ServerNow() WHERE ID = {buyerId}",
                    cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    public async Task<List<LegalDocumentDTO>> GetDocumentsToAccept(CancellationToken cancellationToken = default)
    {
        using (var context = contextFactory.CreateDbContext())
        {
            return await CurrentDocuments(context, cancellationToken);
        }
    }

    public async Task Accept(AcceptLegalRequest request, string? ipAddress, string? userAgent, CancellationToken cancellationToken = default)
    {
        Guid buyerId = RequireBuyer();

        using (var context = contextFactory.CreateDbContext())
        {
            var buyer = await LoadBuyer(context, buyerId, cancellationToken);
            bool renewal = buyer.RegistrationCompletedAt != null;

            if (!renewal && buyer.RegistrationStep < 4)
            {
                throw new BusinessRuleViolationException("Fill in your address details first.");
            }

            var current = await CurrentDocuments(context, cancellationToken);

            if (current.Count < AuthService.BuyerDocuments.Length)
            {
                throw new BusinessRuleViolationException("The legal documents haven't been published yet, so registration can't be completed. Please try again later.");
            }

            // BR-01-R04: what was accepted has to be what is current. If a version
            // changed while they were reading, they see it again.
            var shown = request.VersionIDs.Distinct().ToList();
            if (shown.Count != current.Count || current.Any(x => !shown.Contains(x.VersionID)))
            {
                throw new BusinessRuleViolationException("One of the documents has been updated since you opened this page. Please review them again.");
            }

            await context.InTransaction(IsolationLevel.ReadCommitted, async () =>
            {
                await context.Database.OpenConnectionAsync(cancellationToken);

                // BR-01-R05: always new rows, the database won't let an old acceptance change
                foreach (var doc in current)
                {
                    await context.Database.ExecuteSqlAsync(
                        $@"INSERT INTO philmart.Sys_LegalAcceptance
                               (VersionID, DocumentCode, DocumentVersion, SubjectKind, BuyerID, Context, IpAddress, UserAgent)
                           VALUES ({doc.VersionID}, {doc.Code}, {doc.Version}, 'Buy_Buyer', {buyerId}, 'registration', {ipAddress}, {Trim(userAgent, 500)})",
                        cancellationToken);
                }

                var versions = current.Select(x => new { x.Code, x.Version, x.VersionID }).ToList();

                if (!renewal)
                {
                    await context.Database.ExecuteSqlAsync(
                        $"UPDATE philmart.Buy_Buyer SET RegistrationCompletedAt = philmart.ServerNow(), UpdatedAt = philmart.ServerNow() WHERE ID = {buyerId}",
                        cancellationToken);

                    // D036: the welcome goes now and only now
                    await EmailSql.Queue(context, PhilmartConstants.Email.BuyerWelcome, buyer.Email, buyerId, null,
                        "Welcome to PHILMART",
                        "Hi " + (buyer.FullName ?? "there") + ",\n\nYour PHILMART registration is complete. You can now buy and bid on the marketplace.\n",
                        new { name = buyer.FullName },
                        cancellationToken);
                }

                await context.AsSystem(PhilmartConstants.ActorKind.Buyer, () =>
                    AuditSql.Add(context, buyerId, PhilmartConstants.ActorKind.Buyer, null, "Buy_Buyer", buyerId.ToString(),
                        renewal ? "Buy_Buyer.legal_renewed" : "Buy_Buyer.registration_completed",
                        new { Documents = versions }, cancellationToken: cancellationToken),
                    cancellationToken);

                return true;
            }, cancellationToken);
        }
    }

    private Guid RequireBuyer()
    {
        if (!tenant.IsBuyer || tenant.ActorId == null)
        {
            throw new NotAuthorisedException("Sign in as a buyer to do this.");
        }

        return tenant.ActorId.Value;
    }

    // D039: once registered, identity is read-only. TR_buyer_identity_readonly
    // backs this up, this just gives a proper message first.
    private static void CheckCanEdit(BuyerRow buyer)
    {
        if (buyer.RegistrationCompletedAt != null)
        {
            throw new BusinessRuleViolationException("Your registration is complete. Identity details can't be changed now.", "D039");
        }
    }

    private static async Task<BuyerRow> LoadBuyer(PhilmartContext context, Guid buyerId, CancellationToken cancellationToken)
    {
        var buyer = await context.Database
            .SqlQuery<BuyerRow>($"SELECT ID, Email, FullName, EmailVerifiedAt, RegistrationCompletedAt, RegistrationStep FROM philmart.Buy_Buyer WHERE ID = {buyerId}")
            .FirstOrDefaultAsync(cancellationToken);

        if (buyer == null)
        {
            throw new NotFoundException("Buyer", buyerId);
        }

        return buyer;
    }

    public static async Task<List<LegalDocumentDTO>> CurrentDocuments(PhilmartContext context, CancellationToken cancellationToken)
    {
        var docs = await context.Database
            .SqlQuery<LegalDocumentDTO>($@"SELECT v.ID AS VersionID, d.Code, d.Name, v.Version, d.AcceptanceMode, v.Body
                                           FROM philmart.Sys_LegalDocumentVersion v
                                           JOIN philmart.Sys_LegalDocument d ON d.Code = v.DocumentCode
                                           WHERE v.PublishedAt IS NOT NULL AND v.SupersededAt IS NULL
                                             AND d.Code IN ('LEGAL-BUY-001', 'LEGAL-AUC-001', 'LEGAL-PRV-001')")
            .ToListAsync(cancellationToken);

        return docs.OrderBy(x => Array.IndexOf(AuthService.BuyerDocuments, x.Code)).ToList();
    }

    private static string? Trim(string? value, int max)
    {
        if (value == null || value.Length <= max)
        {
            return value;
        }

        return value.Substring(0, max);
    }

    private class BuyerRow
    {
        public Guid ID { get; set; }

        public string Email { get; set; } = null!;

        public string? FullName { get; set; }

        public DateTimeOffset? EmailVerifiedAt { get; set; }

        public DateTimeOffset? RegistrationCompletedAt { get; set; }

        public byte RegistrationStep { get; set; }
    }
}
