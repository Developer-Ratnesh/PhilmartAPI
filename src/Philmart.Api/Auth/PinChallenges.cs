using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Memory;
using Philmart.Application.Auth;

namespace Philmart.Api.Auth;

// The challenge is encrypted and signed, so the browser can't read or change it.
// Wrong guesses are counted in memory. Fine on one server, a second one would
// need a shared cache.
public class PinChallenges(IDataProtectionProvider provider, IMemoryCache cache) : IPinChallenges
{
    private const int MaxAttempts = 5;
    private const int MaxSendsPerHour = 5;
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    private readonly ITimeLimitedDataProtector protector =
        provider.CreateProtector("Philmart.BuyerPin").ToTimeLimitedDataProtector();

    public PinChallenge Create(string purpose, string email, Guid? buyerId)
    {
        string pin = NewPin();
        string nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));

        var payload = new Payload
        {
            Purpose = purpose,
            Email = email.Trim().ToLowerInvariant(),
            BuyerID = buyerId,
            Nonce = nonce,
            PinHash = Hash(nonce, pin)
        };

        string challenge = protector.Protect(JsonSerializer.Serialize(payload), Lifetime);
        return new PinChallenge { Challenge = challenge, Pin = pin };
    }

    public PinChallengeResult? Verify(string purpose, string challenge, string pin)
    {
        Payload? payload;

        try
        {
            payload = JsonSerializer.Deserialize<Payload>(protector.Unprotect(challenge));
        }
        catch (CryptographicException)
        {
            return null;
        }

        if (payload == null || payload.Purpose != purpose)
        {
            return null;
        }

        string key = "pin-tries:" + payload.Nonce;
        int tries = cache.GetOrCreate(key, x =>
        {
            x.AbsoluteExpirationRelativeToNow = Lifetime;
            return 0;
        });

        // a 4-digit PIN can't survive unlimited guessing
        if (tries >= MaxAttempts)
        {
            return null;
        }

        cache.Set(key, tries + 1, Lifetime);

        bool match = CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(payload.PinHash), Encoding.UTF8.GetBytes(Hash(payload.Nonce, pin.Trim())));

        if (!match)
        {
            return null;
        }

        // one use only
        cache.Set(key, MaxAttempts, Lifetime);
        return new PinChallengeResult { Email = payload.Email, BuyerID = payload.BuyerID };
    }

    public bool CanSend(string email)
    {
        string key = "pin-sends:" + email.Trim().ToLowerInvariant();
        int sent = cache.GetOrCreate(key, x =>
        {
            x.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
            return 0;
        });

        if (sent >= MaxSendsPerHour)
        {
            return false;
        }

        cache.Set(key, sent + 1, TimeSpan.FromHours(1));
        return true;
    }

    // tests swap this for a known PIN
    protected virtual string NewPin()
    {
        return RandomNumberGenerator.GetInt32(0, 10000).ToString("D4");
    }

    private static string Hash(string nonce, string pin)
    {
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(nonce + ":" + pin)));
    }

    private class Payload
    {
        public string Purpose { get; set; } = "";

        public string Email { get; set; } = "";

        public Guid? BuyerID { get; set; }

        public string Nonce { get; set; } = "";

        public string PinHash { get; set; } = "";
    }
}
