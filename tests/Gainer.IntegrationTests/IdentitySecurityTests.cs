using System.Security.Claims;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class IdentitySecurityTests
{
    [TestMethod]
    public async Task AccessTokensAreShortLivedAndSurviveApplicationRestart()
    {
        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-identity-{Guid.NewGuid():N}");

        try
        {
            string userId = Guid.NewGuid().ToString();
            string accessToken;
            await using (WebApplication firstApp = await CreateApplicationAsync(keyRingPath))
            {
                BearerTokenOptions options = BearerOptions(firstApp);
                Assert.AreEqual(GainerIdentityOptions.AccessTokenLifetime, options.BearerTokenExpiration);
                Assert.AreEqual(TimeSpan.FromMinutes(15), options.BearerTokenExpiration);
                var identity = new ClaimsIdentity(
                    [new Claim(ClaimTypes.NameIdentifier, userId)],
                    GainerIdentityOptions.AuthenticationScheme);
                accessToken = options.BearerTokenProtector.Protect(new AuthenticationTicket(
                    new ClaimsPrincipal(identity),
                    GainerIdentityOptions.AuthenticationScheme));
            }

            await using WebApplication restartedApp = await CreateApplicationAsync(keyRingPath);
            AuthenticationTicket? restored = BearerOptions(restartedApp).BearerTokenProtector.Unprotect(accessToken);

            Assert.IsNotNull(restored);
            Assert.AreEqual(userId, restored.Principal.FindFirstValue(ClaimTypes.NameIdentifier));
            Assert.IsNotEmpty(Directory.EnumerateFiles(keyRingPath, "*.xml"));
        }
        finally
        {
            if (Directory.Exists(keyRingPath))
            {
                Directory.Delete(keyRingPath, recursive: true);
            }
        }
    }

    private static BearerTokenOptions BearerOptions(WebApplication app) =>
        app.Services
            .GetRequiredService<IOptionsMonitor<BearerTokenOptions>>()
            .Get(GainerIdentityOptions.AuthenticationScheme);

    private static async Task<WebApplication> CreateApplicationAsync(string keyRingPath)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration["ConnectionStrings:gainer-db"] =
            "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused";
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();

        return app;
    }
}
