using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class WorkoutTemplatePersistenceTests
{
    private static PostgreSqlTestFixture? fixture;
    private static PostgreSqlTestFixture Fixture => fixture
        ?? throw new InvalidOperationException("The PostgreSQL fixture has not started.");

    [ClassInitialize]
    public static async Task StartAsync(TestContext context)
    {
        _ = context;
        fixture = new PostgreSqlTestFixture();
        await fixture.StartAsync();
    }

    [ClassCleanup]
    public static async Task StopAsync()
    {
        if (fixture is not null)
        {
            await fixture.DisposeAsync();
        }
    }

    [TestMethod]
    public async Task TemplateSavesOrderedItemsAndCanAtomicallyReorderStableItemIds()
    {
        (string connectionString, Guid userId) = await CreateDatabaseAsync();
        Guid[] exerciseIds = await BaseExerciseIdsAsync(connectionString, userId, 2);
        Guid firstItem = Guid.NewGuid();
        Guid secondItem = Guid.NewGuid();
        Guid templateId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        WorkoutTemplateSnapshot created = await handler.SaveAsync(SaveWorkoutTemplateMutation.Create(
            Metadata(),
            templateId,
            0,
            "  Upper A  ",
            [
                Item(firstItem, exerciseIds[0], sets: 3, min: 6, max: 8, rir: 2, rest: 180, notes: "  controlled  "),
                Item(secondItem, exerciseIds[1], sets: 4, min: 8, max: 12),
            ]));
        Assert.AreEqual("Upper A", created.Name);
        Assert.AreEqual("controlled", created.Items[0].Notes);
        Assert.AreEqual(1, created.Version);

        WorkoutTemplateSnapshot reordered = await handler.SaveAsync(SaveWorkoutTemplateMutation.Create(
            Metadata(), templateId, 1, "Upper B",
            [Item(secondItem, exerciseIds[1], 4, 8, 12), Item(firstItem, exerciseIds[0], 3, 6, 8)]));
        Assert.AreEqual(2, reordered.Version);
        context.ChangeTracker.Clear();
        List<WorkoutTemplateItem> stored = await context.WorkoutTemplateItems
            .OrderBy(item => item.Position)
            .ToListAsync();
        CollectionAssert.AreEqual(new[] { secondItem, firstItem }, stored.Select(item => item.Id).ToArray());
    }

    [TestMethod]
    public async Task InvalidTemplateDoesNotChangePreviouslyValidState()
    {
        (string connectionString, Guid userId) = await CreateDatabaseAsync();
        Guid exerciseId = (await BaseExerciseIdsAsync(connectionString, userId, 1))[0];
        Guid templateId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = Handler(context, userId);
        await handler.SaveAsync(SaveWorkoutTemplateMutation.Create(
            Metadata(), templateId, 0, "Valid", [Item(Guid.NewGuid(), exerciseId, 3, 8, 12)]));

        WorkoutTemplateValidationException error = await Assert.ThrowsAsync<WorkoutTemplateValidationException>(() =>
            handler.SaveAsync(SaveWorkoutTemplateMutation.Create(
                Metadata(), templateId, 1, "Invalid", [Item(Guid.NewGuid(), exerciseId, 0, 12, 8, rir: 11, rest: -1)])));
        Assert.IsGreaterThanOrEqualTo(3, error.Errors.Count);
        context.ChangeTracker.Clear();
        WorkoutTemplate stored = await context.WorkoutTemplates.SingleAsync();
        Assert.AreEqual("Valid", stored.Name);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task ForeignOrNewlyArchivedCustomExerciseCannotEnterTemplateButExistingReferenceSurvives()
    {
        (string connectionString, Guid ownerId) = await CreateDatabaseAsync();
        Guid otherId = Guid.NewGuid();
        await SeedUserAsync(connectionString, otherId);
        Guid customId = Guid.NewGuid();
        await using (AppDbContext customContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var customHandler = new CustomExerciseMutationHandler(customContext, new User(ownerId), TimeProvider.System);
            await customHandler.CreateAsync(CreateCustomExerciseMutation.Create(
                Metadata(), customId, new CustomExerciseValues("Owner movement")));
        }

        Guid templateId = Guid.NewGuid();
        Guid itemId = Guid.NewGuid();
        await using (AppDbContext templateContext = Fixture.CreateContext(connectionString, ownerId))
        {
            await Handler(templateContext, ownerId).SaveAsync(SaveWorkoutTemplateMutation.Create(
                Metadata(), templateId, 0, "Plan", [Item(itemId, customId, 3, 8, 10)]));
        }
        await using (AppDbContext archiveContext = Fixture.CreateContext(connectionString, ownerId))
        {
            var customHandler = new CustomExerciseMutationHandler(archiveContext, new User(ownerId), TimeProvider.System);
            await customHandler.ArchiveAsync(ArchiveCustomExerciseMutation.Create(Metadata(), customId, 1));
        }
        await using (AppDbContext updateContext = Fixture.CreateContext(connectionString, ownerId))
        {
            WorkoutTemplateSnapshot updated = await Handler(updateContext, ownerId).SaveAsync(
                SaveWorkoutTemplateMutation.Create(Metadata(), templateId, 1, "Plan renamed", [Item(itemId, customId, 3, 8, 10)]));
            Assert.AreEqual(2, updated.Version);
            await Assert.ThrowsAsync<WorkoutTemplateValidationException>(() => Handler(updateContext, ownerId).SaveAsync(
                SaveWorkoutTemplateMutation.Create(
                    Metadata(), Guid.NewGuid(), 0, "New plan", [Item(Guid.NewGuid(), customId, 3, 8, 10)])));
        }
        await using (AppDbContext foreignContext = Fixture.CreateContext(connectionString, otherId))
        {
            await Assert.ThrowsAsync<WorkoutTemplateValidationException>(() => Handler(foreignContext, otherId).SaveAsync(
                SaveWorkoutTemplateMutation.Create(
                    Metadata(), Guid.NewGuid(), 0, "Foreign", [Item(Guid.NewGuid(), customId, 3, 8, 10)])));
            await Assert.ThrowsAsync<WorkoutTemplateNotFoundException>(() => Handler(foreignContext, otherId).ArchiveAsync(
                ArchiveWorkoutTemplateMutation.Create(Metadata(), templateId, 2)));
        }
    }

    [TestMethod]
    public async Task PostgreSqlRejectsInvalidItemAndDuplicatePosition()
    {
        (string connectionString, Guid userId) = await CreateDatabaseAsync();
        Guid exerciseId = (await BaseExerciseIdsAsync(connectionString, userId, 1))[0];
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var template = new WorkoutTemplate
        {
            Id = Guid.NewGuid(),
            Name = "Direct",
            CreatedAtUtc = DateTime.UtcNow,
            UpdatedAtUtc = DateTime.UtcNow,
            Version = 1,
        };
        context.WorkoutTemplates.Add(template);
        context.WorkoutTemplateItems.Add(new WorkoutTemplateItem
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            ExerciseId = exerciseId,
            Position = 0,
            PlannedSets = 0,
            MinimumRepetitions = 8,
            MaximumRepetitions = 6,
        });
        await Assert.ThrowsAsync<DbUpdateException>(() => context.SaveChangesAsync());
    }

    [TestMethod]
    public async Task RotationAdvancesWrapsSkipsArchivedAndSupportsEmptyState()
    {
        (string connectionString, Guid userId) = await CreateDatabaseAsync();
        Guid exerciseId = (await BaseExerciseIdsAsync(connectionString, userId, 1))[0];
        Guid[] templates = new Guid[3];
        for (int index = 0; index < templates.Length; index++)
        {
            templates[index] = await CreateTemplateAsync(connectionString, userId, exerciseId, $"Plan {index + 1}");
        }

        Guid rotationId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var handler = new WorkoutRotationHandler(context, new User(userId), TimeProvider.System);
        WorkoutRotationSnapshot initial = await handler.SaveAsync(SaveWorkoutRotationMutation.Create(
            Metadata(),
            rotationId,
            0,
            templates.Select(id => new WorkoutRotationEntry(Guid.NewGuid(), id)).ToArray()));
        Assert.AreEqual(templates[0], initial.NextTemplateId);

        WorkoutRotationSnapshot afterFirst = await handler.AdvanceAsync(
            AdvanceWorkoutRotationMutation.Create(Metadata(), rotationId, 1, templates[0]));
        Assert.AreEqual(templates[1], afterFirst.NextTemplateId);
        WorkoutRotationSnapshot afterSecond = await handler.AdvanceAsync(
            AdvanceWorkoutRotationMutation.Create(Metadata(), rotationId, 2, templates[1]));
        Assert.AreEqual(templates[2], afterSecond.NextTemplateId);
        WorkoutRotationSnapshot wrapped = await handler.AdvanceAsync(
            AdvanceWorkoutRotationMutation.Create(Metadata(), rotationId, 3, templates[2]));
        Assert.AreEqual(templates[0], wrapped.NextTemplateId);

        context.ChangeTracker.Clear();
        WorkoutTemplate archived = await context.WorkoutTemplates.SingleAsync(item => item.Id == templates[1]);
        archived.IsArchived = true;
        archived.Version++;
        await context.SaveChangesAsync();
        WorkoutRotationSnapshot skipped = await handler.AdvanceAsync(
            AdvanceWorkoutRotationMutation.Create(Metadata(), rotationId, 4, templates[0]));
        Assert.AreEqual(templates[2], skipped.NextTemplateId);

        WorkoutRotationSnapshot empty = await handler.SaveAsync(SaveWorkoutRotationMutation.Create(
            Metadata(), rotationId, 5, []));
        Assert.IsNull(empty.NextTemplateId);
        Assert.HasCount(0, empty.Entries);
    }

    [TestMethod]
    public async Task RotationRejectsForeignTemplatesAndIsIsolatedPerUser()
    {
        (string connectionString, Guid firstUser) = await CreateDatabaseAsync();
        Guid secondUser = Guid.NewGuid();
        await SeedUserAsync(connectionString, secondUser);
        Guid exerciseId = (await BaseExerciseIdsAsync(connectionString, firstUser, 1))[0];
        Guid firstTemplate = await CreateTemplateAsync(connectionString, firstUser, exerciseId, "First plan");
        Guid secondTemplate = await CreateTemplateAsync(connectionString, secondUser, exerciseId, "Second plan");

        await using (AppDbContext firstContext = Fixture.CreateContext(connectionString, firstUser))
        {
            var first = new WorkoutRotationHandler(firstContext, new User(firstUser), TimeProvider.System);
            await Assert.ThrowsAsync<WorkoutRotationValidationException>(() => first.SaveAsync(
                SaveWorkoutRotationMutation.Create(
                    Metadata(), Guid.NewGuid(), 0,
                    [new WorkoutRotationEntry(Guid.NewGuid(), secondTemplate)])));
            Assert.IsNull(await first.GetAsync());
            await first.SaveAsync(SaveWorkoutRotationMutation.Create(
                Metadata(), Guid.NewGuid(), 0,
                [new WorkoutRotationEntry(Guid.NewGuid(), firstTemplate)]));
        }
        await using (AppDbContext secondContext = Fixture.CreateContext(connectionString, secondUser))
        {
            var second = new WorkoutRotationHandler(secondContext, new User(secondUser), TimeProvider.System);
            Assert.IsNull(await second.GetAsync());
        }
    }

    private static WorkoutTemplateMutationHandler Handler(AppDbContext context, Guid userId) =>
        new(context, new User(userId), TimeProvider.System);

    private static WorkoutTemplateItemValues Item(
        Guid itemId, Guid exerciseId, int sets, int min, int max,
        decimal? rir = null, int? rest = null, string? notes = null) =>
        new(itemId, exerciseId, sets, min, max, rir, rest, notes);

    private static MutationMetadata Metadata() => MutationMetadata.Create(Guid.NewGuid(), Guid.NewGuid(), 1);

    private static async Task<(string ConnectionString, Guid UserId)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        await using (AppDbContext context = Fixture.CreateContext(connectionString))
        {
            await context.Database.MigrateAsync();
        }
        Guid userId = Guid.NewGuid();
        await SeedUserAsync(connectionString, userId);
        return (connectionString, userId);
    }

    private static async Task SeedUserAsync(string connectionString, Guid userId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        context.Users.Add(new AppUser
        {
            Id = userId,
            UserName = $"{userId:N}@example.test",
            NormalizedUserName = $"{userId:N}@EXAMPLE.TEST",
            Email = $"{userId:N}@example.test",
            NormalizedEmail = $"{userId:N}@EXAMPLE.TEST",
            IsActive = true,
            SecurityStamp = Guid.NewGuid().ToString("N"),
            ConcurrencyStamp = Guid.NewGuid().ToString("N"),
        });
        await context.SaveChangesAsync();
    }

    private static async Task<Guid[]> BaseExerciseIdsAsync(string connectionString, Guid userId, int count)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        return await context.Exercises.Where(item => item.OwnerUserId == null)
            .OrderBy(item => item.Id).Select(item => item.Id).Take(count).ToArrayAsync();
    }

    private static async Task<Guid> CreateTemplateAsync(
        string connectionString,
        Guid userId,
        Guid exerciseId,
        string name)
    {
        Guid templateId = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        await Handler(context, userId).SaveAsync(SaveWorkoutTemplateMutation.Create(
            Metadata(), templateId, 0, name,
            [Item(Guid.NewGuid(), exerciseId, 3, 8, 12)]));
        return templateId;
    }

    private sealed record User(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
