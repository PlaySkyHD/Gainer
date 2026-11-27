using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Security;
using Gainer.Core.BodyTracking;
using Gainer.Core.Coach;
using Gainer.Core.Nutrition;
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
    // Relative to today, so period-based tools (overview, 7-day figures) keep finding the seeded data.
    private static readonly DateTime Started = DateTime.UtcNow.Date.AddDays(-1).AddHours(7);
    private static readonly DateOnly Today = DateOnly.FromDateTime(
        TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Gainer.Core.Insights.LocalDays.Default));
    private static readonly string[] ExpectedPlanNames = ["Plan Eigen", "Altplan Eigen"];
    private static readonly int[] ExpectedHeartRate = [0, 120, 130, 140];
    private static readonly int[] ExpectedRrIntervals = [500, 510];
    private static readonly int[] ExpectedWater = [2000, 1500];
    private static readonly string[] ExpectedTools =
    [
        "get_overview", "list_workouts", "get_workout", "search_exercises", "get_exercise_progress",
        "get_body_goals", "list_check_ins", "get_nutrition_days", "get_nutrition_targets", "list_saved_meals",
        "list_coach_notes", "get_strava_status", "list_training_plans", "get_training_plan", "get_workout_summary",
        "list_cardio_sessions", "get_cardio_session", "get_water", "list_day_templates",
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
        await SeedCheckInAsync(owner, Today.AddDays(-2), 81.5m);
        await SeedCheckInAsync(other, Today.AddDays(-1), 99m);
        await SeedOwnDataAsync(owner, "Haferflocken", "Kein Training nach 21 Uhr", BodyGoalKind.Cut);
        await SeedOwnDataAsync(other, "Fremdes Müsli", "Fremde Notiz", BodyGoalKind.Bulk);
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
            using (JsonDocument checkIns = await JsonAsync(mcp, "list_check_ins", new()))
            {
                JsonElement single = checkIns.RootElement.GetProperty("checkIns").EnumerateArray().Single();
                Assert.AreEqual(Today.AddDays(-2).ToString("yyyy-MM-dd"), single.GetProperty("date").GetString());
                Assert.AreEqual(81.5m, single.GetProperty("weightKg").GetDecimal());
                Assert.AreEqual(52, single.GetProperty("restingHrvMs").GetInt32());
            }

            using (JsonDocument summary = await JsonAsync(mcp, "get_overview", new() { ["days"] = 30 }))
            {
                JsonElement weight = summary.RootElement.GetProperty("weight");
                Assert.AreEqual(81.5m, weight.GetProperty("series").EnumerateArray().Single().GetProperty("weightKg").GetDecimal());
                Assert.AreEqual(81.5m, weight.GetProperty("sevenDayAverageKg").GetDecimal());
                Assert.AreEqual(1, summary.RootElement.GetProperty("training").GetProperty("workoutsLast7Days").GetInt32());
            }

            using (JsonDocument goals = await JsonAsync(mcp, "get_body_goals", []))
            {
                Assert.AreEqual("Cut", goals.RootElement.GetProperty("active").GetProperty("kind").GetString());
                Assert.AreEqual(0, goals.RootElement.GetProperty("history").GetArrayLength());
            }

            using (JsonDocument days = await JsonAsync(mcp, "get_nutrition_days", new()
            {
                ["from"] = Today.AddDays(-1).ToString("yyyy-MM-dd"),
                ["through"] = Today.ToString("yyyy-MM-dd"),
            }))
            {
                JsonElement[] list = days.RootElement.GetProperty("days").EnumerateArray().ToArray();
                Assert.HasCount(2, list);
                Assert.AreEqual("Haferflocken", list[0].GetProperty("entries")[0].GetProperty("product").GetString());
                Assert.AreEqual("Breakfast", list[0].GetProperty("entries")[0].GetProperty("meal").GetString());
                Assert.AreEqual(0, list[1].GetProperty("entries").GetArrayLength());
                Assert.AreEqual(0m, list[1].GetProperty("totals").GetProperty("kilocalories").GetDecimal());
            }

            using (JsonDocument notes = await JsonAsync(mcp, "list_coach_notes", []))
            {
                JsonElement note = notes.RootElement.GetProperty("notes").EnumerateArray().Single();
                Assert.AreEqual("Kein Training nach 21 Uhr", note.GetProperty("text").GetString());
            }

            foreach (string tool in new[] { "get_nutrition_targets", "list_saved_meals", "get_strava_status" })
            {
                CallToolResult result = await CallAsync(mcp, tool, []);
                Assert.IsFalse(result.IsError ?? false, tool);
            }

            CallToolResult reversed = await CallAsync(mcp, "list_check_ins", new()
            {
                ["from"] = Today.ToString("yyyy-MM-dd"),
                ["through"] = Today.AddDays(-1).ToString("yyyy-MM-dd"),
            });
            Assert.IsTrue(reversed.IsError);

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
    public async Task AssistantReadsPlansCardioWaterTemplatesAndWorkoutSummariesOfItsOwnerOnly()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Guid owner = await CreateUserAsync(app, "owner@example.test");
        Guid other = await CreateUserAsync(app, "other@example.test");
        (Guid baseExercise, string baseName) = await BaseStrengthExerciseAsync(owner);
        StageTwoSeed own = await SeedStageTwoAsync(owner, "Eigen", baseExercise, 1500);
        StageTwoSeed foreign = await SeedStageTwoAsync(other, "Fremd", baseExercise, 999);
        DateTime yesterday = Gainer.Core.Insights.LocalDays.StartOfDayUtc(Today.AddDays(-1), Gainer.Core.Insights.LocalDays.Default);
        Guid morning = await SeedStrengthWorkoutAsync(owner, "Früh", yesterday.AddHours(8), null,
            (baseExercise, baseName, [("warmup", 60m, 5), ("normal", 100m, 5)]));
        Guid evening = await SeedStrengthWorkoutAsync(owner, "Abend", yesterday.AddHours(18), own.PlanId,
            (baseExercise, baseName, [("normal", 105m, 5), ("normal", 100m, 3)]),
            (own.CustomExerciseId, "Eigene Übung Eigen", [("normal", 20m, 10)]));
        Guid foreignWorkout = await SeedStrengthWorkoutAsync(other, "Fremd", yesterday.AddHours(9), foreign.PlanId,
            (baseExercise, baseName, [("normal", 200m, 5)]));
        using var authenticator = new SoftwarePasskeyAuthenticator();
        using HttpClient appClient = CreateClient(app);
        await appClient.AuthenticateAsync("owner@example.test", Password);
        await RegisterPasskeyAsync(appClient, authenticator);
        (_, OAuthTokens tokens) = await ConnectAsync(app, authenticator);

        await using McpClient mcp = await ConnectMcpAsync(app, tokens.AccessToken);
        await AssertPlansAsync(mcp, own, foreign, baseExercise, baseName);
        await AssertWorkoutsAsync(mcp, morning, evening, foreignWorkout, own.PlanId, baseExercise, own.CustomExerciseId);
        await AssertCardioAsync(mcp, own, foreign);
        await AssertWaterAndTemplatesAsync(mcp);
        await AssertExerciseFiltersAsync(mcp, own, foreign);
    }

    private async Task AssertPlansAsync(McpClient mcp, StageTwoSeed own, StageTwoSeed foreign, Guid baseExercise, string baseName)
    {
        using (JsonDocument active = await JsonAsync(mcp, "list_training_plans", []))
        {
            JsonElement plan = active.RootElement.GetProperty("plans").EnumerateArray().Single();
            Assert.AreEqual(own.PlanId, plan.GetProperty("planId").GetGuid());
            Assert.AreEqual("Plan Eigen", plan.GetProperty("name").GetString());
            Assert.AreEqual("Notiz Eigen", plan.GetProperty("notes").GetString());
            Assert.IsFalse(plan.GetProperty("archived").GetBoolean());
            JsonElement[] entries = plan.GetProperty("entries").EnumerateArray().ToArray();
            Assert.HasCount(2, entries);
            Assert.AreEqual(own.CustomExerciseId, entries[0].GetProperty("exerciseId").GetGuid());
            Assert.AreEqual("Eigene Übung Eigen", entries[0].GetProperty("exerciseName").GetString());
            Assert.AreEqual(1, entries[0].GetProperty("warmupSets").GetInt32());
            Assert.AreEqual(3, entries[0].GetProperty("workingSets").GetInt32());
            Assert.AreEqual(baseName, entries[1].GetProperty("exerciseName").GetString());
            Assert.AreEqual(baseExercise, entries[1].GetProperty("exerciseId").GetGuid());
            Assert.AreEqual("Langsam", entries[1].GetProperty("notes").GetString());
            Assert.AreEqual(
                entries[0].GetProperty("supersetId").GetGuid(),
                entries[1].GetProperty("supersetId").GetGuid());
        }

        using (JsonDocument all = await JsonAsync(mcp, "list_training_plans", new() { ["includeArchived"] = true }))
        {
            string[] names = all.RootElement.GetProperty("plans").EnumerateArray()
                .Select(plan => plan.GetProperty("name").GetString()!).ToArray();
            Assert.AreSequenceEqual(ExpectedPlanNames, names);
        }

        using (JsonDocument archived = await JsonAsync(mcp, "get_training_plan", new() { ["planId"] = own.ArchivedPlanId }))
        {
            Assert.IsTrue(archived.RootElement.GetProperty("archived").GetBoolean());
        }

        CallToolResult foreignPlan = await CallAsync(mcp, "get_training_plan", new() { ["planId"] = foreign.PlanId });
        Assert.IsTrue(foreignPlan.IsError);
        Assert.DoesNotContain("Fremd", Text(foreignPlan));
        CallToolResult unknownPlan = await CallAsync(mcp, "get_training_plan", new() { ["planId"] = Guid.NewGuid() });
        Assert.IsTrue(unknownPlan.IsError);
    }

    private async Task AssertWorkoutsAsync(
        McpClient mcp, Guid morning, Guid evening, Guid foreignWorkout, Guid planId, Guid baseExercise, Guid customExercise)
    {
        using (JsonDocument listed = await JsonAsync(mcp, "list_workouts", new()
        {
            ["from"] = Today.AddDays(-1).ToString("yyyy-MM-dd"),
            ["through"] = Today.ToString("yyyy-MM-dd"),
        }))
        {
            JsonElement[] workouts = listed.RootElement.GetProperty("workouts").EnumerateArray().ToArray();
            Assert.AreSequenceEqual(new[] { evening, morning }, workouts.Select(item => item.GetProperty("workoutId").GetGuid()).ToArray());
            Assert.AreEqual(planId, workouts[0].GetProperty("sourcePlanId").GetGuid());
            // Absent values are left out of tool results, not written as null.
            Assert.IsFalse(workouts[1].TryGetProperty("sourcePlanId", out _));
            Assert.AreEqual(3, workouts[0].GetProperty("completedSets").GetInt32());
        }

        using (JsonDocument earlier = await JsonAsync(mcp, "list_workouts", new()
        {
            ["from"] = Today.AddDays(-10).ToString("yyyy-MM-dd"),
            ["through"] = Today.AddDays(-5).ToString("yyyy-MM-dd"),
        }))
        {
            Assert.AreEqual(0, earlier.RootElement.GetProperty("workouts").GetArrayLength());
        }

        using (JsonDocument summary = await JsonAsync(mcp, "get_workout_summary", new() { ["workoutId"] = evening }))
        {
            JsonElement root = summary.RootElement;
            Assert.AreEqual(60, root.GetProperty("durationMinutes").GetInt32());
            Assert.AreEqual(3, root.GetProperty("countedSets").GetInt32());
            Assert.AreEqual(18, root.GetProperty("totalRepetitions").GetInt32());
            Assert.AreEqual(1025m, root.GetProperty("volumeKgRepetitions").GetDecimal());
            Assert.AreEqual(2, root.GetProperty("workoutNumberOverall").GetInt32());
            Assert.AreEqual(2, root.GetProperty("workoutNumberThisWeek").GetInt32());
            JsonElement best = root.GetProperty("bestSets").EnumerateArray()
                .Single(item => item.GetProperty("exerciseId").GetGuid() == baseExercise);
            Assert.AreEqual(105m, best.GetProperty("weightKg").GetDecimal());
            Assert.AreEqual(5, best.GetProperty("repetitions").GetInt32());
            Assert.AreEqual(122.5m, best.GetProperty("estimatedOneRepMaxKg").GetDecimal());
            (Guid ExerciseId, string Kind, decimal Value)[] records = root.GetProperty("newRecords").EnumerateArray()
                .Select(item => (item.GetProperty("exerciseId").GetGuid(), item.GetProperty("kind").GetString()!,
                    item.GetProperty("value").GetDecimal()))
                .ToArray();
            Assert.Contains((baseExercise, "MaxWeight", 105m), records);
            Assert.Contains((baseExercise, "Volume", 825m), records);
            Assert.DoesNotContain((baseExercise, "MaxRepetitions", 5m), records);
            Assert.HasCount(4, records.Where(item => item.ExerciseId == customExercise).ToArray());
        }

        using (JsonDocument first = await JsonAsync(mcp, "get_workout_summary", new() { ["workoutId"] = morning }))
        {
            // Like the app's summary screen: all completed workouts count, also the later one.
            Assert.AreEqual(2, first.RootElement.GetProperty("workoutNumberOverall").GetInt32());
            Assert.AreEqual(2, first.RootElement.GetProperty("workoutNumberThisWeek").GetInt32());
            Assert.AreEqual(1, first.RootElement.GetProperty("countedSets").GetInt32());
        }

        CallToolResult foreignSummary = await CallAsync(mcp, "get_workout_summary", new() { ["workoutId"] = foreignWorkout });
        Assert.IsTrue(foreignSummary.IsError);
        CallToolResult tooLong = await CallAsync(mcp, "list_workouts", new()
        {
            ["from"] = Today.AddDays(-400).ToString("yyyy-MM-dd"),
            ["through"] = Today.ToString("yyyy-MM-dd"),
        });
        Assert.IsTrue(tooLong.IsError);
    }

    private async Task AssertCardioAsync(McpClient mcp, StageTwoSeed own, StageTwoSeed foreign)
    {
        using (JsonDocument recent = await JsonAsync(mcp, "list_cardio_sessions", []))
        {
            JsonElement session = recent.RootElement.GetProperty("sessions").EnumerateArray().Single();
            Assert.AreEqual(own.CardioSessionId, session.GetProperty("sessionId").GetGuid());
            Assert.AreEqual("IndoorCycling", session.GetProperty("activityType").GetString());
            Assert.AreEqual("Intervalle Eigen", session.GetProperty("templateName").GetString());
            Assert.AreEqual(30, session.GetProperty("durationMinutes").GetInt32());
            Assert.AreEqual(130, session.GetProperty("averageHeartRateBpm").GetInt32());
            Assert.AreEqual(140, session.GetProperty("maxHeartRateBpm").GetInt32());
            Assert.AreEqual(12.5m, session.GetProperty("distanceKm").GetDecimal());
            Assert.AreEqual(180m, session.GetProperty("averagePowerWatts").GetDecimal());
            Assert.AreEqual(300m, session.GetProperty("energyKcal").GetDecimal());
            Assert.AreEqual("Locker", session.GetProperty("notes").GetString());
        }

        using (JsonDocument longer = await JsonAsync(mcp, "list_cardio_sessions", new()
        {
            ["from"] = Today.AddDays(-45).ToString("yyyy-MM-dd"),
        }))
        {
            Guid[] ids = longer.RootElement.GetProperty("sessions").EnumerateArray()
                .Select(item => item.GetProperty("sessionId").GetGuid()).ToArray();
            Assert.AreSequenceEqual(new[] { own.CardioSessionId, own.OldCardioSessionId }, ids);
        }

        using (JsonDocument detail = await JsonAsync(mcp, "get_cardio_session", new() { ["sessionId"] = own.CardioSessionId }))
        {
            JsonElement root = detail.RootElement;
            Assert.AreSequenceEqual(ExpectedHeartRate, root.GetProperty("heartRateBpm").EnumerateArray().Select(item => item.GetInt32()).ToArray());
            Assert.AreSequenceEqual(ExpectedRrIntervals, root.GetProperty("rrIntervalsMs").EnumerateArray().Select(item => item.GetInt32()).ToArray());
            Assert.AreEqual(5, root.GetProperty("sampleIntervalSeconds").GetInt32());
            Assert.AreEqual(110, root.GetProperty("targetZone").GetProperty("lowBpm").GetInt32());
            Assert.AreEqual("Warm-up", root.GetProperty("phases")[0].GetProperty("name").GetString());
            Assert.AreEqual(150, root.GetProperty("recoveryStartBpm").GetInt32());
            Assert.AreEqual(120, root.GetProperty("recoveryEndBpm").GetInt32());
        }

        CallToolResult foreignSession = await CallAsync(mcp, "get_cardio_session", new() { ["sessionId"] = foreign.CardioSessionId });
        Assert.IsTrue(foreignSession.IsError);
        Assert.DoesNotContain("Fremd", Text(foreignSession));
        CallToolResult tooLong = await CallAsync(mcp, "list_cardio_sessions", new()
        {
            ["from"] = Today.AddDays(-366).ToString("yyyy-MM-dd"),
        });
        Assert.IsTrue(tooLong.IsError);
    }

    private async Task AssertWaterAndTemplatesAsync(McpClient mcp)
    {
        using (JsonDocument water = await JsonAsync(mcp, "get_water", new()
        {
            ["from"] = Today.AddDays(-3).ToString("yyyy-MM-dd"),
            ["through"] = Today.ToString("yyyy-MM-dd"),
        }))
        {
            JsonElement[] days = water.RootElement.GetProperty("days").EnumerateArray().ToArray();
            Assert.AreSequenceEqual(
                new[] { Today.AddDays(-3).ToString("yyyy-MM-dd"), Today.ToString("yyyy-MM-dd") },
                days.Select(item => item.GetProperty("date").GetString()!).ToArray());
            Assert.AreSequenceEqual(ExpectedWater, days.Select(item => item.GetProperty("milliliters").GetInt32()).ToArray());
        }

        using (JsonDocument today = await JsonAsync(mcp, "get_water", []))
        {
            Assert.AreEqual(1500, today.RootElement.GetProperty("days").EnumerateArray().Single().GetProperty("milliliters").GetInt32());
        }

        CallToolResult tooLong = await CallAsync(mcp, "get_water", new() { ["from"] = Today.AddDays(-366).ToString("yyyy-MM-dd") });
        Assert.IsTrue(tooLong.IsError);

        using JsonDocument templates = await JsonAsync(mcp, "list_day_templates", []);
        JsonElement template = templates.RootElement.GetProperty("templates").EnumerateArray().Single();
        Assert.AreEqual("Trainingstag Eigen", template.GetProperty("name").GetString());
        Assert.AreEqual("Training", template.GetProperty("dayKind").GetString());
        JsonElement entry = template.GetProperty("entries").EnumerateArray().Single();
        Assert.AreEqual("Reis Eigen", entry.GetProperty("product").GetString());
        Assert.AreEqual("Lunch", entry.GetProperty("meal").GetString());
        Assert.AreEqual(150m, entry.GetProperty("grams").GetDecimal());
        Assert.AreEqual(195m, entry.GetProperty("nutrition").GetProperty("kilocalories").GetDecimal());
        Assert.AreEqual(195m, template.GetProperty("totals").GetProperty("kilocalories").GetDecimal());
    }

    private async Task AssertExerciseFiltersAsync(McpClient mcp, StageTwoSeed own, StageTwoSeed foreign)
    {
        using (JsonDocument incomplete = await JsonAsync(mcp, "search_exercises", new() { ["onlyWithoutMuscles"] = true }))
        {
            JsonElement exercise = incomplete.RootElement.GetProperty("exercises").EnumerateArray().Single();
            Assert.AreEqual(own.CustomExerciseId, exercise.GetProperty("exerciseId").GetGuid());
            Assert.AreEqual(own.CategoryId, exercise.GetProperty("categoryIds")[0].GetGuid());
            Guid[] categories = incomplete.RootElement.GetProperty("categories").EnumerateArray()
                .Select(item => item.GetProperty("categoryId").GetGuid()).ToArray();
            Assert.Contains(own.CategoryId, categories);
            Assert.DoesNotContain(foreign.CategoryId, categories);
            Assert.Contains(true, incomplete.RootElement.GetProperty("categories").EnumerateArray()
                .Select(item => item.GetProperty("isBase").GetBoolean()));
        }

        using (JsonDocument inCategory = await JsonAsync(mcp, "search_exercises", new() { ["categoryId"] = own.CategoryId }))
        {
            Assert.AreEqual(own.CustomExerciseId,
                inCategory.RootElement.GetProperty("exercises").EnumerateArray().Single().GetProperty("exerciseId").GetGuid());
        }

        using (JsonDocument archived = await JsonAsync(mcp, "search_exercises", new() { ["query"] = "Alte Übung" }))
        {
            Assert.AreEqual(0, archived.RootElement.GetProperty("exercises").GetArrayLength());
        }

        using (JsonDocument archived = await JsonAsync(mcp, "search_exercises", new()
        {
            ["query"] = "Alte Übung",
            ["includeArchived"] = true,
        }))
        {
            Assert.AreEqual(own.ArchivedExerciseId,
                archived.RootElement.GetProperty("exercises").EnumerateArray().Single().GetProperty("exerciseId").GetGuid());
        }

        CallToolResult foreignCategory = await CallAsync(mcp, "search_exercises", new() { ["categoryId"] = foreign.CategoryId });
        Assert.IsTrue(foreignCategory.IsError);
    }

    private async Task<(Guid Id, string Name)> BaseStrengthExerciseAsync(Guid userId)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var exercise = await context.Exercises.AsNoTracking()
            .Where(item => item.OwnerUserId == null && item.ExerciseType == ExerciseType.Strength
                && item.BodyweightFactor == null && item.WeightFactor == null)
            .OrderBy(item => item.Name)
            .Select(item => new { item.Id, item.Name })
            .FirstAsync(TestContext.CancellationToken);
        return (exercise.Id, exercise.Name);
    }

    /// <summary>Category, exercises, two plans, two cardio sessions, water and a day template of one user.</summary>
    private async Task<StageTwoSeed> SeedStageTwoAsync(Guid userId, string label, Guid baseExercise, int waterTodayMl)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        DateTime now = DateTime.UtcNow;
        var seed = new StageTwoSeed(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(),
            Guid.NewGuid(), Guid.NewGuid());
        context.ExerciseCategories.Add(new ExerciseCategory
        {
            Id = seed.CategoryId,
            OwnerUserId = userId,
            Name = $"Fokus {label}",
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        });
        context.Exercises.AddRange(
            new Exercise
            {
                Id = seed.CustomExerciseId,
                OwnerUserId = userId,
                Name = $"Eigene Übung {label}",
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            },
            new Exercise
            {
                Id = seed.ArchivedExerciseId,
                OwnerUserId = userId,
                Name = $"Alte Übung {label}",
                PrimaryMuscles = ["chest"],
                IsArchived = true,
                CreatedAtUtc = now,
                UpdatedAtUtc = now,
                Version = 1,
            });
        context.ExerciseCategoryAssignments.Add(new ExerciseCategoryAssignment
        {
            ExerciseId = seed.CustomExerciseId,
            CategoryId = seed.CategoryId,
        });
        Guid superset = Guid.NewGuid();
        context.TrainingPlans.AddRange(
            Plan(seed.PlanId, $"Plan {label}", $"Notiz {label}", 0, archived: false, now),
            Plan(seed.ArchivedPlanId, $"Altplan {label}", null, 1, archived: true, now));
        context.TrainingPlanEntries.AddRange(
            PlanEntry(seed.PlanId, 0, seed.CustomExerciseId, 1, 3, null, superset),
            PlanEntry(seed.PlanId, 1, baseExercise, 0, 4, "Langsam", superset),
            PlanEntry(seed.ArchivedPlanId, 0, baseExercise, 0, 2, null, null));
        DateTime cardioStart = Gainer.Core.Insights.LocalDays.StartOfDayUtc(Today.AddDays(-1), Gainer.Core.Insights.LocalDays.Default).AddHours(17);
        context.CardioSessions.AddRange(
            Cardio(seed.CardioSessionId, cardioStart, $"Intervalle {label}", now),
            Cardio(seed.OldCardioSessionId, cardioStart.AddDays(-40), null, now));
        context.WaterIntakeDays.AddRange(
            Water(Today, waterTodayMl, now),
            Water(Today.AddDays(-3), 2000, now));
        var template = new NutritionDayTemplate
        {
            Id = Guid.NewGuid(),
            Name = $"Trainingstag {label}",
            DayKind = NutritionDayKind.Training,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        template.Entries.Add(new NutritionDayTemplateEntry
        {
            Id = Guid.NewGuid(),
            NutritionDayTemplateId = template.Id,
            Meal = MealType.Lunch,
            Position = 0,
            ProductName = $"Reis {label}",
            AmountGrams = 150m,
            Kilocalories = 195m,
            ProteinGrams = 4m,
            BasisGrams = 100m,
            KilocaloriesPerBasis = 130m,
            ProteinGramsPerBasis = 2.7m,
        });
        context.NutritionDayTemplates.Add(template);
        await context.SaveChangesAsync(TestContext.CancellationToken);
        return seed;
    }

    private static TrainingPlan Plan(Guid id, string name, string? notes, int sortOrder, bool archived, DateTime now) => new()
    {
        Id = id,
        Name = name,
        Notes = notes,
        SortOrder = sortOrder,
        IsArchived = archived,
        CreatedAtUtc = now,
        UpdatedAtUtc = now,
        Version = 1,
    };

    private static TrainingPlanEntry PlanEntry(
        Guid planId, int position, Guid exerciseId, int warmupSets, int workingSets, string? notes, Guid? supersetId) => new()
        {
            Id = Guid.NewGuid(),
            PlanId = planId,
            Position = position,
            ExerciseId = exerciseId,
            WarmupSets = warmupSets,
            WorkingSets = workingSets,
            Notes = notes,
            SupersetId = supersetId,
        };

    private static CardioSession Cardio(Guid id, DateTime startedAtUtc, string? templateName, DateTime now) => new()
    {
        Id = id,
        StartedAtUtc = startedAtUtc,
        EndedAtUtc = startedAtUtc.AddMinutes(30),
        TargetZoneLowBpm = 110,
        TargetZoneHighBpm = 140,
        SampleIntervalSeconds = 5,
        HeartRateBpm = [0, 120, 130, 140],
        RrIntervalsMs = [500, 510],
        SensorName = "Gurt",
        DistanceKm = 12.5m,
        AveragePowerWatts = 180m,
        EnergyKcal = 300m,
        Notes = "Locker",
        RecoveryStartBpm = 150,
        RecoveryEndBpm = 120,
        TemplateName = templateName,
        Phases = templateName is null ? null : [new CardioPhaseValues(0, 600, "Warm-up", 100, 120)],
        CreatedAtUtc = now,
        UpdatedAtUtc = now,
        Version = 1,
    };

    private static WaterIntakeDay Water(DateOnly date, int amountMl, DateTime now) => new()
    {
        Id = Guid.NewGuid(),
        LocalDate = date,
        AmountMl = amountMl,
        CreatedAtUtc = now,
        UpdatedAtUtc = now,
        Version = 1,
    };

    private async Task<Guid> SeedStrengthWorkoutAsync(
        Guid userId,
        string title,
        DateTime startedAtUtc,
        Guid? planId,
        params (Guid ExerciseId, string Name, (string Type, decimal Weight, int Repetitions)[] Sets)[] exercises)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        var handler = new WorkoutMutationHandler(context, new CurrentUser(userId), TimeProvider.System, null);
        Guid workoutId = Guid.NewGuid();
        WorkoutExerciseValues[] blocks = exercises
            .Select(exercise => new WorkoutExerciseValues(
                Guid.NewGuid(),
                exercise.ExerciseId,
                exercise.Name,
                "strength",
                null,
                null,
                exercise.Sets
                    .Select(set => new WorkoutSetValues(Guid.NewGuid(), set.Type, set.Weight, set.Repetitions, null, null))
                    .ToList()))
            .ToArray();
        await handler.CreateAsync(
            CreateWorkoutMutation.Create(
                MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1),
                new WorkoutValues(workoutId, title, null, startedAtUtc, startedAtUtc.AddHours(1), "exercise", planId, null, blocks)),
            TestContext.CancellationToken);
        return workoutId;
    }

    private sealed record StageTwoSeed(
        Guid CategoryId,
        Guid CustomExerciseId,
        Guid ArchivedExerciseId,
        Guid PlanId,
        Guid ArchivedPlanId,
        Guid CardioSessionId,
        Guid OldCardioSessionId);

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

    private async Task<JsonDocument> JsonAsync(McpClient mcp, string tool, Dictionary<string, object?> arguments)
    {
        CallToolResult result = await CallAsync(mcp, tool, arguments);
        Assert.IsFalse(result.IsError ?? false, $"{tool}: {Text(result)}");
        return JsonDocument.Parse(Text(result));
    }

    /// <summary>A nutrition day with one entry yesterday, a coach note and an active goal for the user.</summary>
    private async Task SeedOwnDataAsync(Guid userId, string product, string note, BodyGoalKind goal)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        DateTime now = DateTime.UtcNow;
        var day = new NutritionDay
        {
            Id = Guid.NewGuid(),
            LocalDate = Today.AddDays(-1),
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        day.Entries.Add(new NutritionEntry
        {
            Id = Guid.NewGuid(),
            NutritionDayId = day.Id,
            Meal = MealType.Breakfast,
            Position = 0,
            ProductName = product,
            AmountGrams = 80m,
            Kilocalories = 300m,
            ProteinGrams = 10m,
            BasisGrams = 100m,
            KilocaloriesPerBasis = 375m,
            ProteinGramsPerBasis = 12.5m,
        });
        context.NutritionDays.Add(day);
        context.CoachMemories.Add(new CoachMemory
        {
            Id = Guid.NewGuid(),
            Category = CoachMemoryCategory.Preference,
            Text = note,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        });
        context.BodyGoals.Add(new BodyGoal
        {
            Id = Guid.NewGuid(),
            Kind = goal,
            StartWeightKg = 85m,
            TargetWeightKg = 80m,
            StartDate = Today.AddDays(-30),
            CreatedAtUtc = now,
            Version = 1,
        });
        await context.SaveChangesAsync(TestContext.CancellationToken);
    }

    private async Task SeedCheckInAsync(Guid userId, DateOnly date, decimal weightKg)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        context.DailyCheckIns.Add(new DailyCheckIn
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
