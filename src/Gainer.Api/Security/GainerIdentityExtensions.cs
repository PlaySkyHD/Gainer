using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;

namespace Gainer.Api.Security;

/// <summary>Stable security settings for the browser session.</summary>
public static class GainerIdentityOptions
{
    /// <summary>The host-only application cookie.</summary>
    public const string ApplicationCookieName = "__Host-Gainer.Auth";

    /// <summary>Configuration key for the durable data-protection key ring.</summary>
    public const string DataProtectionKeysPathConfigurationKey = "Security:DataProtection:KeysPath";

    /// <summary>Maximum delay before Identity revalidates a session against the user store.</summary>
    public static readonly TimeSpan SecurityStampValidationInterval = TimeSpan.FromMinutes(1);

    /// <summary>Absolute lifetime of an authenticated browser session.</summary>
    public static readonly TimeSpan ApplicationCookieLifetime = TimeSpan.FromHours(12);
}

/// <summary>Registers the Identity session boundary for the API.</summary>
public static class GainerIdentityExtensions
{
    private const string DataProtectionApplicationName = "Gainer";
    private const string DefaultKeysDirectoryName = ".data-protection-keys";

    /// <summary>Adds Identity, its secure application cookie, and a durable data-protection key ring.</summary>
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
            .AddIdentity<AppUser, IdentityRole<Guid>>(options =>
            {
                options.User.RequireUniqueEmail = true;
                options.SignIn.RequireConfirmedAccount = true;
            })
            .AddEntityFrameworkStores<AppDbContext>()
            .AddDefaultTokenProviders();
        builder.Services.AddScoped<IUserConfirmation<AppUser>, GainerUserConfirmation>();
        builder.Services.AddAuthorization(options => options.AddPolicy(
            AccountOperatorAuthorization.PolicyName,
            policy => policy.RequireRole(AccountOperatorAuthorization.RoleName)));
        builder.Services.AddScoped<IInitialAccountOperatorProvisioner, InitialAccountOperatorProvisioner>();
        builder.Services.ConfigureApplicationCookie(options =>
        {
            options.Cookie.Name = GainerIdentityOptions.ApplicationCookieName;
            options.Cookie.Domain = null;
            options.Cookie.Path = "/";
            options.Cookie.HttpOnly = true;
            options.Cookie.SameSite = SameSiteMode.Lax;
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.Cookie.IsEssential = true;
            options.ExpireTimeSpan = GainerIdentityOptions.ApplicationCookieLifetime;
            options.SlidingExpiration = false;
            options.Events.OnRedirectToLogin = ReturnUnauthorizedAsync;
            options.Events.OnRedirectToAccessDenied = ReturnForbiddenAsync;
        });
        builder.Services.Configure<SecurityStampValidatorOptions>(options =>
            options.ValidationInterval = GainerIdentityOptions.SecurityStampValidationInterval);

        return builder;
    }

    private static Task ReturnUnauthorizedAsync(RedirectContext<CookieAuthenticationOptions> context)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return Task.CompletedTask;
    }

    private static Task ReturnForbiddenAsync(RedirectContext<CookieAuthenticationOptions> context)
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        return Task.CompletedTask;
    }
}
