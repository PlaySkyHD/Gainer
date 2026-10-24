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
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), time);
        CancellationToken token = TestContext.CancellationToken;

        CoachMemoryCreateResult first = await store.CreateAsync(CoachMemoryCategory.Goal, "  Halbmarathon\n im   Mai ", token);
        CoachMemoryCreateResult second = await store.CreateAsync(CoachMemoryCategory.Intolerance, "Laktoseintoleranz", token);

        Assert.IsTrue(first.Created);
        Assert.AreEqual("Halbmarathon im Mai", first.Item.Text);
        Assert.AreEqual(1, first.Item.Version);
        CollectionAssert.AreEqual(
            new[] { second.Item.Id, first.Item.Id },
            (await store.ListAsync(token)).Select(item => item.Id).ToArray());

        CoachMemoryItem updated = await store.UpdateAsync(first.Item.Id, CoachMemoryCategory.Other, "Halbmarathon im Juni", token);
        Assert.AreEqual(CoachMemoryCategory.Other, updated.Category);
        Assert.AreEqual("Halbmarathon im Juni", updated.Text);
        Assert.AreEqual(2, updated.Version);
        Assert.IsGreaterThan(first.Item.UpdatedAtUtc, updated.UpdatedAtUtc);
        Assert.AreEqual(first.Item.CreatedAtUtc, updated.CreatedAtUtc);

        CoachMemoryItem unchanged = await store.UpdateAsync(first.Item.Id, CoachMemoryCategory.Other, "Halbmarathon im Juni", token);
        Assert.AreEqual(2, unchanged.Version);

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
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
        var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
        CancellationToken token = TestContext.CancellationToken;

        CoachMemoryCreateResult original = await store.CreateAsync(CoachMemoryCategory.Intolerance, "Laktoseintoleranz", token);
        CoachMemoryCreateResult again = await store.CreateAsync(CoachMemoryCategory.Other, " LAKTOSEINTOLERANZ ", token);
        Assert.IsFalse(again.Created);
        Assert.AreEqual(original.Item.Id, again.Item.Id);
        Assert.HasCount(1, await store.ListAsync(token));

        CoachMemoryCreateResult other = await store.CreateAsync(CoachMemoryCategory.Preference, "Trainiert morgens", token);
        CoachMemoryException duplicate = await Assert.ThrowsAsync<CoachMemoryException>(() =>
            store.UpdateAsync(other.Item.Id, CoachMemoryCategory.Preference, "laktoseintoleranz", token));
        Assert.AreEqual(CoachMemoryException.Duplicate, duplicate.Code);
    }

    [TestMethod]
    public async Task InvalidTextAndUnknownCategoryAreRejected()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
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
        await using (AppDbContext context = Fixture.CreateContext(connectionString, user))
        {
            var store = new CoachMemoryStore(context, new TestUserContext(user), new SteppingTimeProvider());
            for (int index = 0; index < 45; index++)
                await store.CreateAsync(CoachMemoryCategory.Other, $"Notiz {index}", token);
        }

        CoachMemoryException?[] outcomes = await Task.WhenAll(Enumerable.Range(0, 10).Select(async index =>
        {
            await using AppDbContext context = Fixture.CreateContext(connectionString, user);
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
        await using AppDbContext verify = Fixture.CreateContext(connectionString, user);
        Assert.AreEqual(CoachMemoryRules.MaxEntriesPerUser, await verify.CoachMemories.CountAsync(token));
    }

    [TestMethod]
    public async Task ControllerMapsResultsToStableStatusCodes()
    {
        (string connectionString, Guid user, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString, user);
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

        AssertProblem((await controller.Create(new CoachMemoryRequest("diagnosis", "x"), token)).Result, 400, CoachMemoryException.Invalid);
        AssertProblem((await controller.Update(memory.Id, new CoachMemoryRequest("goal", " "), token)).Result, 400, CoachMemoryException.Invalid);

        ActionResult<CoachMemoryResponse> updated = await controller.Update(memory.Id, new CoachMemoryRequest("injury", "Knie schonen"), token);
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
        await using (AppDbContext context = Fixture.CreateContext(connectionString, owner))
        {
            var store = new CoachMemoryStore(context, new TestUserContext(owner), new SteppingTimeProvider());
            ownerEntry = (await store.CreateAsync(CoachMemoryCategory.Injury, "owner-private", token)).Item.Id;
        }

        await using (AppDbContext context = Fixture.CreateContext(connectionString, stranger))
        {
            var controller = new CoachMemoriesController(
                new CoachMemoryStore(context, new TestUserContext(stranger), new SteppingTimeProvider()));
            await controller.Create(new CoachMemoryRequest("goal", "stranger-private"), token);

            var list = (CoachMemoryListResponse)((OkObjectResult)(await controller.List(token)).Result!).Value!;
            Assert.AreEqual("stranger-private", list.Items.Single().Text);

            string foreignUpdate = ProblemJson((await controller.Update(ownerEntry, new CoachMemoryRequest("goal", "overwrite"), token)).Result);
            string unknownUpdate = ProblemJson((await controller.Update(Guid.NewGuid(), new CoachMemoryRequest("goal", "overwrite"), token)).Result);
            Assert.AreEqual(unknownUpdate, foreignUpdate);
            Assert.Contains(CoachMemoryException.NotFound, foreignUpdate);

            Assert.AreEqual(ProblemJson(await controller.Delete(Guid.NewGuid(), token)), ProblemJson(await controller.Delete(ownerEntry, token)));
            Assert.IsInstanceOfType<NoContentResult>(await controller.DeleteAll(token));
        }

        await using AppDbContext verify = Fixture.CreateContext(connectionString, owner);
        CoachMemory kept = await verify.CoachMemories.SingleAsync(token);
        Assert.AreEqual(ownerEntry, kept.Id);
        Assert.AreEqual("owner-private", kept.Text);
        Assert.AreEqual(1, kept.Version);
    }

    [TestMethod]
    public async Task AnonymousAccessIsRejected()
    {
        (string connectionString, _, _) = await CreateDatabaseAsync();
        await using AppDbContext context = Fixture.CreateContext(connectionString);
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
        await using (AppDbContext context = Fixture.CreateContext(connectionString, owner))
            await new CoachMemoryStore(context, new TestUserContext(owner), new SteppingTimeProvider())
                .CreateAsync(CoachMemoryCategory.Goal, "owner-note", token);
        await using (AppDbContext context = Fixture.CreateContext(connectionString, stranger))
            await new CoachMemoryStore(context, new TestUserContext(stranger), new SteppingTimeProvider())
                .CreateAsync(CoachMemoryCategory.Goal, "stranger-note", token);

        await using AppDbContext ownerContext = Fixture.CreateContext(connectionString, owner);
        var provider = new RecordingProvider();
        var coach = new CoachService(
            provider,
            new InsightQueries(ownerContext, new TestUserContext(owner)),
            new NoHistory(),
            new NoExercises(),
            new CoachMemoryStore(ownerContext, new TestUserContext(owner), TimeProvider.System),
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
            Assert.IsFalse(
                method.GetParameters().Any(parameter => parameter.Name is "userId" or "ownerId"),
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
        await using AppDbContext context = Fixture.CreateContext(connectionString);
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

    private sealed class NoExercises : IExerciseCatalogQueries
    {
        public Task<ExerciseCatalogPage> SearchAsync(ExerciseCatalogFilter filter, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseCatalogPage([], 0, filter.Limit, 0, []));
    }
}
