using System.Net;
using System.Security.Claims;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class IdentitySecurityTests
{
    private const string TestOrigin = "https://identity.gainer.test";

    [TestMethod]
    public async Task ApplicationCookieIsHostBoundAndSurvivesApplicationRestart()
    {
        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-identity-{Guid.NewGuid():N}");

        try
        {
            string cookie;
            await using (WebApplication firstApp = await CreateApplicationAsync(keyRingPath))
            {
                using HttpClient firstClient = firstApp.GetTestClient();
                firstClient.BaseAddress = new Uri(TestOrigin);
                using var signInRequest = new HttpRequestMessage(HttpMethod.Post, "/test/sign-in");
                signInRequest.Headers.Add("Origin", TestOrigin);
                using HttpResponseMessage signInResponse = await firstClient.SendAsync(signInRequest);

                Assert.AreEqual(HttpStatusCode.NoContent, signInResponse.StatusCode);
                string setCookie = signInResponse.Headers.GetValues("Set-Cookie").Single();
                StringAssert.StartsWith(setCookie, $"{GainerIdentityOptions.ApplicationCookieName}=");
                StringAssert.Contains(setCookie, "; path=/", StringComparison.OrdinalIgnoreCase);
                StringAssert.Contains(setCookie, "; secure", StringComparison.OrdinalIgnoreCase);
                StringAssert.Contains(setCookie, "; httponly", StringComparison.OrdinalIgnoreCase);
                StringAssert.Contains(setCookie, "; samesite=lax", StringComparison.OrdinalIgnoreCase);
                Assert.IsFalse(setCookie.Contains("domain=", StringComparison.OrdinalIgnoreCase));
                cookie = setCookie.Split(';', 2)[0];

                CookieAuthenticationOptions cookieOptions = firstApp.Services
                    .GetRequiredService<IOptionsMonitor<CookieAuthenticationOptions>>()
                    .Get(IdentityConstants.ApplicationScheme);
                Assert.AreEqual(CookieSecurePolicy.Always, cookieOptions.Cookie.SecurePolicy);
                Assert.AreEqual(SameSiteMode.Lax, cookieOptions.Cookie.SameSite);
            }

            await using WebApplication restartedApp = await CreateApplicationAsync(keyRingPath);
            using HttpClient restartedClient = restartedApp.GetTestClient();
            using var protectedRequest = new HttpRequestMessage(HttpMethod.Get, "/test/protected");
            protectedRequest.Headers.Add("Cookie", cookie);

            using HttpResponseMessage protectedResponse = await restartedClient.SendAsync(protectedRequest);
            string protectedResponseBody = await protectedResponse.Content.ReadAsStringAsync();

            Assert.AreEqual(HttpStatusCode.NoContent, protectedResponse.StatusCode, protectedResponseBody);
            SecurityStampValidatorOptions stampOptions = restartedApp.Services
                .GetRequiredService<IOptions<SecurityStampValidatorOptions>>()
                .Value;
            Assert.AreEqual(GainerIdentityOptions.SecurityStampValidationInterval, stampOptions.ValidationInterval);
            Assert.IsTrue(Directory.EnumerateFiles(keyRingPath, "*.xml").Any());
        }
        finally
        {
            if (Directory.Exists(keyRingPath))
            {
                Directory.Delete(keyRingPath, recursive: true);
            }
        }
    }

    private static async Task<WebApplication> CreateApplicationAsync(string keyRingPath)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.Logging.AddConsole();
        builder.WebHost.UseTestServer();
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = TestOrigin;
        builder.Configuration["ConnectionStrings:gainer-db"] =
            "Host=127.0.0.1;Port=1;Database=unused;Username=unused;Password=unused";
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();

        var app = builder.Build();
        app.MapGainerApi();
        app.MapPost("/test/sign-in", async context =>
        {
            var identity = new ClaimsIdentity(
                [new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString())],
                IdentityConstants.ApplicationScheme);
            await context.SignInAsync(
                IdentityConstants.ApplicationScheme,
                new ClaimsPrincipal(identity),
                new AuthenticationProperties { IssuedUtc = DateTimeOffset.UtcNow });
            context.Response.StatusCode = StatusCodes.Status204NoContent;
        });
        app.MapGet("/test/protected", () => Results.NoContent()).RequireAuthorization();
        await app.StartAsync();

        return app;
    }
}
