using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Philmart.Api.Auth;
using Philmart.Api.Jobs;
using Philmart.Api.Middleware;
using Philmart.Application.Auth;
using Philmart.Application.ShopUsers;
using Philmart.Domain.Abstractions;
using Philmart.Infrastructure;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((context, services, configuration) => configuration
    .ReadFrom.Configuration(context.Configuration)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();

builder.Services.AddHttpContextAccessor();

// built from the login token only, never from request input
builder.Services.AddScoped<ITenantContext, TenantContext>();

builder.Services.AddPhilmartInfrastructure(builder.Configuration);

// tests switch it off and drive the sweep themselves with the test clock
if (builder.Configuration.GetValue("Jobs:Enabled", true))
{
    builder.Services.AddHostedService<AuctionJob>();
    builder.Services.AddHostedService<EmailJob>();
}

var authSettings = builder.Configuration.GetSection("Auth").Get<AuthSettings>() ?? new AuthSettings();
if (authSettings.SigningKey.Length < 32)
{
    if (!builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException("Auth:SigningKey must be set to at least 32 characters.");
    }

    // dev only: a fresh key each run, so tokens stop working after a restart
    authSettings.SigningKey = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(48));
}

builder.Services.AddSingleton(authSettings);
builder.Services.AddSingleton<TokenIssuer>();
builder.Services.AddDataProtection();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<IPinChallenges, PinChallenges>();
builder.Services.AddSingleton<IInvitationTokens, InvitationTokens>();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = authSettings.Issuer,
            ValidAudience = authSettings.Audience,
            IssuerSigningKey = authSettings.Key(),
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

const string WebCors = "philmart-web";
builder.Services.AddCors(options =>
    options.AddPolicy(WebCors, policy => policy
        .WithOrigins(builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? new string[0])
        .AllowAnyHeader()
        .AllowAnyMethod()
        .AllowCredentials()));

// the support form is open to anyone, so cap it per address
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy(Program.SupportLimit, http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = builder.Configuration.GetValue("Support:RequestsPerHour", 10),
            Window = TimeSpan.FromHours(1)
        }));
});

var app = builder.Build();

// logging goes outside the error handler so it records the status the client really got
app.UseSerilogRequestLogging();
app.UseMiddleware<ExceptionHandlingMiddleware>();

// Swagger page at /swagger. Always on in development, elsewhere only when
// Swagger:Enabled is set (staging has it on for testing).
if (app.Environment.IsDevelopment() || app.Configuration.GetValue("Swagger:Enabled", false))
{
    app.MapOpenApi();
    app.UseSwaggerUI(options => options.SwaggerEndpoint("/openapi/v1.json", "PHILMART API v1"));
}

app.UseHttpsRedirection();
app.UseCors(WebCors);
app.UseAuthentication();
app.UseMiddleware<AccountCheckMiddleware>();
app.UseAuthorization();
app.UseRateLimiter();

app.MapControllers();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }))
   .AllowAnonymous()
   .WithName("Health");

app.Run();

// so the integration tests can use WebApplicationFactory
public partial class Program
{
    public const string SupportLimit = "support";
}
