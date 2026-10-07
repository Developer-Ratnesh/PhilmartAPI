using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Philmart.Api.Auth;
using Philmart.Application.Auth;

namespace Philmart.IntegrationTests.Support;

// The real API in memory, pointed at the test database. The auction job is off
// so tests run the sweep themselves, after moving the test clock.
public class ApiFactory(string connectionString) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        // UseSetting, because Program reads these before later config is added
        builder.UseSetting("ConnectionStrings:Philmart", connectionString);
        builder.UseSetting("Jobs:Enabled", "false");
        builder.UseSetting("Auth:SigningKey", "integration-tests-only-signing-key-0123456789");
        builder.UseSetting("Web:BaseUrl", "http://test.local");
        builder.UseSetting("Support:RequestsPerHour", "1000");

        builder.ConfigureTestServices(services =>
        {
            services.AddSingleton<IPinChallenges, KnownPins>();
        });
    }

    public HttpClient As(string? token)
    {
        var client = CreateClient();
        if (token != null)
        {
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        return client;
    }

    // Buyers go through the emailed PIN like the real screen, shop users and
    // admins use their password
    public async Task<string> SignIn(string email, string password, string kind)
    {
        HttpResponseMessage response;

        if (kind == "buyer")
        {
            var pin = await CreateClient().PostAsJsonAsync("/api/auth/buyer/pin", new { email });
            pin.EnsureSuccessStatusCode();
            var challenge = await pin.Content.ReadFromJsonAsync<ChallengeBody>();

            response = await CreateClient().PostAsJsonAsync("/api/auth/buyer/verify", new { challenge = challenge!.Challenge, pin = KnownPins.Pin });
        }
        else
        {
            response = await CreateClient().PostAsJsonAsync("/api/auth/login", new { email, password, kind });
        }

        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<TokenBody>();
        return body!.Token;
    }

    private class TokenBody
    {
        public string Token { get; set; } = "";
    }

    private class ChallengeBody
    {
        public string Challenge { get; set; } = "";
    }
}

// every PIN is 4321, so tests can sign buyers in without reading their email
public class KnownPins(IDataProtectionProvider provider, IMemoryCache cache) : PinChallenges(provider, cache)
{
    public const string Pin = "4321";

    protected override string NewPin()
    {
        return Pin;
    }
}
