using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using static Gainer.IntegrationTests.ConnectorOAuthEndpointTests;

namespace Gainer.IntegrationTests;

/// <summary>Connecting an assistant end to end: consent with a passkey, tokens, MCP tools and revocation.</summary>
[TestClass]
[DoNotParallelize]
public sealed class ConnectorFlowTests
{
    private const string BaseAddress = "https://gainer.markfort.xyz";
    private const string Password = "Correct-horse-42!";
    private static readonly DateTime Started = new(2026, 11, 20, 17, 0, 0, DateTimeKind.Utc);
    private static readonly string[] ExpectedTools =
    [
        "get_overview", "list_workouts", "get_workout", "search_exercises", "get_exercise_progress",
        "get_body_goals", "list_check_ins", "get_nutrition_days", "get_nutrition_targets", "list_saved_meals",
        "list_coach_notes", "get_strava_status",
    ];
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> keyRingPaths = [];
    private string connectionString = string.Empty;

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
    public async Task ApprovedAssistantReadsOnlyItsOwnersDataThroughMcp()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid owner = await CreateUserAsync(app, "owner@example.test");
        Guid other = await CreateUserAsync(app, "other@example.test");
        Guid ownWorkout = await SeedWorkoutAsync(owner, "Push");
        Guid foreignWorkout = await SeedWorkoutAsync(other, "Fremd");
        await SeedCheckInAsync(owner, new DateOnly(2026, 11, 19), 81.5m);
        await SeedCheckInAsync(other, new DateOnly(2026, 11, 20), 99m);
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient appClient = CreateClient(app);
        await appClient.AuthenticateAsync("owner@example.test", Password);
        await RegisterPasskeyAsync(appClient, authenticator);

        (string clientId, OAuthTokens tokens) = await ConnectAsync(app, authenticator);

        await using (McpClient mcp = await ConnectMcpAsync(app, tokens.AccessToken))
        {
            IList<McpClientTool> tools = await mcp.ListToolsAsync(cancellationToken: TestContext.CancellationToken);
            Assert.AreSequenceEqual(
                ExpectedTools.Order(StringComparer.Ordinal).ToArray(),
                tools.Select(tool => tool.Name).Order(StringComparer.Ordinal).ToArray());
            Assert.IsTrue(tools.All(tool => tool.ProtocolTool.Annotations?.ReadOnlyHint == true));

            CallToolResult listed = await CallAsync(mcp, "list_workouts", new() { ["limit"] = 10 });
            string listedText = Text(listed);
            Assert.Contains(ownWorkout.ToString(), listedText);
            Assert.DoesNotContain(foreignWorkout.ToString(), listedText);

            CallToolResult own = await CallAsync(mcp, "get_workout", new() { ["workoutId"] = ownWorkout });
            Assert.IsFalse(own.IsError ?? false);
            CallToolResult foreign = await CallAsync(mcp, "get_workout", new() { ["workoutId"] = foreignWorkout });
            Assert.IsTrue(foreign.IsError);
            Assert.DoesNotContain("Fremd", Text(foreign));

            CallToolResult overview = await CallAsync(mcp, "get_overview", new() { ["days"] = 30 });
            Assert.IsFalse(overview.IsError ?? false);
            CallToolResult previous = await CallAsync(mcp, "get_overview", new() { ["days"] = 7, ["endDaysAgo"] = 7 });
            Assert.IsFalse(previous.IsError ?? false);

            CallToolResult found = await CallAsync(mcp, "search_exercises", new() { ["limit"] = 5 });
            Assert.IsFalse(found.IsError ?? false);
            using JsonDocument exercises = JsonDocument.Parse(Text(found));
            Guid exerciseId = exercises.RootElement.GetProperty("exercises")[0].GetProperty("exerciseId").GetGuid();
            CallToolResult progress = await CallAsync(mcp, "get_exercise_progress", new() { ["exerciseId"] = exerciseId, ["days"] = 90 });
            Assert.IsFalse(progress.IsError ?? false);
            CallToolResult unknownExercise = await CallAsync(mcp, "get_exercise_progress", new() { ["exerciseId"] = Guid.NewGuid() });
            Assert.IsTrue(unknownExercise.IsError);

            // Body, nutrition and account data of the owner only.
            CallToolResult checkIns = await CallAsync(mcp, "list_check_ins", new()
            {
                ["from"] = "2026-11-01",
                ["through"] = "2026-11-30",
            });
            Assert.IsFalse(checkIns.IsError ?? false);
            using (JsonDocument document = JsonDocument.Parse(Text(checkIns)))
            {
                JsonElement single = document.RootElement.GetProperty("checkIns").EnumerateArray().Single();
                Assert.AreEqual("2026-11-19", single.GetProperty("date").GetString());
                Assert.AreEqual(81.5m, single.GetProperty("weightKg").GetDecimal());
                Assert.AreEqual(52, single.GetProperty("restingHrvMs").GetInt32());
            }

            foreach (string tool in new[]
            {
                "get_body_goals", "get_nutrition_days", "get_nutrition_targets", "list_saved_meals",
                "list_coach_notes", "get_strava_status",
            })
            {
                CallToolResult result = await CallAsync(mcp, tool, []);
                Assert.IsFalse(result.IsError ?? false, tool);
            }

            CallToolResult tooLong = await CallAsync(mcp, "get_nutrition_days", new()
            {
                ["from"] = "2026-01-01",
                ["through"] = "2026-03-01",
            });
            Assert.IsTrue(tooLong.IsError);

            // Out-of-range arguments are reported as tool errors.
            foreach ((string tool, Dictionary<string, object?> arguments) in new (string, Dictionary<string, object?>)[]
            {
                ("get_overview", new() { ["days"] = 5 }),
                ("get_overview", new() { ["endDaysAgo"] = -1 }),
                ("list_workouts", new() { ["limit"] = 0 }),
                ("search_exercises", new() { ["limit"] = 51 }),
                ("get_exercise_progress", new() { ["exerciseId"] = exerciseId, ["days"] = 5 }),
            })
            {
                CallToolResult invalid = await CallAsync(mcp, tool, arguments);
                Assert.IsTrue(invalid.IsError, tool);
            }
        }

