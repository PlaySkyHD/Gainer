using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;

namespace Gainer.Api.Security;

/// <summary>Stable security settings for mobile device sessions.</summary>
public static class GainerIdentityOptions
{
    /// <summary>The bearer scheme that authenticates every API request.</summary>
    public static readonly string AuthenticationScheme = IdentityConstants.BearerScheme;

    /// <summary>Claim carrying the device session an access token belongs to.</summary>
    public const string DeviceSessionClaimType = "gainer:device_session";

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
            })
            .AddRoles<IdentityRole<Guid>>()
            .AddEntityFrameworkStores<AppDbContext>()
            .AddSignInManager()
            .AddDefaultTokenProviders();
        builder.Services.AddScoped<IUserConfirmation<AppUser>, GainerUserConfirmation>();
        builder.Services
            .AddAuthentication(GainerIdentityOptions.AuthenticationScheme)
            .AddBearerToken(GainerIdentityOptions.AuthenticationScheme, options =>
                options.BearerTokenExpiration = GainerIdentityOptions.AccessTokenLifetime);
        builder.Services.AddAuthorizationBuilder().AddPolicy(
            AccountOperatorAuthorization.PolicyName,
            policy => policy.RequireRole(AccountOperatorAuthorization.RoleName));
        builder.Services.AddScoped<AccessTokenIssuer>();
        builder.Services.AddScoped<IInitialAccountOperatorProvisioner, InitialAccountOperatorProvisioner>();

        return builder;
    }
}
