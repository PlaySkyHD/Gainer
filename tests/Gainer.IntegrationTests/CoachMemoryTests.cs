using System.Text.Json;
using Gainer.Api.Controllers;
using Gainer.Contracts.Coach;
using Gainer.Core.Coach;
using Gainer.Core.Insights;
using Gainer.Core.Security;
using Gainer.Core.Training;
using Gainer.Infrastructure.Coach;
using Gainer.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed class CoachMemoryTests
{
    public TestContext TestContext { get; set; } = null!;

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
    public async Task CrudRoundTripNormalizesTextAndListsNewestFirst()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        var time = new SteppingTimeProvider();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), time);
        CancellationToken token = TestContext.CancellationToken;

        CoachMemoryCreateResult first = await store.CreateAsync(CoachMemoryCategory.Goal, "  Halbmarathon\n im   Mai ", token);
        CoachMemoryCreateResult second = await store.CreateAsync(CoachMemoryCategory.Intolerance, "Laktoseintoleranz", token);

        Assert.IsTrue(first.Created);
        Assert.AreEqual("Halbmarathon im Mai", first.Item.Text);
        Assert.AreEqual(1, first.Item.Version);
        Assert.AreSequenceEqual(
            new[] { second.Item.Id, first.Item.Id }, (await store.ListAsync(token)).Select(item => item.Id).ToArray());

        CoachMemoryItem updated = await store.UpdateAsync(
            first.Item.Id, CoachMemoryCategory.Other, "Halbmarathon im Juni", first.Item.Version, token);
        Assert.AreEqual(CoachMemoryCategory.Other, updated.Category);
        Assert.AreEqual("Halbmarathon im Juni", updated.Text);
        Assert.AreEqual(2, updated.Version);
        Assert.IsGreaterThan(first.Item.UpdatedAtUtc, updated.UpdatedAtUtc);
        Assert.AreEqual(first.Item.CreatedAtUtc, updated.CreatedAtUtc);

        CoachMemoryItem unchanged = await store.UpdateAsync(
            first.Item.Id, CoachMemoryCategory.Other, "Halbmarathon im Juni", updated.Version, token);
        Assert.AreEqual(2, unchanged.Version);

        // Older app builds send no base version; their change is applied unchecked.
        CoachMemoryItem withoutBase = await store.UpdateAsync(
            first.Item.Id, CoachMemoryCategory.Goal, "Halbmarathon im Juni", cancellationToken: token);
        Assert.AreEqual(3, withoutBase.Version);

        Assert.IsTrue(await store.DeleteAsync(second.Item.Id, token));
        Assert.IsFalse(await store.DeleteAsync(second.Item.Id, token));
        Assert.HasCount(1, await store.ListAsync(token));
        Assert.AreEqual(1, await store.DeleteAllAsync(token));
        Assert.IsEmpty(await store.ListAsync(token));
    }

    [TestMethod]
    public async Task DuplicatesAreIdempotentOnCreateAndRejectedOnUpdate()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
        CancellationToken token = TestContext.CancellationToken;

        CoachMemoryCreateResult original = await store.CreateAsync(CoachMemoryCategory.Intolerance, "Laktoseintoleranz", token);
        CoachMemoryCreateResult again = await store.CreateAsync(CoachMemoryCategory.Intolerance, " LAKTOSEINTOLERANZ ", token);
        Assert.IsFalse(again.Created);
        Assert.AreEqual(original.Item.Id, again.Item.Id);
        Assert.AreEqual(original.Item, again.Item);
        Assert.HasCount(1, await store.ListAsync(token));

        CoachMemoryCreateResult other = await store.CreateAsync(CoachMemoryCategory.Preference, "Trainiert morgens", token);
        CoachMemoryException duplicate = await Assert.ThrowsAsync<CoachMemoryException>(() =>
            store.UpdateAsync(other.Item.Id, CoachMemoryCategory.Preference, "laktoseintoleranz", cancellationToken: token));
        Assert.AreEqual(CoachMemoryException.Duplicate, duplicate.Code);
    }

    [TestMethod]
    public async Task SameTextWithOtherCategoryUpdatesTheExistingEntryInPlace()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
        CancellationToken token = TestContext.CancellationToken;
        CoachMemoryCreateResult original = await store.CreateAsync(CoachMemoryCategory.Other, "Laktoseintoleranz", token);
        CoachMemoryCreateResult newer = await store.CreateAsync(CoachMemoryCategory.Preference, "Trainiert morgens", token);

        CoachMemoryCreateResult again = await store.CreateAsync(CoachMemoryCategory.Intolerance, "laktoseintoleranz", token);

        Assert.IsFalse(again.Created);
        Assert.AreEqual(original.Item.Id, again.Item.Id);
        Assert.AreEqual(CoachMemoryCategory.Intolerance, again.Item.Category);
        Assert.AreEqual("Laktoseintoleranz", again.Item.Text);
        Assert.AreEqual(2, again.Item.Version);
        Assert.IsGreaterThan(original.Item.UpdatedAtUtc, again.Item.UpdatedAtUtc);
        Assert.AreEqual(original.Item.CreatedAtUtc, again.Item.CreatedAtUtc);
        IReadOnlyList<CoachMemoryItem> list = await store.ListAsync(token);
        Assert.AreSequenceEqual(new[] { newer.Item.Id, original.Item.Id }, list.Select(item => item.Id).ToArray());
        Assert.AreEqual(CoachMemoryCategory.Intolerance, list[1].Category);

        await using AppDbContext verify = PostgreSqlTestFixture.CreateContext(connectionString, user);
        CoachMemory stored = await verify.CoachMemories.SingleAsync(item => item.Id == original.Item.Id, token);
        Assert.AreEqual(CoachMemoryCategory.Intolerance, stored.Category);
        Assert.AreEqual(2, stored.Version);
    }

    [TestMethod]
    public async Task ConcurrentUpdatesFromTheSameBaseVersionLetOnlyOneWin()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        CancellationToken token = TestContext.CancellationToken;
        CoachMemoryItem original;
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            original = (await new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider())
                .CreateAsync(CoachMemoryCategory.Goal, "Halbmarathon im Mai", token)).Item;
        }

        string[] texts = ["Halbmarathon im Juni", "Marathon im Oktober"];
        (string Text, CoachMemoryItem? Item, CoachMemoryException? Error)[] outcomes = await Task.WhenAll(texts.Select(async text =>
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
            var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
            try
            {
                return (text, (CoachMemoryItem?)await store.UpdateAsync(
                    original.Id, CoachMemoryCategory.Goal, text, original.Version, token), (CoachMemoryException?)null);
            }
            catch (CoachMemoryException exception)
            {
                return (text, null, exception);
            }
        }));

        var winner = outcomes.Single(item => item.Item is not null);
        var loser = outcomes.Single(item => item.Error is not null);
        Assert.AreEqual(CoachMemoryException.Conflict, loser.Error!.Code);
        Assert.AreEqual(2, winner.Item!.Version);
        await using AppDbContext verify = PostgreSqlTestFixture.CreateContext(connectionString, user);
        CoachMemory stored = await verify.CoachMemories.SingleAsync(token);
        Assert.AreEqual(winner.Text, stored.Text);
        Assert.AreEqual(2, stored.Version);

        var controller = new CoachMemoriesController(
            new CoachMemoryStore(verify, new TestUserContext(user), new SteppingTimeProvider()));
        AssertProblem(
            (await controller.Update(original.Id, new CoachMemoryUpdateRequest("goal", loser.Text, original.Version), token)).Result,
            409,
            CoachMemoryException.Conflict);
        ActionResult<CoachMemoryResponse> retried = await controller.Update(
            original.Id, new CoachMemoryUpdateRequest("goal", loser.Text, stored.Version), token);
        Assert.AreEqual(3, ((CoachMemoryResponse)((OkObjectResult)retried.Result!).Value!).Version);
    }

    [TestMethod]
    public async Task InvalidTextAndUnknownCategoryAreRejected()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
        CancellationToken token = TestContext.CancellationToken;

        foreach (string text in new[] { "", "   \n ", new string('a', 201) })
        {
            CoachMemoryException invalid = await Assert.ThrowsAsync<CoachMemoryException>(() =>
                store.CreateAsync(CoachMemoryCategory.Goal, text, token));
            Assert.AreEqual(CoachMemoryException.Invalid, invalid.Code);
        }
        CoachMemoryException category = await Assert.ThrowsAsync<CoachMemoryException>(() =>
            store.CreateAsync((CoachMemoryCategory)99, "Text", token));
        Assert.AreEqual(CoachMemoryException.Invalid, category.Code);
        Assert.AreEqual(200, (await store.CreateAsync(CoachMemoryCategory.Goal, new string('a', 200), token)).Item.Text.Length);
    }

    [TestMethod]
    public async Task LimitOfFiftyHoldsAlsoForParallelCreates()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        CancellationToken token = TestContext.CancellationToken;
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user))
        {
            var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
            for (int index = 0; index < 45; index++)
                await store.CreateAsync(CoachMemoryCategory.Other, $"Notiz {index}", token);
        }

        CoachMemoryException?[] outcomes = await Task.WhenAll(Enumerable.Range(0, 10).Select(async index =>
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
            var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
            try
            {
                await store.CreateAsync(CoachMemoryCategory.Other, $"Parallel {index}", token);
                return null;
            }
            catch (CoachMemoryException exception)
            {
                return exception;
            }
        }));

        Assert.AreEqual(5, outcomes.Count(item => item is null));
        Assert.IsTrue(outcomes.Where(item => item is not null).All(item => item!.Code == CoachMemoryException.LimitReached));
        await using AppDbContext verify = PostgreSqlTestFixture.CreateContext(connectionString, user);
        Assert.AreEqual(CoachMemoryRules.MaxEntriesPerUser, await verify.CoachMemories.CountAsync(token));
    }

    [TestMethod]
    public async Task ControllerMapsResultsToStableStatusCodes()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, user);
        var controller = new CoachMemoriesController(
            new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider()));
        CancellationToken token = TestContext.CancellationToken;

        ActionResult<CoachMemoryResponse> created = await controller.Create(new CoachMemoryRequest("goal", "Halbmarathon im Mai"), token);
        var createdResult = (ObjectResult)created.Result!;
        Assert.AreEqual(StatusCodes.Status201Created, createdResult.StatusCode);
        var memory = (CoachMemoryResponse)createdResult.Value!;
        Assert.AreEqual("goal", memory.Category);

        ActionResult<CoachMemoryResponse> repeated = await controller.Create(new CoachMemoryRequest("goal", "halbmarathon im mai"), token);
        Assert.AreEqual(memory.Id, ((CoachMemoryResponse)((OkObjectResult)repeated.Result!).Value!).Id);
        ActionResult<CoachMemoryResponse> recategorized = await controller.Create(new CoachMemoryRequest("other", "Halbmarathon im Mai"), token);
        var recategorizedMemory = (CoachMemoryResponse)((OkObjectResult)recategorized.Result!).Value!;
        Assert.AreEqual(memory.Id, recategorizedMemory.Id);
        Assert.AreEqual("other", recategorizedMemory.Category);
        Assert.AreEqual(2, recategorizedMemory.Version);

        AssertProblem((await controller.Create(new CoachMemoryRequest("diagnosis", "x"), token)).Result, 400, CoachMemoryException.Invalid);
        AssertProblem((await controller.Update(memory.Id, new CoachMemoryUpdateRequest("goal", " "), token)).Result, 400, CoachMemoryException.Invalid);

        ActionResult<CoachMemoryResponse> updated = await controller.Update(memory.Id, new CoachMemoryUpdateRequest("injury", "Knie schonen", 2), token);
        Assert.AreEqual("injury", ((CoachMemoryResponse)((OkObjectResult)updated.Result!).Value!).Category);

        var list = (CoachMemoryListResponse)((OkObjectResult)(await controller.List(token)).Result!).Value!;
        Assert.AreEqual(CoachMemoryRules.MaxEntriesPerUser, list.MaxEntries);
        Assert.AreEqual("Knie schonen", list.Items.Single().Text);

        for (int index = 1; index < CoachMemoryRules.MaxEntriesPerUser; index++)
            await controller.Create(new CoachMemoryRequest("other", $"Notiz {index}"), token);
        AssertProblem((await controller.Create(new CoachMemoryRequest("other", "Eine zu viel"), token)).Result, 409, CoachMemoryException.LimitReached);

        Assert.IsInstanceOfType<NoContentResult>(await controller.Delete(memory.Id, token));
        AssertProblem(await controller.Delete(memory.Id, token), 404, CoachMemoryException.NotFound);
        Assert.IsInstanceOfType<NoContentResult>(await controller.DeleteAll(token));
        Assert.IsEmpty(((CoachMemoryListResponse)((OkObjectResult)(await controller.List(token)).Result!).Value!).Items);
    }

    [TestMethod]
    public async Task ForeignEntriesAreInvisibleAndAnswerLikeUnknownIds()
    {
        (string connectionString, Guid owner, Guid stranger) = await CreateDatabaseAsync();
        CancellationToken token = TestContext.CancellationToken;
        Guid ownerEntry;
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, owner))
        {
            var store = new CoachMemoryStore(context, new TestUserContext(owner), new SteppingTimeProvider());
            ownerEntry = (await store.CreateAsync(CoachMemoryCategory.Injury, "owner-private", token)).Item.Id;
        }

        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, stranger))
        {
            var controller = new CoachMemoriesController(
                new CoachMemoryStore(context, new TestUserContext(stranger), new SteppingTimeProvider()));
            await controller.Create(new CoachMemoryRequest("goal", "stranger-private"), token);

            var list = (CoachMemoryListResponse)((OkObjectResult)(await controller.List(token)).Result!).Value!;
            Assert.AreEqual("stranger-private", list.Items.Single().Text);

            string foreignUpdate = ProblemJson((await controller.Update(ownerEntry, new CoachMemoryUpdateRequest("goal", "overwrite", 1), token)).Result);
            string unknownUpdate = ProblemJson((await controller.Update(Guid.NewGuid(), new CoachMemoryUpdateRequest("goal", "overwrite", 1), token)).Result);
            Assert.AreEqual(unknownUpdate, foreignUpdate);
            Assert.Contains(CoachMemoryException.NotFound, foreignUpdate);

            Assert.AreEqual(ProblemJson(await controller.Delete(Guid.NewGuid(), token)), ProblemJson(await controller.Delete(ownerEntry, token)));
            Assert.IsInstanceOfType<NoContentResult>(await controller.DeleteAll(token));
        }

        await using AppDbContext verify = PostgreSqlTestFixture.CreateContext(connectionString, owner);
        CoachMemory kept = await verify.CoachMemories.SingleAsync(token);
        Assert.AreEqual(ownerEntry, kept.Id);
        Assert.AreEqual("owner-private", kept.Text);
        Assert.AreEqual(1, kept.Version);
    }

    [TestMethod]
    public async Task AnonymousAccessIsRejected()
    {
        (string connectionString, _, _) = await CreateDatabaseAsync();
        await using AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString);
        var store = new CoachMemoryStore(context, new TestUserContext(null), new SteppingTimeProvider());
        await Assert.ThrowsAsync<UserIsolationViolationException>(() => store.ListAsync(TestContext.CancellationToken));
        await Assert.ThrowsAsync<UserIsolationViolationException>(() =>
            store.CreateAsync(CoachMemoryCategory.Goal, "x", TestContext.CancellationToken));
        await Assert.ThrowsAsync<UserIsolationViolationException>(() => store.DeleteAllAsync(TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CoachReadsOnlyTheCurrentUsersNotesFromTheDatabase()
    {
        (string connectionString, Guid owner, Guid stranger) = await CreateDatabaseAsync();
        CancellationToken token = TestContext.CancellationToken;
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, owner))
            await new CoachMemoryStore(context, new TestUserContext(owner), new SteppingTimeProvider())
                .CreateAsync(CoachMemoryCategory.Goal, "owner-note", token);
        await using (AppDbContext context = PostgreSqlTestFixture.CreateContext(connectionString, stranger))
            await new CoachMemoryStore(context, new TestUserContext(stranger), new SteppingTimeProvider())
                .CreateAsync(CoachMemoryCategory.Goal, "stranger-note", token);

        await using AppDbContext ownerContext = PostgreSqlTestFixture.CreateContext(connectionString, owner);
        var provider = new RecordingProvider();
        var coach = new CoachService(
            provider,
            new InsightQueries(ownerContext, new TestUserContext(owner)),
            new NoHistory(),
            new NoExercises(),
            new CoachMemoryStore(ownerContext, new TestUserContext(owner), TimeProvider.System),
            new PassCoachQuota(),
            new TestUserContext(owner),
            TimeProvider.System);

        await coach.AnswerAsync("Wie läuft es?", token);

        string request = provider.Request!.Value.GetRawText();
        Assert.Contains("owner-note", request);
        Assert.DoesNotContain("stranger-note", request);
    }

    [TestMethod]
    public void EndpointRequiresAuthentication()
    {
        Assert.IsNotNull(typeof(CoachMemoriesController).GetCustomAttributes(typeof(AuthorizeAttribute), inherit: true).SingleOrDefault());
        Assert.IsTrue(typeof(CoachMemoriesController).IsSealed);
        foreach (var method in typeof(CoachMemoriesController).GetMethods().Where(method => method.DeclaringType == typeof(CoachMemoriesController)))
        {
            Assert.DoesNotContain(
                parameter => parameter.Name is "userId" or "ownerId", method.GetParameters(),
                $"{method.Name} must not accept a user id.");
        }
    }

    private static void AssertProblem(IActionResult? result, int status, string code)
    {
        var problem = (ObjectResult)result!;
        Assert.AreEqual(status, problem.StatusCode);
        Assert.AreEqual(code, ((ProblemDetails)problem.Value!).Extensions["code"]);
    }

    private static void AssertProblem(ActionResult? result, int status, string code) => AssertProblem((IActionResult?)result, status, code);

    private static string ProblemJson(IActionResult? result)
    {
        var problem = (ObjectResult)result!;
        return $"{problem.StatusCode}:{JsonSerializer.Serialize(problem.Value)}";
    }

    private static string ProblemJson(ActionResult? result) => ProblemJson((IActionResult?)result);

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
        EmailConfirmed = true,
        IsActive = true,
        SecurityStamp = Guid.NewGuid().ToString("N"),
        ConcurrencyStamp = Guid.NewGuid().ToString("N"),
    };

    private sealed record TestUserContext(Guid? UserId) : IUserContext;

    /// <summary>Each read moves one second forward, so creation order is unambiguous.</summary>
    private sealed class SteppingTimeProvider : TimeProvider
    {
        private DateTimeOffset now = new(2026, 10, 24, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => now = now.AddSeconds(1);
    }

    private sealed class RecordingProvider : IOpenAiResponsesProvider
    {
        public JsonElement? Request { get; private set; }

        public Task<JsonElement> CreateResponseAsync(JsonElement request, CancellationToken cancellationToken = default)
        {
            Request = request.Clone();
            return Task.FromResult(JsonSerializer.SerializeToElement(new
            {
                output = new[]
                {
                    new
                    {
                        type = "message",
                        content = new[]
                        {
                            new
                            {
                                type = "output_text",
                                text = """{"summary":"Gut.","observations":[],"dataGaps":[],"suggestions":[],"memorySuggestions":[]}""",
                            },
                        },
                    },
                },
            }));
        }
    }

    private sealed class NoHistory : IWorkoutHistoryQueries
    {
        public Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<WorkoutHistorySummary>>([]);
        public Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default) =>
            Task.FromResult<WorkoutSnapshot?>(null);
    }

    private sealed class NoExercises : IExerciseResolver
    {
        public Task<ExerciseCatalogItem?> ResolveAsync(Guid exerciseId, bool includeArchived, CancellationToken cancellationToken = default) =>
            Task.FromResult<ExerciseCatalogItem?>(null);
    }
}