        // The connector token counts as missing outside MCP; the app token does not open MCP.
        using (HttpClient connector = CreateClient(app))
        {
            connector.UseAccessToken(tokens.AccessToken);
            using HttpResponseMessage session = await connector.GetAsync("/api/v1/auth/session", TestContext.CancellationToken);
            using HttpResponseMessage connectors = await connector.GetAsync("/api/v1/auth/connectors", TestContext.CancellationToken);
            using HttpResponseMessage logoutAll = await connector.PostAsync("/api/v1/auth/logout-all", content: null, TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.Unauthorized, session.StatusCode);
            Assert.AreEqual(HttpStatusCode.Unauthorized, connectors.StatusCode);
            Assert.AreEqual(HttpStatusCode.Unauthorized, logoutAll.StatusCode);
        }

        using (HttpResponseMessage appOnMcp = await appClient.PostAsJsonAsync("/api/v1/mcp", new { }, TestContext.CancellationToken))
        {
            Assert.AreEqual(HttpStatusCode.Forbidden, appOnMcp.StatusCode);
            Assert.Contains("insufficient_scope", appOnMcp.Headers.WwwAuthenticate.ToString());
        }

        // Refresh rotates through the OAuth endpoint.
        using HttpClient anonymous = CreateClient(app);
        using HttpResponseMessage refreshed = await anonymous.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "refresh_token"), ("client_id", clientId), ("refresh_token", tokens.RefreshToken)), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, refreshed.StatusCode, await refreshed.Content.ReadAsStringAsync(TestContext.CancellationToken));
        OAuthTokens renewed = (await refreshed.Content.ReadFromJsonAsync<OAuthTokens>(TestContext.CancellationToken))!;

        // The owner sees and revokes the connection in the app.
        List<ConnectorSessionResponse>? listedConnectors = await appClient.GetFromJsonAsync<List<ConnectorSessionResponse>>(
            "/api/v1/auth/connectors", TestContext.CancellationToken);
        Assert.HasCount(1, listedConnectors!);
        Assert.AreEqual("ChatGPT", listedConnectors![0].Name);
        using (HttpClient otherClient = CreateClient(app))
        {
            await otherClient.AuthenticateAsync("other@example.test", Password);
            using HttpResponseMessage foreignRevoke = await otherClient.DeleteAsync(
                $"/api/v1/auth/connectors/{listedConnectors[0].Id}", TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.NotFound, foreignRevoke.StatusCode);
        }

        using HttpResponseMessage revoked = await appClient.DeleteAsync(
            $"/api/v1/auth/connectors/{listedConnectors[0].Id}", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NoContent, revoked.StatusCode);

        using HttpClient afterRevoke = CreateClient(app);
        afterRevoke.UseAccessToken(renewed.AccessToken);
        using HttpResponseMessage rejected = await afterRevoke.PostAsJsonAsync("/api/v1/mcp", new { }, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, rejected.StatusCode);
    }

    [TestMethod]
    public async Task CodesAreSingleUseAndBoundToTheVerifier()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, "owner@example.test");
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient appClient = CreateClient(app);
        TokenResponse appTokens = await appClient.AuthenticateAsync("owner@example.test", Password);
        await RegisterPasskeyAsync(appClient, authenticator);
        using HttpClient anonymous = CreateClient(app);
        string clientId = await RegisterAsync(anonymous, TestContext.CancellationToken);
        string verifier = NewVerifier();

        string code = await ApproveAsync(anonymous, authenticator, clientId, Challenge(verifier));
        using HttpResponseMessage wrongVerifier = await anonymous.PostAsync("/api/v1/oauth/token", CodeForm(clientId, code, NewVerifier()), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.BadRequest, wrongVerifier.StatusCode);
        Assert.AreEqual("invalid_grant", await ErrorAsync(wrongVerifier));

        string second = await ApproveAsync(anonymous, authenticator, clientId, Challenge(verifier));
        using HttpResponseMessage first = await anonymous.PostAsync("/api/v1/oauth/token", CodeForm(clientId, second, verifier), TestContext.CancellationToken);
        using HttpResponseMessage replay = await anonymous.PostAsync("/api/v1/oauth/token", CodeForm(clientId, second, verifier), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, first.StatusCode);
        Assert.AreEqual(HttpStatusCode.BadRequest, replay.StatusCode);
        Assert.AreEqual("invalid_grant", await ErrorAsync(replay));

        // An app refresh token is no connector grant, and rejecting it leaves the app session intact.
        using HttpResponseMessage appRefresh = await anonymous.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "refresh_token"), ("client_id", clientId), ("refresh_token", appTokens.RefreshToken)), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.BadRequest, appRefresh.StatusCode);
        using HttpResponseMessage appStillRefreshes = await BearerTestClient.RefreshAsync(anonymous, appTokens.RefreshToken);
        Assert.AreEqual(HttpStatusCode.OK, appStillRefreshes.StatusCode);

        // A connector refresh token works only for its own client and not at the app endpoint.
        OAuthTokens connector = (await first.Content.ReadFromJsonAsync<OAuthTokens>(TestContext.CancellationToken))!;
        string otherClient = await RegisterAsync(anonymous, TestContext.CancellationToken);
        using HttpResponseMessage foreignClient = await anonymous.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "refresh_token"), ("client_id", otherClient), ("refresh_token", connector.RefreshToken)), TestContext.CancellationToken);
        using HttpResponseMessage atAppEndpoint = await BearerTestClient.RefreshAsync(anonymous, connector.RefreshToken);
        using HttpResponseMessage ownClient = await anonymous.PostAsync("/api/v1/oauth/token", Form(
            ("grant_type", "refresh_token"), ("client_id", clientId), ("refresh_token", connector.RefreshToken)), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.BadRequest, foreignClient.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, atAppEndpoint.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, ownClient.StatusCode);
    }

    [TestMethod]
    public async Task ReconnectingReplacesTheConnectionAndLogoutEverywhereEndsIt()
    {
        await using WebApplication app = await CreateApplicationAsync();
        await CreateUserAsync(app, "owner@example.test");
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient appClient = CreateClient(app);
        await appClient.AuthenticateAsync("owner@example.test", Password);
        await RegisterPasskeyAsync(appClient, authenticator);
        using HttpClient anonymous = CreateClient(app);
        string clientId = await RegisterAsync(anonymous, TestContext.CancellationToken);

        OAuthTokens first = await ExchangeAsync(anonymous, authenticator, clientId);
        OAuthTokens second = await ExchangeAsync(anonymous, authenticator, clientId);

        List<ConnectorSessionResponse>? listed = await appClient.GetFromJsonAsync<List<ConnectorSessionResponse>>(
            "/api/v1/auth/connectors", TestContext.CancellationToken);
        Assert.HasCount(1, listed!);
        Assert.AreEqual(HttpStatusCode.Unauthorized, await McpStatusAsync(app, first.AccessToken));
        Assert.AreNotEqual(HttpStatusCode.Unauthorized, await McpStatusAsync(app, second.AccessToken));

        using HttpResponseMessage logoutAll = await appClient.PostAsync("/api/v1/auth/logout-all", content: null, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.NoContent, logoutAll.StatusCode);
        Assert.AreEqual(HttpStatusCode.Unauthorized, await McpStatusAsync(app, second.AccessToken));
    }

    private async Task<OAuthTokens> ExchangeAsync(HttpClient client, SoftwarePasskeyAuthenticator authenticator, string clientId)
    {
        string verifier = NewVerifier();
        string code = await ApproveAsync(client, authenticator, clientId, Challenge(verifier));
        using HttpResponseMessage response = await client.PostAsync("/api/v1/oauth/token", CodeForm(clientId, code, verifier), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        return (await response.Content.ReadFromJsonAsync<OAuthTokens>(TestContext.CancellationToken))!;
    }

    private async Task<HttpStatusCode> McpStatusAsync(WebApplication app, string accessToken)
    {
        using HttpClient client = CreateClient(app);
        client.UseAccessToken(accessToken);
        using HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/mcp", new { }, TestContext.CancellationToken);
        return response.StatusCode;
    }

    private async Task<(string ClientId, OAuthTokens Tokens)> ConnectAsync(WebApplication app, SoftwarePasskeyAuthenticator authenticator)
    {
        using HttpClient anonymous = CreateClient(app);
        string clientId = await RegisterAsync(anonymous, TestContext.CancellationToken);
        string verifier = NewVerifier();
        string code = await ApproveAsync(anonymous, authenticator, clientId, Challenge(verifier));
        using HttpResponseMessage response = await anonymous.PostAsync("/api/v1/oauth/token", CodeForm(clientId, code, verifier), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        OAuthTokens tokens = (await response.Content.ReadFromJsonAsync<OAuthTokens>(TestContext.CancellationToken))!;
        Assert.AreEqual("Bearer", tokens.TokenType);
        return (clientId, tokens);
    }

    private async Task<string> ApproveAsync(HttpClient client, SoftwarePasskeyAuthenticator authenticator, string clientId, string challenge)
    {
        using HttpResponseMessage page = await client.GetAsync(AuthorizeUrl(clientId, RedirectUri, challenge), TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, page.StatusCode);
        string request = ProtectedRequest(await page.Content.ReadAsStringAsync(TestContext.CancellationToken));

        using HttpResponseMessage optionsResponse = await client.PostAsync("/api/v1/auth/passkeys/request-options", content: null, TestContext.CancellationToken);
        PasskeyOptionsResponse options = (await optionsResponse.Content.ReadFromJsonAsync<PasskeyOptionsResponse>(TestContext.CancellationToken))!;
        using HttpResponseMessage approved = await client.PostAsJsonAsync(
            "/api/v1/oauth/authorize/approve",
            new { request, state = options.State, credentialJson = authenticator.SignIn(options.OptionsJson) },
            TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, approved.StatusCode, await approved.Content.ReadAsStringAsync(TestContext.CancellationToken));
        using JsonDocument body = JsonDocument.Parse(await approved.Content.ReadAsStringAsync(TestContext.CancellationToken));
        var redirect = new Uri(body.RootElement.GetProperty("redirectUri").GetString()!);
        Assert.StartsWith(RedirectUri, redirect.ToString());
        Dictionary<string, string?> query = Query(redirect);
        Assert.AreEqual("xyz", query["state"]);
        return query["code"]!;
    }

    private static FormUrlEncodedContent CodeForm(string clientId, string code, string verifier) => Form(
        ("grant_type", "authorization_code"),
        ("client_id", clientId),
        ("code", code),
        ("redirect_uri", RedirectUri),
        ("code_verifier", verifier));

    private async Task<McpClient> ConnectMcpAsync(WebApplication app, string accessToken)
    {
        HttpClient http = CreateClient(app);
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        var transport = new HttpClientTransport(
            new HttpClientTransportOptions { Endpoint = new Uri(BaseAddress + "/api/v1/mcp") },
            http,
            null,
            true);
        return await McpClient.CreateAsync(transport, null, null, TestContext.CancellationToken);
    }

    private async Task<CallToolResult> CallAsync(McpClient mcp, string tool, Dictionary<string, object?> arguments) =>
        await mcp.CallToolAsync(tool, arguments, cancellationToken: TestContext.CancellationToken);

    private static string Text(CallToolResult result) =>
        string.Join("\n", result.Content.OfType<TextContentBlock>().Select(block => block.Text));

    private async Task RegisterPasskeyAsync(HttpClient client, SoftwarePasskeyAuthenticator authenticator)
    {
        using HttpResponseMessage optionsResponse = await client.PostAsync("/api/v1/auth/passkeys/creation-options", content: null, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, optionsResponse.StatusCode, await optionsResponse.Content.ReadAsStringAsync(TestContext.CancellationToken));
        PasskeyOptionsResponse options = (await optionsResponse.Content.ReadFromJsonAsync<PasskeyOptionsResponse>(TestContext.CancellationToken))!;
        using HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/auth/passkeys",
            new RegisterPasskeyRequest(authenticator.Register(options.OptionsJson), options.State, "iPhone"),
            TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Created, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
    }

    private async Task<Guid> SeedWorkoutAsync(Guid userId, string title)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = new WorkoutMutationHandler(context, new CurrentUser(userId), TimeProvider.System, null);
        Guid workoutId = Guid.NewGuid();
        await handler.CreateAsync(
            CreateWorkoutMutation.Create(
                MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1),
                new WorkoutValues(workoutId, title, null, Started, Started.AddHours(1), "exercise", null, null, [])),
            TestContext.CancellationToken);
        return workoutId;
    }

    private async Task SeedCheckInAsync(Guid userId, DateOnly date, decimal weightKg)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        context.DailyCheckIns.Add(new Gainer.Core.BodyTracking.DailyCheckIn
        {
            Id = Guid.NewGuid(),
            LocalDate = date,
            WeightKg = weightKg,
            Steps = 9000,
            RestingHrvMs = 52,
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync(TestContext.CancellationToken);
    }

    private async Task<WebApplication> CreateApplicationAsync()
    {
        connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync(TestContext.CancellationToken);
        }

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-connector-flow-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.Configuration[GainerIdentityOptions.PasskeyServerDomainConfigurationKey] = "gainer.markfort.xyz";
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        var app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync(TestContext.CancellationToken);
        return app;
    }

    private static async Task<Guid> CreateUserAsync(WebApplication app, string email)
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        UserManager<AppUser> userManager = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
        var user = new AppUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            EmailConfirmed = true,
            IsActive = true,
        };
        IdentityResult result = await userManager.CreateAsync(user, Password);
        Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
        return user.Id;
    }

    private static HttpClient CreateClient(WebApplication app)
    {
        HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(BaseAddress);
        return client;
    }

    private sealed record CurrentUser(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }

    private sealed record OAuthTokens(
        [property: System.Text.Json.Serialization.JsonPropertyName("access_token")] string AccessToken,
        [property: System.Text.Json.Serialization.JsonPropertyName("token_type")] string TokenType,
        [property: System.Text.Json.Serialization.JsonPropertyName("expires_in")] int ExpiresIn,
        [property: System.Text.Json.Serialization.JsonPropertyName("refresh_token")] string RefreshToken);

    public TestContext TestContext { get; set; } = null!;
}
