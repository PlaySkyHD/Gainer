using System.Text.Json;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.Catalog;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class ExerciseCatalogSyncPersistenceTests
{
    public TestContext TestContext { get; set; } = null!;

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
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
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestMethod]
    public async Task CategoryCreateRenameAndArchiveFollowVersionsAndReplayWithoutDoubleEffect()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid categoryId = Guid.NewGuid();
        Guid createId = Guid.NewGuid();

        ProcessedSyncMutationResult created = await ProcessAsync(connectionString, userId, Command(
            createId, clientId, 1, "createExerciseCategory", "ExerciseCategory", categoryId, 0,
            new { categoryId, name = "  Reha  " }));
        Assert.IsFalse(created.Replayed);
        Assert.AreEqual(1, created.Revision);

        ProcessedSyncMutationResult replayed = await ProcessAsync(connectionString, userId, Command(
            createId, clientId, 1, "createExerciseCategory", "ExerciseCategory", categoryId, 0,
            new { categoryId, name = "  Reha  " }));
        Assert.IsTrue(replayed.Replayed);
        Assert.AreEqual(1, replayed.Revision);

        ProcessedSyncMutationResult renamed = await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 2, "updateExerciseCategory", "ExerciseCategory", categoryId, 1,
            new { categoryId, baseVersion = 1, name = "Rehabilitation" }));
        ExecutedSyncChange renamedChange = renamed.Changes.Single();
        Assert.AreEqual(2, renamedChange.Version);
        Assert.AreEqual("Rehabilitation", ((ExerciseCategorySnapshot)renamedChange.Snapshot!).Name);

        await Assert.ThrowsAsync<SyncMutationConflictException>(() => ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 3, "updateExerciseCategory", "ExerciseCategory", categoryId, 1,
            new { categoryId, baseVersion = 1, name = "Stale" })));

        ProcessedSyncMutationResult archived = await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 3, "archiveExerciseCategory", "ExerciseCategory", categoryId, 2,
            new { categoryId, baseVersion = 2 }));
        Assert.AreEqual(3, archived.Changes.Single().Version);

        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        ExerciseCategory stored = await check.ExerciseCategories.SingleAsync(item => item.Id == categoryId, TestContext.CancellationToken);
        Assert.IsTrue(stored.IsArchived);
        Assert.AreEqual(1, await check.ProcessedMutations.CountAsync(item => item.MutationId == createId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task BaseCategoryCannotBeRenamedOrArchivedThroughSync()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid legs = ExerciseCatalogSnapshot.Document.CategoryId("legs");

        SyncMutationConflictException rename = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
            ProcessAsync(connectionString, userId, Command(
                Guid.NewGuid(), clientId, 1, "updateExerciseCategory", "ExerciseCategory", legs, 1,
                new { categoryId = legs, baseVersion = 1, name = "Changed" })));
        Assert.AreEqual("resource_not_found", rename.Code);

        SyncMutationConflictException archive = await Assert.ThrowsAsync<SyncMutationConflictException>(() =>
            ProcessAsync(connectionString, userId, Command(
                Guid.NewGuid(), clientId, 2, "archiveExerciseCategory", "ExerciseCategory", legs, 1,
                new { categoryId = legs, baseVersion = 1 })));
        Assert.AreEqual("resource_not_found", archive.Code);

        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        ExerciseCategory stored = await check.ExerciseCategories.IgnoreQueryFilters().SingleAsync(item => item.Id == legs, TestContext.CancellationToken);
        Assert.AreEqual(ExerciseCatalogSnapshot.Document.Categories.Single(item => item.Key == "legs").Name, stored.Name);
        Assert.IsFalse(stored.IsArchived);
        Assert.AreEqual(1, stored.Version);
    }

    [TestMethod]
    public async Task CustomExerciseWithTypeFactorsAndCategoriesIsCreatedUpdatedAndReplacedAsAWhole()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid rehaId = Guid.NewGuid();
        Guid exerciseId = Guid.NewGuid();
        Guid legs = ExerciseCatalogSnapshot.Document.CategoryId("legs");
        Guid chest = ExerciseCatalogSnapshot.Document.CategoryId("chest");
        await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 1, "createExerciseCategory", "ExerciseCategory", rehaId, 0,
            new { categoryId = rehaId, name = "Reha" }));

        ProcessedSyncMutationResult created = await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 2, "createCustomExercise", "CustomExercise", exerciseId, 0,
            new { exerciseId, values = Values("Assisted Pull-Up", "assisted", bodyweight: 0.9m, weight: 1.5m, categoryIds: [rehaId, legs]) }));
        CustomExerciseSnapshot createdSnapshot = (CustomExerciseSnapshot)created.Changes.Single().Snapshot!;
        Assert.AreEqual("assisted", createdSnapshot.Values.ExerciseType);
        Assert.AreEqual(0.9m, createdSnapshot.Values.BodyweightFactor);
        Assert.AreEqual(1.5m, createdSnapshot.Values.WeightFactor);
        CollectionAssert.AreEqual(new[] { legs, rehaId }.Order().ToArray(), createdSnapshot.Values.CategoryIds!.ToArray());

        ProcessedSyncMutationResult updated = await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 3, "updateCustomExercise", "CustomExercise", exerciseId, 1,
            new { exerciseId, baseVersion = 1, values = Values("Assisted Pull-Up", "Strength", notes: "Band", categoryIds: [chest]) }));
        CustomExerciseSnapshot updatedSnapshot = (CustomExerciseSnapshot)updated.Changes.Single().Snapshot!;
        Assert.AreEqual(2, updatedSnapshot.Version);
        Assert.AreEqual("strength", updatedSnapshot.Values.ExerciseType);
        Assert.AreEqual("Band", updatedSnapshot.Values.Notes);
        CollectionAssert.AreEqual(new[] { chest }, updatedSnapshot.Values.CategoryIds!.ToArray());

        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        Guid[] assigned = await check.ExerciseCategoryAssignments
            .Where(item => item.ExerciseId == exerciseId)
            .Select(item => item.CategoryId)
            .ToArrayAsync(TestContext.CancellationToken);
        CollectionAssert.AreEqual(new[] { chest }, assigned);
    }

    [TestMethod]
    public async Task UnknownTypeAndInvalidFactorsAreReportedAgainstTheirFields()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid exerciseId = Guid.NewGuid();

        CustomExerciseValidationException unknown = await Assert.ThrowsAsync<CustomExerciseValidationException>(() =>
            ProcessAsync(connectionString, userId, Command(
                Guid.NewGuid(), clientId, 1, "createCustomExercise", "CustomExercise", exerciseId, 0,
                new { exerciseId, values = Values("Cardio", "cardio") })));
        Assert.IsTrue(unknown.Errors.ContainsKey(nameof(CustomExerciseValues.ExerciseType)));
        Assert.IsFalse(unknown.Errors.ContainsKey(nameof(CustomExerciseValues.Name)));

        CustomExerciseValidationException factors = await Assert.ThrowsAsync<CustomExerciseValidationException>(() =>
            ProcessAsync(connectionString, userId, Command(
                Guid.NewGuid(), clientId, 2, "createCustomExercise", "CustomExercise", exerciseId, 0,
                new { exerciseId, values = Values("Factors", "strength", bodyweight: 1.01m, weight: 0m) })));
        Assert.IsTrue(factors.Errors.ContainsKey(nameof(CustomExerciseValues.BodyweightFactor)));
        Assert.IsTrue(factors.Errors.ContainsKey(nameof(CustomExerciseValues.WeightFactor)));

        CustomExerciseValidationException duplicates = await Assert.ThrowsAsync<CustomExerciseValidationException>(() =>
            ProcessAsync(connectionString, userId, Command(
                Guid.NewGuid(), clientId, 3, "createCustomExercise", "CustomExercise", exerciseId, 0,
                new { exerciseId, values = Values("Duplicates", "strength", categoryIds: [ExerciseCatalogSnapshot.Document.CategoryId("legs"), ExerciseCatalogSnapshot.Document.CategoryId("legs")]) })));
        Assert.IsTrue(duplicates.Errors.ContainsKey(nameof(CustomExerciseValues.CategoryIds)));

        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        Assert.AreEqual(0, await check.Exercises.CountAsync(item => item.OwnerUserId == userId, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task ForeignUnknownAndArchivedCategoriesAreRejectedIdentically()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid ownerClient = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, owner, ownerClient);
        await RegisterActiveClientAsync(connectionString, other, otherClient);
        Guid foreignCategory = Guid.NewGuid();
        Guid archivedCategory = Guid.NewGuid();
        await ProcessAsync(connectionString, other, Command(
            Guid.NewGuid(), otherClient, 1, "createExerciseCategory", "ExerciseCategory", foreignCategory, 0,
            new { categoryId = foreignCategory, name = "Foreign" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 1, "createExerciseCategory", "ExerciseCategory", archivedCategory, 0,
            new { categoryId = archivedCategory, name = "Old" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 2, "archiveExerciseCategory", "ExerciseCategory", archivedCategory, 1,
            new { categoryId = archivedCategory, baseVersion = 1 }));

        CustomExerciseValidationException foreign = await AssertRejectedAsync(connectionString, owner, ownerClient, 3, [foreignCategory]);
        CustomExerciseValidationException unknown = await AssertRejectedAsync(connectionString, owner, ownerClient, 4, [Guid.NewGuid()]);
        CustomExerciseValidationException archived = await AssertRejectedAsync(connectionString, owner, ownerClient, 5, [archivedCategory]);
        Assert.AreEqual(unknown.Message, foreign.Message);
        Assert.AreEqual(unknown.Message, archived.Message);
        CollectionAssert.AreEqual(unknown.Errors.Keys.ToArray(), foreign.Errors.Keys.ToArray());
        Assert.AreEqual(unknown.Errors[nameof(CustomExerciseValues.CategoryIds)], foreign.Errors[nameof(CustomExerciseValues.CategoryIds)]);
        Assert.AreEqual(unknown.Errors[nameof(CustomExerciseValues.CategoryIds)], archived.Errors[nameof(CustomExerciseValues.CategoryIds)]);
    }

    [TestMethod]
    public async Task ArchivedCategoryLeavesAssignedExercisesUnchangedAndOutOfSelection()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid categoryId = Guid.NewGuid();
        Guid firstExercise = Guid.NewGuid();
        Guid secondExercise = Guid.NewGuid();
        await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 1, "createExerciseCategory", "ExerciseCategory", categoryId, 0,
            new { categoryId, name = "Reha" }));
        await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 2, "createCustomExercise", "CustomExercise", firstExercise, 0,
            new { exerciseId = firstExercise, values = Values("First", "strength", categoryIds: [categoryId]) }));
        await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 3, "createCustomExercise", "CustomExercise", secondExercise, 0,
            new { exerciseId = secondExercise, values = Values("Second", "bodyweightOnly", categoryIds: [categoryId]) }));

        await ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, 4, "archiveExerciseCategory", "ExerciseCategory", categoryId, 1,
            new { categoryId, baseVersion = 1 }));

        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        Assert.AreEqual(2, await check.ExerciseCategoryAssignments.CountAsync(item => item.CategoryId == categoryId, TestContext.CancellationToken));
        Exercise first = await check.Exercises.SingleAsync(item => item.Id == firstExercise, TestContext.CancellationToken);
        Assert.AreEqual(1, first.Version);
        Assert.IsFalse(first.IsArchived);
        var queries = new ExerciseCatalogQueries(check, new TestUserContext(userId));
        ExerciseCatalogPage page = await queries.SearchAsync(new ExerciseCatalogFilter(Search: "First"), TestContext.CancellationToken);
        Assert.AreEqual(1, page.Total);
        CollectionAssert.AreEqual(new[] { categoryId }, page.Items.Single().CategoryIds.ToArray());
        Assert.IsFalse(page.Categories.Any(item => item.Id == categoryId));
    }

    [TestMethod]
    public async Task RepeatedCustomExerciseMutationIdHasNoDoubleEffect()
    {
        (string connectionString, Guid userId, _) = await CreateDatabaseAsync();
        Guid clientId = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, userId, clientId);
        Guid mutationId = Guid.NewGuid();
        Guid exerciseId = Guid.NewGuid();
        ProcessSyncMutationCommand command = Command(
            mutationId, clientId, 1, "createCustomExercise", "CustomExercise", exerciseId, 0,
            new { exerciseId, values = Values("Once", "strength") });

        ProcessedSyncMutationResult first = await ProcessAsync(connectionString, userId, command);
        ProcessedSyncMutationResult second = await ProcessAsync(connectionString, userId, command);

        Assert.IsFalse(first.Replayed);
        Assert.IsTrue(second.Replayed);
        await using AppDbContext check = Fixture.CreateContext(connectionString, userId);
        Assert.AreEqual(1, await check.Exercises.CountAsync(item => item.OwnerUserId == userId, TestContext.CancellationToken));
        Assert.AreEqual(1, await check.ChangeBatches.CountAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CategoryChangesReachOnlyTheOwnersPull()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid ownerClient = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, owner, ownerClient);
        await RegisterActiveClientAsync(connectionString, other, otherClient);
        Guid categoryId = Guid.NewGuid();
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 1, "createExerciseCategory", "ExerciseCategory", categoryId, 0,
            new { categoryId, name = "Private" }));

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        SyncChangeFeedPage ownerPage = await new SyncChangeFeed(ownerContext).GetAsync(0, 10, Gainer.Contracts.Sync.SyncProtocol.CurrentVersion, TestContext.CancellationToken);
        Assert.IsTrue(ownerPage.Batches.SelectMany(batch => batch.Changes)
            .Any(change => change.ResourceType == "ExerciseCategory" && change.ResourceId == categoryId));

        await using AppDbContext otherContext = Fixture.CreateContext(connectionString, other);
        SyncChangeFeedPage otherPage = await new SyncChangeFeed(otherContext).GetAsync(0, 10, Gainer.Contracts.Sync.SyncProtocol.CurrentVersion, TestContext.CancellationToken);
        Assert.IsFalse(otherPage.Batches.Any());
    }

    [TestMethod]
    public async Task InterceptorRejectsAssignmentsOutsideTheUsersOwnership()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid ownerClient = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, owner, ownerClient);
        await RegisterActiveClientAsync(connectionString, other, otherClient);
        Guid ownerExercise = Guid.NewGuid();
        Guid foreignCategory = Guid.NewGuid();
        Guid ownerCategory = Guid.NewGuid();
        Guid archivedCategory = Guid.NewGuid();
        Guid baseCategory = ExerciseCatalogSnapshot.Document.CategoryId("legs");
        Guid baseExercise = ExerciseCatalogSnapshot.Document.Entries[0].Id;
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 1, "createCustomExercise", "CustomExercise", ownerExercise, 0,
            new { exerciseId = ownerExercise, values = Values("Mine", "strength") }));
        await ProcessAsync(connectionString, other, Command(
            Guid.NewGuid(), otherClient, 1, "createExerciseCategory", "ExerciseCategory", foreignCategory, 0,
            new { categoryId = foreignCategory, name = "Theirs" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 2, "createExerciseCategory", "ExerciseCategory", ownerCategory, 0,
            new { categoryId = ownerCategory, name = "Mine" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 3, "createExerciseCategory", "ExerciseCategory", archivedCategory, 0,
            new { categoryId = archivedCategory, name = "Gone" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 4, "archiveExerciseCategory", "ExerciseCategory", archivedCategory, 1,
            new { categoryId = archivedCategory, baseVersion = 1 }));

        await AssertAssignmentRejectedAsync<BaseExerciseImmutableException>(connectionString, owner, baseExercise, baseCategory);
        await AssertAssignmentRejectedAsync<UserIsolationViolationException>(connectionString, owner, ownerExercise, foreignCategory);
        await AssertAssignmentRejectedAsync<UserIsolationViolationException>(connectionString, owner, ownerExercise, archivedCategory);
        await AssertAssignmentRejectedAsync<UserIsolationViolationException>(connectionString, owner, Guid.NewGuid(), ownerCategory);
        await AssertAssignmentRejectedAsync<UserIsolationViolationException>(connectionString, other, ownerExercise, ownerCategory);

        await using AppDbContext allowed = Fixture.CreateContext(connectionString, owner);
        allowed.ExerciseCategoryAssignments.Add(new ExerciseCategoryAssignment { ExerciseId = ownerExercise, CategoryId = ownerCategory });
        await allowed.SaveChangesAsync(TestContext.CancellationToken);
        Assert.AreEqual(1, await allowed.ExerciseCategoryAssignments.CountAsync(item => item.ExerciseId == ownerExercise, TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task ExerciseCatalogResponseContainsBaseAndOwnItemsOnlyForTheAuthenticatedUser()
    {
        (string connectionString, Guid owner, Guid other) = await CreateDatabaseAsync();
        Guid ownerClient = Guid.NewGuid();
        Guid otherClient = Guid.NewGuid();
        await RegisterActiveClientAsync(connectionString, owner, ownerClient);
        await RegisterActiveClientAsync(connectionString, other, otherClient);
        Guid ownerCategory = Guid.NewGuid();
        Guid otherCategory = Guid.NewGuid();
        Guid ownerExercise = Guid.NewGuid();
        Guid otherExercise = Guid.NewGuid();
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 1, "createExerciseCategory", "ExerciseCategory", ownerCategory, 0,
            new { categoryId = ownerCategory, name = "Owner category" }));
        await ProcessAsync(connectionString, owner, Command(
            Guid.NewGuid(), ownerClient, 2, "createCustomExercise", "CustomExercise", ownerExercise, 0,
            new { exerciseId = ownerExercise, values = Values("Owner Movement", "assisted", bodyweight: 0.5m, notes: "Band", categoryIds: [ownerCategory]) }));
        await ProcessAsync(connectionString, other, Command(
            Guid.NewGuid(), otherClient, 1, "createExerciseCategory", "ExerciseCategory", otherCategory, 0,
            new { categoryId = otherCategory, name = "Other category" }));
        await ProcessAsync(connectionString, other, Command(
            Guid.NewGuid(), otherClient, 2, "createCustomExercise", "CustomExercise", otherExercise, 0,
            new { exerciseId = otherExercise, values = Values("Other Movement", "strength", categoryIds: [otherCategory]) }));

        await using AppDbContext context = Fixture.CreateContext(connectionString, owner);
        var controller = new Gainer.Api.Controllers.ExerciseCatalogController(new ExerciseCatalogQueries(context, new TestUserContext(owner)));
        var result = (Microsoft.AspNetCore.Mvc.OkObjectResult)(await controller.Search(null, null, null, null, 0, 100, TestContext.CancellationToken)).Result!;
        var response = (Gainer.Contracts.Training.ExerciseCatalogResponse)result.Value!;

        Assert.IsFalse(response.Items.Any(item => item.Name == "Other Movement"));
        Gainer.Contracts.Training.ExerciseCatalogItemResponse mine = response.Items.Single(item => item.Name == "Owner Movement");
        Assert.AreEqual("assisted", mine.ExerciseType);
        Assert.AreEqual("Band", mine.Notes);
        Assert.AreEqual(0.5m, mine.BodyweightFactor);
        CollectionAssert.AreEqual(new[] { ownerCategory }, mine.CategoryIds.ToArray());
        Assert.IsTrue(response.Items.Any(item => !item.IsCustom && item.CategoryIds.Count > 0));
        Assert.IsTrue(response.Categories.Any(item => item.IsBase));
        Assert.IsTrue(response.Categories.Any(item => item.Id == ownerCategory && !item.IsBase));
        Assert.IsFalse(response.Categories.Any(item => item.Id == otherCategory));

        await using AppDbContext otherContext = Fixture.CreateContext(connectionString, other);
        var otherController = new Gainer.Api.Controllers.ExerciseCatalogController(new ExerciseCatalogQueries(otherContext, new TestUserContext(other)));
        var otherResult = (Microsoft.AspNetCore.Mvc.OkObjectResult)(await otherController.Search(null, null, null, null, 0, 100, TestContext.CancellationToken)).Result!;
        var otherResponse = (Gainer.Contracts.Training.ExerciseCatalogResponse)otherResult.Value!;
        Assert.IsFalse(otherResponse.Items.Any(item => item.Name == "Owner Movement"));
        Assert.IsFalse(otherResponse.Categories.Any(item => item.Id == ownerCategory));
    }

    private static async Task AssertAssignmentRejectedAsync<TException>(
        string connectionString,
        Guid userId,
        Guid exerciseId,
        Guid categoryId)
        where TException : Exception
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.ExerciseCategoryAssignments.Add(new ExerciseCategoryAssignment { ExerciseId = exerciseId, CategoryId = categoryId });
        await Assert.ThrowsAsync<TException>(() => context.SaveChangesAsync());
    }

    private static async Task<CustomExerciseValidationException> AssertRejectedAsync(
        string connectionString,
        Guid userId,
        Guid clientId,
        long sequence,
        Guid[] categoryIds)
    {
        Guid exerciseId = Guid.NewGuid();
        return await Assert.ThrowsAsync<CustomExerciseValidationException>(() => ProcessAsync(connectionString, userId, Command(
            Guid.NewGuid(), clientId, sequence, "createCustomExercise", "CustomExercise", exerciseId, 0,
            new { exerciseId, values = Values("Probe", "strength", categoryIds: categoryIds) })));
    }

    private static CustomExerciseValues Values(
        string name,
        string exerciseType,
        decimal? bodyweight = null,
        decimal? weight = null,
        string? notes = null,
        Guid[]? categoryIds = null) =>
        new(name, exerciseType, Notes: notes, BodyweightFactor: bodyweight, WeightFactor: weight, CategoryIds: categoryIds);

    private static async Task<ProcessedSyncMutationResult> ProcessAsync(
        string connectionString,
        Guid userId,
        ProcessSyncMutationCommand command)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        var user = new TestUserContext(userId);
        var processor = new SyncMutationProcessor(
            context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
        return await processor.ProcessAsync(command);
    }

    private static ProcessSyncMutationCommand Command(
        Guid mutationId,
        Guid clientId,
        long sequence,
        string operation,
        string resourceType,
        Guid resourceId,
        long baseVersion,
        object payload) =>
        new(
            mutationId,
            new CanonicalMutationContent(
                3,
                clientId,
                sequence,
                operation,
                [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                null,
                JsonSerializer.SerializeToElement(payload, JsonOptions)));

    private static async Task<(string ConnectionString, Guid FirstUser, Guid SecondUser)> CreateDatabaseAsync()
    {
        string connectionString = await Fixture.CreateIsolatedDatabaseAsync();
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
        await context.Database.MigrateAsync();
        context.Users.AddRange(User(first), User(second));
        await context.SaveChangesAsync();
        return (connectionString, first, second);
    }

    private static async Task RegisterActiveClientAsync(string connectionString, Guid userId, Guid clientId)
    {
        await using AppDbContext context = Fixture.CreateContext(connectionString, userId);
        context.SyncClients.Add(new SyncClient
        {
            Id = clientId,
            DisplayName = "Test browser",
            ProtocolVersion = 1,
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

    private sealed record TestUserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
