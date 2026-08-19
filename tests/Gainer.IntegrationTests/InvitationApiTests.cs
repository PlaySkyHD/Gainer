using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class InvitationApiTests
{
    private const string TestOrigin = "https://invitations.gainer.test";
    private const string OperatorEmail = "operator@example.test";
    private const string OperatorPassword = "Operator-password-42!";
    private const string InviteePassword = "Invitee-password-42!";
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> keyRingPaths = [];

    private static PostgreSqlTestFixture Fixture =>
        fixture ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    [ClassInitialize]
    public static async Task StartPostgreSqlAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopPostgreSqlAsync()
    {
        if (fixture is not null)
        {
            await fixture.DisposeAsync();
        }
    }

    [TestCleanup]
    public void DeleteKeyRings()
    {
        foreach (string path in keyRingPaths.Where(Directory.Exists))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    [TestMethod]
    public async Task OperatorCanIssueAndInviteeCanActivateAHashOnlyInvitation()
    {
        await using TestApplication test = await CreateApplicationAsync();
        await CreateOperatorAsync(test.App);
        var operatorCookies = new CookieJar();
        using HttpClient client = CreateClient(test.App);
        await LoginAsync(client, operatorCookies, OperatorEmail, OperatorPassword);

        InvitationResponse invitation = await IssueInvitationAsync(
            client,
            operatorCookies,
            "invitee@example.test");
        string token = ExtractToken(invitation.ActivationPath);

        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            AccountInvitation stored = await database.AccountInvitations.SingleAsync();
            Assert.HasCount(32, stored.TokenHash);
            Assert.IsFalse(Convert.ToHexString(stored.TokenHash).Contains(token, StringComparison.Ordinal));
            Assert.IsFalse(typeof(AccountInvitation).GetProperties().Any(property =>
                property.PropertyType == typeof(string)
                && property.Name.Contains("Token", StringComparison.Ordinal)));
        }

        var inviteeCookies = new CookieJar();
        AntiforgeryTokenResponse tokenPair = await GetAntiforgeryTokenAsync(client, inviteeCookies);
        using HttpResponseMessage activation = await SendMutationAsync(
            client,
            inviteeCookies,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(token, InviteePassword),
            tokenPair.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, activation.StatusCode);

        await LoginAsync(client, inviteeCookies, "invitee@example.test", InviteePassword);
    }

    [TestMethod]
    public async Task ExpiredReusedAndUnknownInvitationsReturnTheSameNeutralFailure()
    {
        var time = new MutableTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero));
        await using TestApplication test = await CreateApplicationAsync(time);
        await CreateOperatorAsync(test.App);
        using HttpClient client = CreateClient(test.App);
        var operatorCookies = new CookieJar();
        await LoginAsync(client, operatorCookies, OperatorEmail, OperatorPassword);
        InvitationResponse first = await IssueInvitationAsync(client, operatorCookies, "first@example.test");
        InvitationResponse second = await IssueInvitationAsync(client, operatorCookies, "second@example.test");

        var anonymousCookies = new CookieJar();
        AntiforgeryTokenResponse requestToken = await GetAntiforgeryTokenAsync(client, anonymousCookies);
        using HttpResponseMessage accepted = await SendMutationAsync(
            client,
            anonymousCookies,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(ExtractToken(first.ActivationPath), InviteePassword),
            requestToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, accepted.StatusCode);

        time.Advance(AccountInvitationOptions.Lifetime + TimeSpan.FromSeconds(1));
        using HttpResponseMessage reused = await AcceptInvalidAsync(
            client,
            anonymousCookies,
            requestToken.RequestToken,
            ExtractToken(first.ActivationPath));
        using HttpResponseMessage expired = await AcceptInvalidAsync(
            client,
            anonymousCookies,
            requestToken.RequestToken,
            ExtractToken(second.ActivationPath));
        using HttpResponseMessage unknown = await AcceptInvalidAsync(
            client,
            anonymousCookies,
            requestToken.RequestToken,
            "unknown-invitation-token");

        string reusedBody = await reused.Content.ReadAsStringAsync();
        string expiredBody = await expired.Content.ReadAsStringAsync();
        string unknownBody = await unknown.Content.ReadAsStringAsync();
        Assert.AreEqual(HttpStatusCode.BadRequest, reused.StatusCode);
        Assert.AreEqual(reused.StatusCode, expired.StatusCode);
        Assert.AreEqual(reused.StatusCode, unknown.StatusCode);
        AssertProblemIdentity(reusedBody, expiredBody);
        AssertProblemIdentity(reusedBody, unknownBody);
        Assert.IsFalse(reusedBody.Contains("used", StringComparison.OrdinalIgnoreCase));
        Assert.IsFalse(expiredBody.Contains("expired", StringComparison.OrdinalIgnoreCase));
    }

    [TestMethod]
    public async Task DeactivationRevokesSessionAndReactivationPreservesTheAccount()
    {
        await using TestApplication test = await CreateApplicationAsync();
        await CreateOperatorAsync(test.App);
        using HttpClient client = CreateClient(test.App);
        var operatorCookies = new CookieJar();
        await LoginAsync(client, operatorCookies, OperatorEmail, OperatorPassword);
        InvitationResponse invitation = await IssueInvitationAsync(
            client,
            operatorCookies,
            "member@example.test");

        var memberCookies = new CookieJar();
        AntiforgeryTokenResponse memberToken = await GetAntiforgeryTokenAsync(client, memberCookies);
        using HttpResponseMessage activation = await SendMutationAsync(
            client,
            memberCookies,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(ExtractToken(invitation.ActivationPath), InviteePassword),
            memberToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, activation.StatusCode);
        await LoginAsync(client, memberCookies, "member@example.test", InviteePassword);

        Guid memberId;
        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            memberId = (await users.FindByEmailAsync("member@example.test"))?.Id
                ?? throw new InvalidOperationException("The invited member was not created.");
        }

        using HttpResponseMessage disabled = await SetAccountStatusAsync(
            client,
            operatorCookies,
            memberId,
            isActive: false);
        Assert.AreEqual(HttpStatusCode.NoContent, disabled.StatusCode);
        using HttpResponseMessage revokedSession = await SendGetAsync(
            client,
            memberCookies,
            "/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, revokedSession.StatusCode);

        AntiforgeryTokenResponse disabledLoginToken = await GetAntiforgeryTokenAsync(client, memberCookies);
        using HttpResponseMessage disabledLogin = await SendMutationAsync(
            client,
            memberCookies,
            "/api/v1/auth/login",
            new LoginRequest("member@example.test", InviteePassword),
            disabledLoginToken.RequestToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, disabledLogin.StatusCode);

        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.AreEqual(memberId, (await database.Users.SingleAsync(user => user.Id == memberId)).Id);
            Assert.AreEqual(1, await database.AccountInvitations.CountAsync(item => item.UserId == memberId));
        }

        using HttpResponseMessage enabled = await SetAccountStatusAsync(
            client,
            operatorCookies,
            memberId,
            isActive: true);
        Assert.AreEqual(HttpStatusCode.NoContent, enabled.StatusCode);
        await LoginAsync(client, memberCookies, "member@example.test", InviteePassword);
    }

    private async Task<TestApplication> CreateApplicationAsync(TimeProvider? timeProvider = null)
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-invitations-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerRequestSecurityOptions.FrontendOriginConfigurationKey] = TestOrigin;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        builder.Services.PostConfigure<SecurityStampValidatorOptions>(options =>
            options.ValidationInterval = TimeSpan.Zero);
        if (timeProvider is not null)
        {
            builder.Services.RemoveAll<TimeProvider>();
            builder.Services.AddSingleton(timeProvider);
        }

        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync();
        return new TestApplication(app, connectionString);
    }

    private static async Task CreateOperatorAsync(WebApplication app)
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        RoleManager<IdentityRole<Guid>> roles = scope.ServiceProvider
            .GetRequiredService<RoleManager<IdentityRole<Guid>>>();
        Assert.IsTrue((await roles.CreateAsync(
            new IdentityRole<Guid>(AccountOperatorAuthorization.RoleName))).Succeeded);
        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = OperatorEmail,
            Email = OperatorEmail,
            EmailConfirmed = true,
        };
        Assert.IsTrue((await users.CreateAsync(user, OperatorPassword)).Succeeded);
        Assert.IsTrue((await users.AddToRoleAsync(user, AccountOperatorAuthorization.RoleName)).Succeeded);
    }

    private static async Task LoginAsync(
        HttpClient client,
        CookieJar cookies,
        string email,
        string password)
    {
        AntiforgeryTokenResponse token = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/login",
            new LoginRequest(email, password),
            token.RequestToken);
        Assert.AreEqual(HttpStatusCode.NoContent, response.StatusCode, await response.Content.ReadAsStringAsync());
    }

    private static async Task<InvitationResponse> IssueInvitationAsync(
        HttpClient client,
        CookieJar cookies,
        string email)
    {
        AntiforgeryTokenResponse token = await GetAntiforgeryTokenAsync(client, cookies);
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            cookies,
            "/api/v1/account-operator/invitations",
            new CreateInvitationRequest(email),
            token.RequestToken);
        Assert.AreEqual(HttpStatusCode.Created, response.StatusCode, await response.Content.ReadAsStringAsync());
        return await response.Content.ReadFromJsonAsync<InvitationResponse>()
            ?? throw new InvalidOperationException("The invitation response was empty.");
    }

    private static async Task<HttpResponseMessage> AcceptInvalidAsync(
        HttpClient client,
        CookieJar cookies,
        string requestToken,
        string token) =>
        await SendMutationAsync(
            client,
            cookies,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(token, InviteePassword),
            requestToken);

    private static async Task<HttpResponseMessage> SetAccountStatusAsync(
        HttpClient client,
        CookieJar cookies,
        Guid accountId,
        bool isActive)
    {
        AntiforgeryTokenResponse token = await GetAntiforgeryTokenAsync(client, cookies);
        return await SendMutationAsync(
            client,
            cookies,
            $"/api/v1/account-operator/accounts/{accountId}/status",
            new SetAccountStatusRequest(isActive),
            token.RequestToken,
            HttpMethod.Put);
    }

    private static void AssertProblemIdentity(string expectedJson, string actualJson)
    {
        using JsonDocument expected = JsonDocument.Parse(expectedJson);
        using JsonDocument actual = JsonDocument.Parse(actualJson);
        Assert.AreEqual(
            expected.RootElement.GetProperty("title").GetString(),
            actual.RootElement.GetProperty("title").GetString());
        Assert.AreEqual(
            expected.RootElement.GetProperty("code").GetString(),
            actual.RootElement.GetProperty("code").GetString());
    }

    private static string ExtractToken(string activationPath)
    {
        const string marker = "token=";
        int index = activationPath.IndexOf(marker, StringComparison.Ordinal);
        Assert.IsGreaterThanOrEqualTo(0, index);
        return Uri.UnescapeDataString(activationPath[(index + marker.Length)..]);
    }

    private static HttpClient CreateClient(WebApplication app)
    {
        HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        return client;
    }

    private static async Task<AntiforgeryTokenResponse> GetAntiforgeryTokenAsync(
        HttpClient client,
        CookieJar cookies)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/antiforgery");
        cookies.Apply(request);
        using HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<AntiforgeryTokenResponse>()
            ?? throw new InvalidOperationException("The antiforgery response was empty.");
    }

    private static async Task<HttpResponseMessage> SendMutationAsync<TBody>(
        HttpClient client,
        CookieJar cookies,
        string path,
        TBody body,
        string requestToken,
        HttpMethod? method = null)
    {
        var request = new HttpRequestMessage(method ?? HttpMethod.Post, path)
        {
            Content = JsonContent.Create(body),
        };
        request.Headers.Add("Origin", TestOrigin);
        request.Headers.Add(GainerRequestSecurityOptions.AntiforgeryHeaderName, requestToken);
        cookies.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        request.Dispose();
        return response;
    }

    private static async Task<HttpResponseMessage> SendGetAsync(
        HttpClient client,
        CookieJar cookies,
        string path)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
        cookies.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        cookies.Capture(response);
        request.Dispose();
        return response;
    }

    private sealed class CookieJar
    {
        private readonly Dictionary<string, string> values = new(StringComparer.Ordinal);

        public void Capture(HttpResponseMessage response)
        {
            if (!response.Headers.TryGetValues("Set-Cookie", out IEnumerable<string>? headers))
            {
                return;
            }

            foreach (string header in headers)
            {
                string[] pair = header.Split(';', 2)[0].Split('=', 2);
                if (pair[1].Length == 0)
                {
                    values.Remove(pair[0]);
                }
                else
                {
                    values[pair[0]] = pair[1];
                }
            }
        }

        public void Apply(HttpRequestMessage request)
        {
            if (values.Count > 0)
            {
                request.Headers.Add("Cookie", string.Join("; ", values.Select(pair => $"{pair.Key}={pair.Value}")));
            }
        }
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset currentUtc = utcNow;

        public override DateTimeOffset GetUtcNow() => currentUtc;

        public void Advance(TimeSpan duration) => currentUtc += duration;
    }

    private sealed record TestApplication(WebApplication App, string ConnectionString) : IAsyncDisposable
    {
        public async ValueTask DisposeAsync() => await App.DisposeAsync();
    }
}
