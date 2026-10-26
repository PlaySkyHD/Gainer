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
        var operatorAuth = new TestSession();
        using HttpClient client = CreateClient(test.App);
        await LoginAsync(client, operatorAuth, OperatorEmail, OperatorPassword);

        InvitationResponse invitation = await IssueInvitationAsync(
            client,
            operatorAuth,
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

        var inviteeAuth = new TestSession();
        using HttpResponseMessage activation = await SendMutationAsync(
            client,
            inviteeAuth,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(token, InviteePassword));
        Assert.AreEqual(HttpStatusCode.NoContent, activation.StatusCode);

        await LoginAsync(client, inviteeAuth, "invitee@example.test", InviteePassword);
    }

    [TestMethod]
    public async Task AnonymousAcceptEndpointIsRateLimitedWithoutSharingTheLoginBudget()
    {
        await using TestApplication test = await CreateApplicationAsync();
        using HttpClient client = CreateClient(test.App);
        var anonymousAuth = new TestSession();

        for (int attempt = 0; attempt < 30; attempt++)
        {
            using HttpResponseMessage rejected = await AcceptInvalidAsync(client, anonymousAuth, "unknown-token");
            Assert.AreEqual(HttpStatusCode.BadRequest, rejected.StatusCode);
        }

        using HttpResponseMessage limited = await AcceptInvalidAsync(client, anonymousAuth, "unknown-token");
        Assert.AreEqual(HttpStatusCode.TooManyRequests, limited.StatusCode);

        // The sign-in budget is a separate partition, so accept attempts cannot lock out login.
        using HttpResponseMessage login = await SendMutationAsync(
            client, anonymousAuth, "/api/v1/auth/login", new { email = "nobody@example.test", password = "wrong-password-42!" });
        Assert.AreNotEqual(HttpStatusCode.TooManyRequests, login.StatusCode);
    }

    [TestMethod]
    public async Task ExpiredReusedAndUnknownInvitationsReturnTheSameNeutralFailure()
    {
        var time = new MutableTimeProvider(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero));
        await using TestApplication test = await CreateApplicationAsync(time);
        await CreateOperatorAsync(test.App);
        using HttpClient client = CreateClient(test.App);
        var operatorAuth = new TestSession();
        await LoginAsync(client, operatorAuth, OperatorEmail, OperatorPassword);
        InvitationResponse first = await IssueInvitationAsync(client, operatorAuth, "first@example.test");
        InvitationResponse second = await IssueInvitationAsync(client, operatorAuth, "second@example.test");

        var anonymousAuth = new TestSession();
        using HttpResponseMessage accepted = await SendMutationAsync(
            client,
            anonymousAuth,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(ExtractToken(first.ActivationPath), InviteePassword));
        Assert.AreEqual(HttpStatusCode.NoContent, accepted.StatusCode);

        time.Advance(AccountInvitationOptions.Lifetime + TimeSpan.FromSeconds(1));
        using HttpResponseMessage reused = await AcceptInvalidAsync(
            client,
            anonymousAuth,
            ExtractToken(first.ActivationPath));
        using HttpResponseMessage expired = await AcceptInvalidAsync(
            client,
            anonymousAuth,
            ExtractToken(second.ActivationPath));
        using HttpResponseMessage unknown = await AcceptInvalidAsync(
            client,
            anonymousAuth,
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
        var operatorAuth = new TestSession();
        await LoginAsync(client, operatorAuth, OperatorEmail, OperatorPassword);
        InvitationResponse invitation = await IssueInvitationAsync(
            client,
            operatorAuth,
            "member@example.test");

        var memberAuth = new TestSession();
        using HttpResponseMessage activation = await SendMutationAsync(
            client,
            memberAuth,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(ExtractToken(invitation.ActivationPath), InviteePassword));
        Assert.AreEqual(HttpStatusCode.NoContent, activation.StatusCode);
        await LoginAsync(client, memberAuth, "member@example.test", InviteePassword);

        Guid memberId;
        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            memberId = (await users.FindByEmailAsync("member@example.test"))?.Id
                ?? throw new InvalidOperationException("The invited member was not created.");
        }

        using HttpResponseMessage disabled = await SetAccountStatusAsync(
            client,
            operatorAuth,
            memberId,
            isActive: false);
        Assert.AreEqual(HttpStatusCode.NoContent, disabled.StatusCode);
        using HttpResponseMessage revokedSession = await SendGetAsync(
            client,
            memberAuth,
            "/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.Unauthorized, revokedSession.StatusCode);
        using HttpResponseMessage disabledLogin = await SendMutationAsync(
            client,
            memberAuth,
            "/api/v1/auth/login",
            new LoginRequest("member@example.test", InviteePassword));
        Assert.AreEqual(HttpStatusCode.Unauthorized, disabledLogin.StatusCode);

        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            AppDbContext database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.AreEqual(memberId, (await database.Users.SingleAsync(user => user.Id == memberId)).Id);
            Assert.AreEqual(1, await database.AccountInvitations.CountAsync(item => item.UserId == memberId));
        }

        using HttpResponseMessage enabled = await SetAccountStatusAsync(
            client,
            operatorAuth,
            memberId,
            isActive: true);
        Assert.AreEqual(HttpStatusCode.NoContent, enabled.StatusCode);
        await LoginAsync(client, memberAuth, "member@example.test", InviteePassword);
    }

    [TestMethod]
    public async Task OperatorCannotDeactivateTheirOwnAccount()
    {
        await using TestApplication test = await CreateApplicationAsync();
        await CreateOperatorAsync(test.App);
        using HttpClient client = CreateClient(test.App);
        var operatorAuth = new TestSession();
        await LoginAsync(client, operatorAuth, OperatorEmail, OperatorPassword);

        Guid operatorId;
        await using (AsyncServiceScope scope = test.App.Services.CreateAsyncScope())
        {
            UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            operatorId = (await users.FindByEmailAsync(OperatorEmail))?.Id
                ?? throw new InvalidOperationException("The operator was not created.");
        }

        using HttpResponseMessage self = await SetAccountStatusAsync(
            client,
            operatorAuth,
            operatorId,
            isActive: false);
        using JsonDocument problem = JsonDocument.Parse(await self.Content.ReadAsStringAsync());
        Assert.AreEqual(HttpStatusCode.Conflict, self.StatusCode);
        Assert.AreEqual("operator_self_deactivation", problem.RootElement.GetProperty("code").GetString());
        Assert.AreEqual(
            self.Headers.GetValues("X-Correlation-Id").Single(),
            problem.RootElement.GetProperty("correlationId").GetString());
        Assert.IsFalse(string.IsNullOrWhiteSpace(problem.RootElement.GetProperty("traceId").GetString()));

        // The operator stays active and can keep using the session.
        using HttpResponseMessage session = await SendGetAsync(client, operatorAuth, "/api/v1/auth/session");
        Assert.AreEqual(HttpStatusCode.OK, session.StatusCode);
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
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
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
        TestSession auth,
        string email,
        string password)
    {
        TokenResponse tokens = await BearerTestClient.LoginAsync(client, email, password);
        auth.AccessToken = tokens.AccessToken;
    }

    private static async Task<InvitationResponse> IssueInvitationAsync(
        HttpClient client,
        TestSession auth,
        string email)
    {
        using HttpResponseMessage response = await SendMutationAsync(
            client,
            auth,
            "/api/v1/account-operator/invitations",
            new CreateInvitationRequest(email));
        Assert.AreEqual(HttpStatusCode.Created, response.StatusCode, await response.Content.ReadAsStringAsync());
        return await response.Content.ReadFromJsonAsync<InvitationResponse>()
            ?? throw new InvalidOperationException("The invitation response was empty.");
    }

    private static async Task<HttpResponseMessage> AcceptInvalidAsync(
        HttpClient client,
        TestSession auth,
        string token) =>
        await SendMutationAsync(
            client,
            auth,
            "/api/v1/auth/invitations/accept",
            new AcceptInvitationRequest(token, InviteePassword));

    private static async Task<HttpResponseMessage> SetAccountStatusAsync(
        HttpClient client,
        TestSession auth,
        Guid accountId,
        bool isActive)
    {
        return await SendMutationAsync(
            client,
            auth,
            $"/api/v1/account-operator/accounts/{accountId}/status",
            new SetAccountStatusRequest(isActive),
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

    private static async Task<HttpResponseMessage> SendMutationAsync<TBody>(
        HttpClient client,
        TestSession auth,
        string path,
        TBody body,
        HttpMethod? method = null)
    {
        var request = new HttpRequestMessage(method ?? HttpMethod.Post, path)
        {
            Content = JsonContent.Create(body),
        };
        auth.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        request.Dispose();
        return response;
    }

    private static async Task<HttpResponseMessage> SendGetAsync(
        HttpClient client,
        TestSession auth,
        string path)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
        auth.Apply(request);
        HttpResponseMessage response = await client.SendAsync(request);
        request.Dispose();
        return response;
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
