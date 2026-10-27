using System.Text.Json;
using Gainer.Core.Nutrition;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class TrainingRestDayNutritionSyncTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly DateTimeOffset ServerNow = new(2026, 10, 24, 12, 0, 0, TimeSpan.Zero);
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture ?? throw new InvalidOperationException("PostgreSQL is not started.");

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

    [TestMethod]
    public async Task TargetChangesOnlyAffectDaysFromTheirStart()
    {
        (string connectionString, Guid user, Guid otherUser) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid scheduleId = Guid.NewGuid();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        object rest = Rest(2200m, 180m, 190m, 80m);

        await Apply(connectionString, user, client, 1, Targets(scheduleId, 0, Version(first, "2026-10-01", null, 2600m)));

        // Edited offline on 22 October, synced two days later.
        ProcessSyncMutationCommand offlineEdit = For(Targets(scheduleId, 1,
            Version(first, "2026-10-01", "2026-10-21", 2600m),
            Version(second, "2026-10-22", null, 2600m, rest)), client, 2);
        await Apply(connectionString, user, client, 2, offlineEdit);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            ProcessedSyncMutationResult replayed = await Processor(context, user).ProcessAsync(offlineEdit, TestContext.CancellationToken);
            Assert.IsTrue(replayed.Replayed);
            NutritionTargetScheduleSnapshot schedule = await Schedule(context);
            Assert.AreEqual(2, schedule.Version);
            NutritionRestDayTargetDraft restDay = schedule.Versions[1].RestDay ?? throw new AssertFailedException();
            Assert.AreEqual(2200m, restDay.Kilocalories);
            Assert.IsFalse(restDay.RequiresEnergyMismatchConfirmation);
            Assert.IsNull(schedule.Versions[0].RestDay);
        }

        // A second change on the same day replaces the version that starts that day.
        await Apply(connectionString, user, client, 3, Targets(scheduleId, 2,
            Version(first, "2026-10-01", "2026-10-21", 2600m),
            Version(second, "2026-10-22", null, 2550m, rest)));

        // Days before the change start stay unchanged.
        await ExpectConflict(connectionString, user, client, 4, Targets(scheduleId, 3,
            Version(first, "2026-10-01", "2026-10-21", 2700m),
            Version(second, "2026-10-22", null, 2550m, rest)));

        // A new version cannot start before a version that has begun.
        await ExpectConflict(connectionString, user, client, 4, Targets(scheduleId, 3,
            Version(first, "2026-10-01", "2026-10-19", 2600m),
            Version(Guid.NewGuid(), "2026-10-20", null, 2400m)));

        // An older client sends the version without rest day fields; the server accepts it.
        await Apply(connectionString, user, client, 4, Targets(scheduleId, 3,
            Version(first, "2026-10-01", "2026-10-21", 2600m),
            Version(second, "2026-10-22", null, 2550m)));
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            NutritionTargetScheduleSnapshot schedule = await Schedule(context);
            Assert.AreEqual(4, schedule.Version);
            Assert.AreEqual(2550m, schedule.Versions[1].Kilocalories);
            Assert.IsNull(schedule.Versions[1].RestDay);
        }

        await using AppDbContext other = PostgreSqlTestFixture.CreateContext(connectionString, otherUser);
        Assert.IsNull(await new SmartNutritionQueries(other).GetNutritionTargetScheduleAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task PlannedPhasesCanBeDroppedAndOlderClientsKeepWorking()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid scheduleId = Guid.NewGuid();
        Guid running = Guid.NewGuid();
        Guid planned = Guid.NewGuid();
        Guid current = Guid.NewGuid();

        await Apply(connectionString, user, client, 1, Targets(scheduleId, 0,
            Version(running, "2026-10-01", "2026-11-29", 2600m),
            Version(planned, "2026-11-30", null, 2800m)));

        // The simple editor saves on 24 October: the running phase ends, the planned one is dropped.
        await Apply(connectionString, user, client, 2, Targets(scheduleId, 1,
            Version(running, "2026-10-01", "2026-10-23", 2600m),
            Version(current, "2026-10-24", null, 2500m, Rest(2100m, 180m, 165m, 80m))));

        // Flow of an older app: end today, new phase from tomorrow.
        await Apply(connectionString, user, client, 3, Targets(scheduleId, 2,
            Version(running, "2026-10-01", "2026-10-23", 2600m),
            Version(current, "2026-10-24", "2026-10-24", 2500m, Rest(2100m, 180m, 165m, 80m)),
            Version(Guid.NewGuid(), "2026-10-25", null, 2450m)));

        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        NutritionTargetScheduleSnapshot schedule = await Schedule(context);
        Assert.AreSequenceEqual(
            new[] { new DateOnly(2026, 10, 1), new DateOnly(2026, 10, 24), new DateOnly(2026, 10, 25) }, schedule.Versions.Select(item => item.EffectiveFrom).ToArray());
        Assert.DoesNotContain(item => item.TargetVersionId == planned, schedule.Versions);
        Assert.AreEqual(2100m, schedule.Versions[1].RestDay?.Kilocalories);
    }

    [TestMethod]
    public async Task InvalidRestDayTargetsAreRejected()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid scheduleId = Guid.NewGuid();
        object percentNot100 = new
        {
            inputMode = "Percent",
            kilocalories = 2200m,
            proteinGrams = 165m,
            carbohydrateGrams = 220m,
            fatGrams = 49m,
            proteinPercent = 30m,
            carbohydratePercent = 40m,
            fatPercent = 20m,
        };
        object incomplete = new { inputMode = "Grams", kilocalories = 2200m, proteinGrams = 180m, carbohydrateGrams = 190m };

        foreach (object rest in new[] { percentNot100, incomplete })
        {
            await ExpectInvalid(connectionString, user, client, 1,
                Targets(scheduleId, 0, Version(Guid.NewGuid(), "2026-10-01", null, 2600m, rest)));
        }
    }

    [TestMethod]
    public async Task DayKindIsStoredWithoutEntriesClearedByOlderPayloadsAndValidated()
    {
        (string connectionString, Guid user, Guid otherUser) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid dayId = Guid.NewGuid();

        await Apply(connectionString, user, client, 1, DayCommand(dayId, 0, "Rest"));
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            NutritionDay day = await context.NutritionDays.SingleAsync(TestContext.CancellationToken);
            Assert.AreEqual(NutritionDayKind.Rest, day.DayKind);
            Assert.AreEqual(0, await context.NutritionEntries.CountAsync(TestContext.CancellationToken));
        }

        await Apply(connectionString, user, client, 2, DayCommand(dayId, 1, null));
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            Assert.IsNull((await context.NutritionDays.SingleAsync(TestContext.CancellationToken)).DayKind);
        }

        await ExpectInvalid(connectionString, user, client, 3, DayCommand(dayId, 2, "Refeed"));

        await using AppDbContext other = PostgreSqlTestFixture.CreateContext(connectionString, otherUser);
        Assert.AreEqual(0, await other.NutritionDays.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task DayTemplatesAreSavedOverwrittenDeletedAndUserScoped()
    {
        (string connectionString, Guid user, Guid otherUser) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        await RegisterAsync(connectionString, otherUser, otherClient);
        Guid templateId = Guid.NewGuid();

        ProcessSyncMutationCommand save = For(TemplateCommand(templateId, 0, "Trainingstag", "Training",
            Entry("Breakfast", 0, "Haferflocken", 80m), Entry("Lunch", 0, "Reis", 150m)), client, 1);
        await Apply(connectionString, user, client, 1, save);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            ProcessedSyncMutationResult replayed = await Processor(context, user).ProcessAsync(save, TestContext.CancellationToken);
            Assert.IsTrue(replayed.Replayed);
            NutritionDayTemplate template = await context.NutritionDayTemplates.Include(item => item.Entries).SingleAsync(TestContext.CancellationToken);
            Assert.AreEqual(NutritionDayKind.Training, template.DayKind);
            Assert.HasCount(2, template.Entries);
        }

        await Apply(connectionString, user, client, 2,
            TemplateCommand(templateId, 1, "Trainingstag", "Training", Entry("Dinner", 0, "Hähnchen", 200m)));
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            NutritionDayTemplate template = await context.NutritionDayTemplates.Include(item => item.Entries).SingleAsync(TestContext.CancellationToken);
            Assert.AreEqual(2, template.Version);
            Assert.AreEqual("Hähnchen", template.Entries.Single().ProductName);
            NutritionDayTemplateSnapshot snapshot = NutritionDayTemplateMutationHandler.Snapshot(template);
            Assert.AreEqual(330m, snapshot.Totals.Kilocalories);
        }

        await ExpectConflict(connectionString, user, client, 3,
            TemplateCommand(templateId, 1, "Trainingstag", null, Entry("Dinner", 0, "Hähnchen", 200m)));

        await using (AppDbContext foreign = PostgreSqlTestFixture.CreateContext(connectionString, otherUser))
        {
            Assert.AreEqual(0, await foreign.NutritionDayTemplates.CountAsync(TestContext.CancellationToken));
            SyncMutationConflictException denied = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
                Processor(foreign, otherUser).ProcessAsync(DeleteTemplateCommand(templateId, 2, otherClient, 1), TestContext.CancellationToken));
            Assert.AreEqual("resource_not_found", denied.Code);
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            ProcessedSyncMutationResult deleted = await Processor(context, user)
                .ProcessAsync(DeleteTemplateCommand(templateId, 2, client, 3), TestContext.CancellationToken);
            Assert.IsTrue(deleted.Changes.Single().IsTombstone);
            Assert.AreEqual(0, await context.NutritionDayTemplates.CountAsync(TestContext.CancellationToken));
            Assert.AreEqual(0, await context.NutritionDayTemplateEntries.CountAsync(TestContext.CancellationToken));
        }
    }

    [TestMethod]
    public async Task DayTemplateEntriesWithStableIdsCanBeDeletedInsertedAndSwapped()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        Guid templateId = Guid.NewGuid();
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid(), added = Guid.NewGuid();
        object[][] saves =
        [
            [Entry("Breakfast", 0, "A", 80m, a), Entry("Breakfast", 1, "B", 80m, b), Entry("Breakfast", 2, "C", 80m, c)],
            // Deleting the first entry moves the others up.
            [Entry("Breakfast", 0, "B", 80m, b), Entry("Breakfast", 1, "C", 80m, c)],
            // A new first entry moves the others down.
            [Entry("Breakfast", 0, "Neu", 80m, added), Entry("Breakfast", 1, "B", 80m, b), Entry("Breakfast", 2, "C", 80m, c)],
            // Swapping two entries.
            [Entry("Breakfast", 0, "Neu", 80m, added), Entry("Breakfast", 1, "C", 80m, c), Entry("Breakfast", 2, "B", 80m, b)],
        ];

        for (int index = 0; index < saves.Length; index++)
        {
            await Apply(connectionString, user, client, index + 1,
                TemplateCommand(templateId, index, "Trainingstag", "Training", saves[index]));
        }

        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        NutritionDayTemplate template = await context.NutritionDayTemplates.Include(item => item.Entries).SingleAsync(TestContext.CancellationToken);
        Assert.AreEqual(saves.Length, template.Version);
        Assert.AreSequenceEqual(
            new[] { added, c, b }, template.Entries.OrderBy(item => item.Position).Select(item => item.Id).ToArray());
    }

    [TestMethod]
    public async Task DayTemplatesAreValidated()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        Guid client = Guid.NewGuid();
        await RegisterAsync(connectionString, user, client);
        object oats = Entry("Breakfast", 0, "Haferflocken", 80m);
        object[] tooMany = Enumerable.Range(0, 201).Select(position => Entry("Snacks", position, "Nuss", 5m)).ToArray();
        Guid duplicateId = Guid.NewGuid();

        await ExpectInvalid(connectionString, user, client, 1, TemplateCommand(Guid.NewGuid(), 0, " ", null, oats));
        await ExpectInvalid(connectionString, user, client, 1, TemplateCommand(Guid.NewGuid(), 0, "Ruhetag", "Refeed", oats));
        await ExpectInvalid(connectionString, user, client, 1, TemplateCommand(Guid.NewGuid(), 0, "Ruhetag", null));
        await ExpectInvalid(connectionString, user, client, 1, TemplateCommand(Guid.NewGuid(), 0, "Ruhetag", null, tooMany));
        await ExpectInvalid(connectionString, user, client, 1, TemplateCommand(Guid.NewGuid(), 0, "Ruhetag", null,
            Entry("Breakfast", 0, "A", 10m, duplicateId), Entry("Lunch", 0, "B", 10m, duplicateId)));

        long sequence = 1;
        for (int index = 0; index < NutritionLimits.MaxDayTemplates; index++)
        {
            await Apply(connectionString, user, client, sequence++,
                TemplateCommand(Guid.NewGuid(), 0, $"Vorlage {index}", null, Entry("Breakfast", 0, "Haferflocken", 80m)));
        }
        await ExpectInvalid(connectionString, user, client, sequence,
            TemplateCommand(Guid.NewGuid(), 0, "Zu viel", null, Entry("Breakfast", 0, "Haferflocken", 80m)));
    }

    private static object Rest(decimal kcal, decimal protein, decimal carbohydrates, decimal fat) => new
    {
        inputMode = "Grams",
        kilocalories = kcal,
        proteinGrams = protein,
        carbohydrateGrams = carbohydrates,
        fatGrams = fat,
    };

    private static Dictionary<string, object?> Version(
        Guid id, string from, string? until, decimal kcal, object? rest = null)
    {
        var version = new Dictionary<string, object?>
        {
            ["targetVersionId"] = id,
            ["name"] = "Ziele",
            ["category"] = "Custom",
            ["inputMode"] = "Grams",
            ["effectiveFrom"] = from,
            ["effectiveUntil"] = until,
            ["kilocalories"] = kcal,
            ["proteinGrams"] = 180m,
            ["carbohydrateGrams"] = 290m,
            ["fatGrams"] = 80m,
            ["origin"] = "Manual",
        };
        if (rest is not null) version["restDay"] = rest;
        return version;
    }

    private static ProcessSyncMutationCommand Targets(Guid scheduleId, long baseVersion, params object[] versions) =>
        Command("saveNutritionTargetSchedule", "NutritionTargetSchedule", scheduleId, baseVersion,
            new { nutritionTargetScheduleId = scheduleId, baseVersion, versions });

    private static ProcessSyncMutationCommand DayCommand(Guid dayId, long baseVersion, string? dayKind) =>
        Command("saveNutritionDay", "NutritionDay", dayId, baseVersion, new
        {
            nutritionDayId = dayId,
            localDate = new DateOnly(2026, 10, 23),
            baseVersion,
            entries = Array.Empty<object>(),
            dayKind,
        });

    private static ProcessSyncMutationCommand TemplateCommand(
        Guid templateId, long baseVersion, string name, string? dayKind, params object[] entries) =>
        Command("saveNutritionDayTemplate", "NutritionDayTemplate", templateId, baseVersion,
            new { templateId, baseVersion, name, dayKind, entries });

    private static ProcessSyncMutationCommand DeleteTemplateCommand(Guid templateId, long baseVersion, Guid client, long sequence) =>
        For(Command("deleteNutritionDayTemplate", "NutritionDayTemplate", templateId, baseVersion,
            new { templateId, baseVersion }), client, sequence);

    private static object Entry(string meal, int position, string name, decimal grams, Guid? id = null) => new
    {
        entryId = id ?? Guid.NewGuid(),
        meal,
        position,
        productName = name,
        amountGrams = grams,
        kilocaloriesPer100Grams = 165m,
        proteinGramsPer100Grams = (decimal?)20m,
        carbohydrateGramsPer100Grams = (decimal?)10m,
        fatGramsPer100Grams = (decimal?)5m,
    };

    private static ProcessSyncMutationCommand Command(
        string operation, string resourceType, Guid resourceId, long baseVersion, object payload) => new(
            Guid.NewGuid(),
            new CanonicalMutationContent(
                Gainer.Contracts.Sync.SyncProtocol.CurrentVersion,
                Guid.Empty,
                0,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static ProcessSyncMutationCommand For(ProcessSyncMutationCommand command, Guid client, long sequence) =>
        command.Content.ClientId == Guid.Empty
            ? command with { Content = command.Content with { ClientId = client, ClientSequence = sequence } }
            : command;

    private static async Task Apply(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        _ = await Processor(context, user).ProcessAsync(For(command, client, sequence));
    }

    private static async Task ExpectConflict(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        SyncMutationConflictException conflict = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
        Assert.AreEqual("stale_base_version", conflict.Code);
    }

    private static async Task ExpectInvalid(
        string connectionString, Guid user, Guid client, long sequence, ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        _ = await Assert.ThrowsAsync<SyncMutationValidationException>(() =>
            Processor(context, user).ProcessAsync(For(command, client, sequence)));
    }

    private static async Task<NutritionTargetScheduleSnapshot> Schedule(AppDbContext context) =>
        await new SmartNutritionQueries(context).GetNutritionTargetScheduleAsync() ?? throw new AssertFailedException();

    private static SyncMutationProcessor Processor(AppDbContext context, Guid userId)
    {
        var user = new UserContext(userId);
        var time = new FixedTimeProvider(ServerNow);
        return new SyncMutationProcessor(context, user, new SyncMutationExecutor(context, user, time), time);
    }

    private static async Task RegisterAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Rest day test",
            ProtocolVersion = 2,
            RegisteredAtUtc = DateTime.UtcNow,
            LastSeenAtUtc = DateTime.UtcNow,
        });
        context.UserSyncStates.Add(new UserSyncState
        {
            CurrentRevision = 0,
            ActiveClientId = clientId,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        });
        await context.SaveChangesAsync();
    }

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(first), User(second));
        await context.SaveChangesAsync();
        return (connectionString, first, second);
    }

    private static AppUser User(Guid id) => new()
    {
        Id = id,
        UserName = $"{id:N}@example.test",
        NormalizedUserName = $"{id:N}@EXAMPLE.TEST",
        Email = $"{id:N}@example.test",
        NormalizedEmail = $"{id:N}@EXAMPLE.TEST",
        IsActive = true,
        SecurityStamp = Guid.NewGuid().ToString("N"),
        ConcurrencyStamp = Guid.NewGuid().ToString("N"),
    };

    private sealed record UserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }

    public TestContext TestContext { get; set; } = null!;
}
