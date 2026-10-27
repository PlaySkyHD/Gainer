using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Gainer.IntegrationTests;

/// <summary>End-to-end wire contract of the training schedule (design D3a) through the sync HTTP endpoints, with two users.</summary>
[TestClass]
[DoNotParallelize]
public sealed class TrainingScheduleApiTests
{
    private const string TestOrigin = "https://schedule.gainer.test";
    private const string OwnerEmail = "schedule-owner@example.test";
    private const string IntruderEmail = "schedule-intruder@example.test";
    private const string Password = "Schedule-test-password-42!";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static PostgreSqlTestFixture? fixture;
    private readonly List<string> keyRingPaths = [];
    private string connectionString = string.Empty;

    public TestContext TestContext { get; set; } = null!;

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
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestCleanup]
    public void DeleteKeyRings()
    {
        foreach (string path in keyRingPaths)
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        keyRingPaths.Clear();
    }

    [TestMethod]
    public async Task SaveReplaysIdempotentlyUpdatesWithVersionCheckAndAppearsInThePullFeed()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Device owner = await SignInDeviceAsync(app, OwnerEmail);
        Guid push = await CreatePlanAsync(owner, "Push");
        Guid pull = await CreatePlanAsync(owner, "Pull");
        Guid scheduleId = Guid.NewGuid();

        object cycle = new
        {
            scheduleId,
            baseVersion = 0,
            mode = "cycle",
            anchorDate = "2026-10-20",
            validFrom = "2026-10-21",
            slots = new object[] { new { planId = (Guid?)push }, new { planId = (Guid?)pull }, new { planId = (Guid?)null } },
            shifts = new[] { new { fromDate = "2026-10-23", days = 1 } },
            exceptions = new[] { new { date = "2026-10-22", planId = pull, movedToDate = (string?)"2026-10-23" } },
        };
        Guid createId = Guid.NewGuid();
        PushMutationResponse created = await PushOkAsync(owner, createId, "saveTrainingSchedule", scheduleId, 0, cycle);
        Assert.IsFalse(created.Replayed);
        SyncResourceResult resource = created.Resources.Single();
        Assert.AreEqual("TrainingSchedule", resource.ResourceType);
        Assert.AreEqual(scheduleId, resource.ResourceId);
        Assert.AreEqual(1, resource.Version);
        JsonElement snapshot = resource.Snapshot!.Value;
        Assert.AreEqual(scheduleId, snapshot.GetProperty("scheduleId").GetGuid());
        Assert.AreEqual("cycle", snapshot.GetProperty("mode").GetString());
        Assert.AreEqual("2026-10-20", snapshot.GetProperty("anchorDate").GetString());
        Assert.AreEqual("2026-10-21", snapshot.GetProperty("validFrom").GetString());
        Assert.AreEqual(3, snapshot.GetProperty("slots").GetArrayLength());
        Assert.AreEqual(pull, snapshot.GetProperty("slots")[1].GetProperty("planId").GetGuid());
        Assert.AreEqual(JsonValueKind.Null, snapshot.GetProperty("slots")[2].GetProperty("planId").ValueKind);
        Assert.AreEqual("2026-10-23", snapshot.GetProperty("shifts")[0].GetProperty("fromDate").GetString());
        Assert.AreEqual(1, snapshot.GetProperty("shifts")[0].GetProperty("days").GetInt32());
        Assert.AreEqual("2026-10-22", snapshot.GetProperty("exceptions")[0].GetProperty("date").GetString());
        Assert.AreEqual("2026-10-23", snapshot.GetProperty("exceptions")[0].GetProperty("movedToDate").GetString());
        Assert.AreEqual(1, snapshot.GetProperty("version").GetInt64());
        Assert.IsTrue(snapshot.TryGetProperty("updatedAtUtc", out _));
        Assert.IsFalse(snapshot.TryGetProperty("baseVersion", out _));

        // Same mutation id, same content: replayed, not applied twice.
        PushMutationResponse replay = await PushOkAsync(owner, createId, "saveTrainingSchedule", scheduleId, 0, cycle);
        Assert.IsTrue(replay.Replayed);
        Assert.AreEqual(created.Revision, replay.Revision);
        Assert.AreEqual(1, replay.Resources.Single().Version);
        await using (AppDbContext check = PostgreSqlTestFixture.CreateContext(connectionString, owner.UserId))
        {
            Assert.AreEqual(1, await check.TrainingSchedules.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(3, await check.TrainingScheduleSlots.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(1, await check.ProcessedMutations.CountAsync(item => item.MutationId == createId, TestContext.CancellationToken));
        }

        // Full replacement switches to weekly mode and drops shifts and exceptions.
        object weekly = new
        {
            scheduleId,
            baseVersion = 1,
            mode = "weekly",
            anchorDate = (string?)null,
            validFrom = "2026-10-22",
            slots = new object[]
            {
                new { planId = (Guid?)push }, new { planId = (Guid?)pull }, new { planId = (Guid?)null }, new { planId = (Guid?)push },
                new { planId = (Guid?)pull }, new { planId = (Guid?)null }, new { planId = (Guid?)null },
            },
            shifts = Array.Empty<object>(),
            exceptions = Array.Empty<object>(),
        };
        PushMutationResponse updated = await PushOkAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 1, weekly);
        JsonElement updatedSnapshot = updated.Resources.Single().Snapshot!.Value;
        Assert.AreEqual(2, updatedSnapshot.GetProperty("version").GetInt64());
        Assert.AreEqual("weekly", updatedSnapshot.GetProperty("mode").GetString());
        Assert.AreEqual(JsonValueKind.Null, updatedSnapshot.GetProperty("anchorDate").ValueKind);
        Assert.AreEqual(7, updatedSnapshot.GetProperty("slots").GetArrayLength());
        Assert.AreEqual(0, updatedSnapshot.GetProperty("exceptions").GetArrayLength());

        // Stale base version: the server keeps version 2 and reports a conflict.
        using (HttpResponseMessage stale = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 1, weekly))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, stale.StatusCode, await stale.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(stale));
        }

        // At most one schedule per user: creating another id is a conflict as well.
        Guid secondId = Guid.NewGuid();
        using (HttpResponseMessage second = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", secondId, 0,
                   WithIdentity(cycle, secondId, 0)))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, second.StatusCode, await second.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(second));
        }

        PullChangesResponse feed = await PullAsync(owner);
        List<SyncChangeResponse> scheduleChanges = feed.Batches.SelectMany(batch => batch.Changes)
            .Where(change => change.ResourceType == "TrainingSchedule").ToList();
        Assert.HasCount(2, scheduleChanges);
        Assert.AreEqual("weekly", scheduleChanges[^1].Snapshot!.Value.GetProperty("mode").GetString());
        Assert.AreEqual(2, scheduleChanges[^1].Version);
    }

    [TestMethod]
    public async Task ForeignPlansAreRejectedLikeUnknownPlansAndNothingIsStored()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Device owner = await SignInDeviceAsync(app, OwnerEmail);
        Device intruder = await SignInDeviceAsync(app, IntruderEmail);
        Guid ownerPlan = await CreatePlanAsync(owner, "Push");
        Guid intruderPlan = await CreatePlanAsync(intruder, "Eigene");
        Guid scheduleId = Guid.NewGuid();

        using HttpResponseMessage foreign = await PushAsync(intruder, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0,
            Cycle(scheduleId, 0, intruderPlan, ownerPlan));
        string foreignBody = await foreign.Content.ReadAsStringAsync(TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.UnprocessableEntity, foreign.StatusCode, foreignBody);
        using HttpResponseMessage unknown = await PushAsync(intruder, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0,
            Cycle(scheduleId, 0, intruderPlan, Guid.NewGuid()));
        string unknownBody = await unknown.Content.ReadAsStringAsync(TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.UnprocessableEntity, unknown.StatusCode, unknownBody);
        using JsonDocument foreignProblem = JsonDocument.Parse(foreignBody);
        using JsonDocument unknownProblem = JsonDocument.Parse(unknownBody);
        Assert.AreEqual("validation_failed", foreignProblem.RootElement.GetProperty("code").GetString());
        Assert.AreEqual(
            unknownProblem.RootElement.GetProperty("errors").GetProperty("Slots").GetString(),
            foreignProblem.RootElement.GetProperty("errors").GetProperty("Slots").GetString());

        await using AppDbContext intruderCheck = PostgreSqlTestFixture.CreateContext(connectionString, intruder.UserId);
        Assert.AreEqual(0, await intruderCheck.TrainingSchedules.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, await intruderCheck.TrainingScheduleSlots.CountAsync(TestContext.CancellationToken));
        Assert.AreEqual(0, (await PullAsync(intruder)).Batches.SelectMany(batch => batch.Changes)
            .Count(change => change.ResourceType == "TrainingSchedule"));

        // The owner can still save the plan in a schedule; the intruder can neither see nor delete it.
        await PushOkAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0, Cycle(scheduleId, 0, ownerPlan));
        using HttpResponseMessage foreignDelete = await PushAsync(intruder, Guid.NewGuid(), "deleteTrainingSchedule", scheduleId, 1,
            new { scheduleId, baseVersion = 1 });
        Assert.AreEqual(HttpStatusCode.Conflict, foreignDelete.StatusCode, await foreignDelete.Content.ReadAsStringAsync(TestContext.CancellationToken));
        Assert.AreEqual("resource_not_found", await ProblemCodeAsync(foreignDelete));
        Assert.AreEqual(0, (await PullAsync(intruder)).Batches.SelectMany(batch => batch.Changes)
            .Count(change => change.ResourceType == "TrainingSchedule"));
    }

    [TestMethod]
    public async Task DeleteEmitsATombstoneRemovesChildrenAndAllowsANewSchedule()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Device owner = await SignInDeviceAsync(app, OwnerEmail);
        Guid push = await CreatePlanAsync(owner, "Push");
        Guid scheduleId = Guid.NewGuid();
        await PushOkAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0, Cycle(scheduleId, 0, push));

        using (HttpResponseMessage stale = await PushAsync(owner, Guid.NewGuid(), "deleteTrainingSchedule", scheduleId, 2,
                   new { scheduleId, baseVersion = 2 }))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, stale.StatusCode, await stale.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(stale));
        }

        PushMutationResponse deleted = await PushOkAsync(owner, Guid.NewGuid(), "deleteTrainingSchedule", scheduleId, 1,
            new { scheduleId, baseVersion = 1 });
        SyncResourceResult tombstone = deleted.Resources.Single();
        Assert.IsTrue(tombstone.IsTombstone);
        Assert.AreEqual("TrainingSchedule", tombstone.ResourceType);
        Assert.AreEqual(2, tombstone.Version);
        Assert.IsNull(tombstone.Snapshot);
        await using (AppDbContext check = PostgreSqlTestFixture.CreateContext(connectionString, owner.UserId))
        {
            Assert.AreEqual(0, await check.TrainingSchedules.CountAsync(item => item.DeletedAtUtc == null, TestContext.CancellationToken));
            Assert.AreEqual(0, await check.TrainingScheduleSlots.CountAsync(TestContext.CancellationToken));
        }
        Assert.Contains(change => change.ResourceType == "TrainingSchedule" && change.IsTombstone, (await PullAsync(owner)).Batches.SelectMany(batch => batch.Changes));

        using (HttpResponseMessage missing = await PushAsync(owner, Guid.NewGuid(), "deleteTrainingSchedule", scheduleId, 1,
                   new { scheduleId, baseVersion = 1 }))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, missing.StatusCode);
            Assert.AreEqual("resource_not_found", await ProblemCodeAsync(missing));
        }

        // The same id is recreated from its tombstone version; the version keeps counting up.
        foreach (long staleBase in new long[] { 0, 1 })
        {
            using HttpResponseMessage stale = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, staleBase,
                Cycle(scheduleId, staleBase, push));
            Assert.AreEqual(HttpStatusCode.Conflict, stale.StatusCode, await stale.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(stale));
        }
        PushMutationResponse recreated = await PushOkAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 2,
            Cycle(scheduleId, 2, push, null));
        SyncResourceResult recreatedResource = recreated.Resources.Single();
        Assert.IsFalse(recreatedResource.IsTombstone);
        Assert.AreEqual(3, recreatedResource.Version);
        Assert.AreEqual(2, recreatedResource.Snapshot!.Value.GetProperty("slots").GetArrayLength());
        await using (AppDbContext check = PostgreSqlTestFixture.CreateContext(connectionString, owner.UserId))
        {
            Assert.AreEqual(2, await check.TrainingScheduleSlots.CountAsync(TestContext.CancellationToken));
        }
        PullChangesResponse feed = await PullAsync(owner);
        SyncChangeResponse latest = feed.Batches.SelectMany(batch => batch.Changes).Last(change => change.ResourceId == scheduleId);
        Assert.AreEqual(3, latest.Version);
        Assert.IsFalse(latest.IsTombstone);

        // While the recreated schedule is live, a different id is still the one-per-user conflict.
        Guid nextId = Guid.NewGuid();
        using (HttpResponseMessage second = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", nextId, 0, Cycle(nextId, 0, push)))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, second.StatusCode);
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(second));
        }

        // After deleting it again, a schedule with a new id can be created next to the tombstone.
        PushMutationResponse deletedAgain = await PushOkAsync(owner, Guid.NewGuid(), "deleteTrainingSchedule", scheduleId, 3,
            new { scheduleId, baseVersion = 3 });
        Assert.AreEqual(4, deletedAgain.Resources.Single().Version);
        PushMutationResponse fresh = await PushOkAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", nextId, 0, Cycle(nextId, 0, push));
        Assert.AreEqual(1, fresh.Resources.Single().Version);
        using (HttpResponseMessage resurrectBeside = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 4,
                   Cycle(scheduleId, 4, push)))
        {
            Assert.AreEqual(HttpStatusCode.Conflict, resurrectBeside.StatusCode);
            Assert.AreEqual("stale_base_version", await ProblemCodeAsync(resurrectBeside));
        }
    }

    [TestMethod]
    public async Task InvalidSchedulesReturnValidationProblems()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Device owner = await SignInDeviceAsync(app, OwnerEmail);
        Guid push = await CreatePlanAsync(owner, "Push");
        Guid scheduleId = Guid.NewGuid();

        (object Payload, string Field)[] cases =
        [
            (Cycle(scheduleId, 0, (Guid?)null), "Slots"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["slots"] = new System.Text.Json.Nodes.JsonArray()), "Slots"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["anchorDate"] = null), "AnchorDate"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["mode"] = "rotation"), "Mode"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["mode"] = "weekly"), "Slots"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["shifts"] = Nodes(new[] { new { fromDate = "2026-10-23", days = 32 } })), "Shifts"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["exceptions"] = Nodes(new[]
            {
                new { date = "2026-10-22", planId = push, movedToDate = (string?)null },
                new { date = "2026-10-22", planId = push, movedToDate = (string?)"2026-10-23" },
            })), "Exceptions"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["exceptions"] = Nodes(new[]
            {
                new { date = "2026-10-22", planId = push, movedToDate = (string?)"2026-10-22" },
            })), "Exceptions"),
            (Mutate(Cycle(scheduleId, 0, push), node => node["shifts"] = Nodes(new[]
            {
                new { fromDate = "2026-10-23", days = 1 },
                new { fromDate = "2026-10-23", days = 2 },
            })), "Shifts"),
        ];
        foreach ((object payload, string field) in cases)
        {
            using HttpResponseMessage response = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0, payload);
            string body = await response.Content.ReadAsStringAsync(TestContext.CancellationToken);
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode, body);
            using JsonDocument problem = JsonDocument.Parse(body);
            Assert.AreEqual("validation_failed", problem.RootElement.GetProperty("code").GetString(), body);
            Assert.IsTrue(problem.RootElement.GetProperty("errors").TryGetProperty(field, out _), $"{field}: {body}");
        }

        System.Text.Json.Nodes.JsonObject[] invalidPayloads =
        [
            Mutate(Cycle(scheduleId, 0, push), node => node["validFrom"] = "21.10.2026"),
            Mutate(Cycle(scheduleId, 0, push), node => node.Remove("validFrom")),
            Mutate(Cycle(scheduleId, 0, push), node => node["validFrom"] = null),
        ];
        foreach (System.Text.Json.Nodes.JsonObject payload in invalidPayloads)
        {
            using HttpResponseMessage response = await PushAsync(owner, Guid.NewGuid(), "saveTrainingSchedule", scheduleId, 0, payload);
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("invalid_payload", await ProblemCodeAsync(response));
        }

        await using AppDbContext check = PostgreSqlTestFixture.CreateContext(connectionString, owner.UserId);
        Assert.AreEqual(0, await check.TrainingSchedules.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task WorkoutRotationMutationsAreRejectedAsUnknownOperations()
    {
        await using WebApplication app = await CreateApplicationAsync();
        Device owner = await SignInDeviceAsync(app, OwnerEmail);
        Guid push = await CreatePlanAsync(owner, "Push");
        Guid rotationId = Guid.NewGuid();

        foreach (string resourceType in new[] { "WorkoutRotation", "TrainingSchedule" })
        {
            using HttpResponseMessage response = await PushAsync(owner, Guid.NewGuid(), "saveWorkoutRotation", rotationId, 0,
                new { rotationId, baseVersion = 0, planIds = new[] { push } }, resourceType);
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
            Assert.AreEqual("unsupported_operation", await ProblemCodeAsync(response));
        }

        await using AppDbContext check = PostgreSqlTestFixture.CreateContext(connectionString, owner.UserId);
        Assert.AreEqual(0, await check.TrainingSchedules.CountAsync(TestContext.CancellationToken));
    }

    private static object Cycle(Guid scheduleId, long baseVersion, params Guid?[] planIds) => new
    {
        scheduleId,
        baseVersion,
        mode = "cycle",
        anchorDate = (string?)"2026-10-20",
        validFrom = "2026-10-21",
        slots = planIds.Select(planId => new { planId }).ToArray(),
        shifts = Array.Empty<object>(),
        exceptions = Array.Empty<object>(),
    };

    private static System.Text.Json.Nodes.JsonObject WithIdentity(object payload, Guid scheduleId, long baseVersion) =>
        Mutate(payload, node =>
        {
            node["scheduleId"] = scheduleId;
            node["baseVersion"] = baseVersion;
        });

    private static System.Text.Json.Nodes.JsonObject Mutate(object payload, Action<System.Text.Json.Nodes.JsonObject> change)
    {
        var node = System.Text.Json.Nodes.JsonNode.Parse(JsonSerializer.Serialize(payload, JsonOptions))!.AsObject();
        change(node);
        return node;
    }

    private static System.Text.Json.Nodes.JsonNode Nodes(object value) =>
        System.Text.Json.Nodes.JsonNode.Parse(JsonSerializer.Serialize(value, JsonOptions))!;

    private async Task<Guid> CreatePlanAsync(Device device, string name)
    {
        Guid exerciseId;
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, device.UserId))
        {
            exerciseId = await context.Exercises.Where(item => item.OwnerUserId == null)
                .OrderBy(item => item.Id).Select(item => item.Id).FirstAsync(TestContext.CancellationToken);
        }
        Guid planId = Guid.NewGuid();
        await PushOkAsync(device, Guid.NewGuid(), "createTrainingPlan", planId, 0, new
        {
            plan = new
            {
                planId,
                name,
                notes = (string?)null,
                previousValueSource = "exercise",
                entries = new[]
                {
                    new { entryId = Guid.NewGuid(), exerciseId, warmupSets = 0, workingSets = 3, notes = (string?)null, supersetId = (Guid?)null },
                },
            },
        }, "TrainingPlan");
        return planId;
    }

    private async Task<PushMutationResponse> PushOkAsync(
        Device device,
        Guid mutationId,
        string operation,
        Guid resourceId,
        long baseVersion,
        object payload,
        string resourceType = "TrainingSchedule")
    {
        using HttpResponseMessage response = await PushAsync(device, mutationId, operation, resourceId, baseVersion, payload, resourceType);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        return (await response.Content.ReadFromJsonAsync<PushMutationResponse>(TestContext.CancellationToken))!;
    }

    private async Task<HttpResponseMessage> PushAsync(
        Device device,
        Guid mutationId,
        string operation,
        Guid resourceId,
        long baseVersion,
        object payload,
        string resourceType = "TrainingSchedule")
    {
        // A replayed mutation must repeat the client sequence of its first attempt.
        if (!device.Sequences.TryGetValue(mutationId, out long sequence))
        {
            sequence = ++device.LastSequence;
            device.Sequences[mutationId] = sequence;
        }
        var body = new PushMutationRequest(
            SyncProtocol.CurrentVersion,
            device.ClientId,
            sequence,
            operation,
            [new ResourceVersionRequest(resourceType, resourceId, baseVersion)],
            null,
            JsonSerializer.SerializeToElement(payload, JsonOptions));
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/sync/mutations/{mutationId}")
        {
            Content = JsonContent.Create(body),
        };
        device.Session.Apply(request);
        return await device.Client.SendAsync(request, TestContext.CancellationToken);
    }

    private async Task<PullChangesResponse> PullAsync(Device device)
    {
        // Training schedules need protocol 4; a pull without a version counts as protocol 3.
        using var request = new HttpRequestMessage(
            HttpMethod.Get, $"/api/v1/sync/changes?after=0&limit=200&protocolVersion={SyncProtocol.CurrentVersion}");
        device.Session.Apply(request);
        using HttpResponseMessage response = await device.Client.SendAsync(request, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        return (await response.Content.ReadFromJsonAsync<PullChangesResponse>(TestContext.CancellationToken))!;
    }

    private async Task<Device> SignInDeviceAsync(WebApplication app, string email)
    {
        Guid userId = Guid.NewGuid();
        await using (AsyncServiceScope scope = app.Services.CreateAsyncScope())
        {
            UserManager<AppUser> users = scope.ServiceProvider.GetRequiredService<UserManager<AppUser>>();
            IdentityResult result = await users.CreateAsync(new AppUser
            {
                Id = userId,
                UserName = email,
                Email = email,
                EmailConfirmed = true,
                IsActive = true,
            }, Password);
            Assert.IsTrue(result.Succeeded, string.Join(", ", result.Errors.Select(error => error.Code)));
        }

        HttpClient client = app.GetTestClient();
        client.BaseAddress = new Uri(TestOrigin);
        TestSession session = await TestSession.SignInAsync(client, email, Password);
        var device = new Device(userId, Guid.NewGuid(), client, session);
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/sync/clients/{device.ClientId}")
        {
            Content = JsonContent.Create(new RegisterSyncClientRequest(device.ClientId, "iPhone", SyncProtocol.CurrentVersion, true)),
        };
        session.Apply(request);
        using HttpResponseMessage response = await client.SendAsync(request, TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode, await response.Content.ReadAsStringAsync(TestContext.CancellationToken));
        return device;
    }

    private async Task<WebApplication> CreateApplicationAsync()
    {
        connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString))
            await context.Database.MigrateAsync(TestContext.CancellationToken);

        string keyRingPath = Path.Combine(Path.GetTempPath(), $"gainer-training-schedule-api-{Guid.NewGuid():N}");
        keyRingPaths.Add(keyRingPath);
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseTestServer();
        builder.Configuration["ConnectionStrings:gainer-db"] = connectionString;
        builder.Configuration[GainerIdentityOptions.DataProtectionKeysPathConfigurationKey] = keyRingPath;
        builder.AddGainerApi();
        builder.AddGainerPersistence();
        builder.AddGainerIdentity();
        WebApplication app = builder.Build();
        app.MapGainerApi();
        await app.StartAsync(TestContext.CancellationToken);
        return app;
    }

    private static async Task<string?> ProblemCodeAsync(HttpResponseMessage response)
    {
        using JsonDocument problem = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync());
        return problem.RootElement.GetProperty("code").GetString();
    }

    private sealed class Device(Guid userId, Guid clientId, HttpClient client, TestSession session)
    {
        public Guid UserId { get; } = userId;
        public Guid ClientId { get; } = clientId;
        public HttpClient Client { get; } = client;
        public TestSession Session { get; } = session;
        public long LastSequence { get; set; }
        public Dictionary<Guid, long> Sequences { get; } = [];
    }
}
