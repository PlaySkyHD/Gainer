using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Gainer.Api.Security;

/// <summary>Stable security settings for mobile device sessions.</summary>
public static class GainerIdentityOptions
{
    /// <summary>The bearer scheme that authenticates every API request.</summary>
    public static readonly string AuthenticationScheme = IdentityConstants.BearerScheme;

    /// <summary>Claim carrying the device session an access token belongs to.</summary>
    public const string DeviceSessionClaimType = "gainer:device_session";

    /// <summary>Configuration key for the WebAuthn relying-party domain, e.g. <c>gainer.markfort.xyz</c>.</summary>
    public const string PasskeyServerDomainConfigurationKey = "Security:Passkeys:ServerDomain";

    /// <summary>Configuration key for the durable data-protection key ring.</summary>
    public const string DataProtectionKeysPathConfigurationKey = "Security:DataProtection:KeysPath";

    /// <summary>Lifetime of an access token. Revocation applies sooner because every request checks the session.</summary>
    public static readonly TimeSpan AccessTokenLifetime = TimeSpan.FromMinutes(15);
}

/// <summary>Registers Identity and bearer authentication for the API.</summary>
public static class GainerIdentityExtensions
{
    private const string DataProtectionApplicationName = "Gainer";
    private const string DefaultKeysDirectoryName = ".data-protection-keys";

    /// <summary>Adds Identity, bearer access tokens, and a durable data-protection key ring.</summary>
    public static WebApplicationBuilder AddGainerIdentity(this WebApplicationBuilder builder)
    {
        string configuredKeysPath = builder.Configuration[
            GainerIdentityOptions.DataProtectionKeysPathConfigurationKey]
            ?? DefaultKeysDirectoryName;
        string keysPath = Path.GetFullPath(configuredKeysPath, builder.Environment.ContentRootPath);

        builder.Services
            .AddDataProtection()
            .SetApplicationName(DataProtectionApplicationName)
            .PersistKeysToFileSystem(new DirectoryInfo(keysPath));

        builder.Services
            .AddIdentityCore<AppUser>(options =>
            {
                options.User.RequireUniqueEmail = true;
                options.SignIn.RequireConfirmedAccount = true;
                options.Stores.SchemaVersion = IdentitySchemaVersions.Version3;
            })
            .AddRoles<IdentityRole<Guid>>()
            .AddEntityFrameworkStores<AppDbContext>()
            .AddSignInManager()
            .AddDefaultTokenProviders();
        builder.Services.AddScoped<IUserConfirmation<AppUser>, GainerUserConfirmation>();
        AddPasskeys(builder);
        builder.Services
            .AddAuthentication(GainerIdentityOptions.AuthenticationScheme)
            .AddBearerToken(GainerIdentityOptions.AuthenticationScheme, options =>
                options.BearerTokenExpiration = GainerIdentityOptions.AccessTokenLifetime);
        // An endpoint without authorization metadata (Map* calls, minimal APIs, future additions) is
        // protected by default. Anonymous endpoints must opt out with [AllowAnonymous]/.AllowAnonymous().
        builder.Services.AddAuthorizationBuilder()
            .SetFallbackPolicy(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build())
            .AddPolicy(
                AccountOperatorAuthorization.PolicyName,
                policy => policy.RequireRole(AccountOperatorAuthorization.RoleName));
        builder.Services.AddScoped<AccessTokenIssuer>();
        builder.Services.AddScoped<DeviceSignIn>();
        builder.Services.AddScoped<IInitialAccountOperatorProvisioner, InitialAccountOperatorProvisioner>();

        return builder;
    }

    // The iOS app signs WebAuthn requests with the origin of its associated domain, which is the
    // relying party itself; there is no browser origin to compare with.
    private static void AddPasskeys(WebApplicationBuilder builder)
    {
        string serverDomain = builder.Configuration[GainerIdentityOptions.PasskeyServerDomainConfigurationKey]
            ?? throw new InvalidOperationException(
                $"{GainerIdentityOptions.PasskeyServerDomainConfigurationKey} must name the passkey domain.");
        string expectedOrigin = $"https://{serverDomain}";
        builder.Services.Configure<IdentityPasskeyOptions>(options =>
        {
            options.ServerDomain = serverDomain;
            options.UserVerificationRequirement = "required";
            options.ResidentKeyRequirement = "required";
            options.ValidateOrigin = context => ValueTask.FromResult(
                !context.CrossOrigin && string.Equals(context.Origin, expectedOrigin, StringComparison.Ordinal));
        });
        builder.Services.TryAddScoped<IPasskeyHandler<AppUser>, PasskeyHandler<AppUser>>();
        builder.Services.AddMemoryCache();
        builder.Services.AddSingleton<PasskeyCeremonyProtector>();
    }
}
