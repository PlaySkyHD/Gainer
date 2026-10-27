using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Gainer.IntegrationTests;

[TestClass]
[DoNotParallelize]
public sealed partial class ExerciseCatalogIsolationMatrixTests
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
        if (fixture is not null) await fixture.DisposeAsync();
    }

    [TestMethod]
    public async Task CustomExercisesCoverEveryRequiredOperationAgainstTwoIndependentActors()
    {
        var scenario = await CustomExerciseScenario.CreateScenarioAsync();
        await TwoUserApiIsolationMatrix.VerifyAsync(scenario);
    }

    [TestMethod]
    public async Task ExerciseCategoriesCoverEveryRequiredOperationAgainstTwoIndependentActors()
    {
        var scenario = await ExerciseCategoryScenario.CreateScenarioAsync();
        await TwoUserApiIsolationMatrix.VerifyAsync(scenario);
    }

    private abstract partial class ScenarioBase(string connectionString, Guid first, Guid second)
    {
        private readonly Dictionary<Guid, long> sequences = [];

        protected string ConnectionString { get; } = connectionString;

        protected Guid FirstClient { get; } = Guid.NewGuid();

        protected Guid SecondClient { get; } = Guid.NewGuid();

        public Guid FirstUser { get; } = first;

        public Guid SecondUser { get; } = second;

        public System.Text.RegularExpressions.Regex FirstUserSecretPattern { get; } = FirstUserSecretRegex();

        public System.Text.RegularExpressions.Regex SecondUserSecretPattern { get; } = SecondUserSecretRegex();

        [GeneratedRegex("first-(user|private)", RegexOptions.IgnoreCase)]
        private static partial System.Text.RegularExpressions.Regex FirstUserSecretRegex();

        [GeneratedRegex("second-(user|private)", RegexOptions.IgnoreCase)]
        private static partial System.Text.RegularExpressions.Regex SecondUserSecretRegex();

        protected static async Task<(string ConnectionString, Guid First, Guid Second)> CreateDatabaseAsync()
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

        protected async Task RegisterClientsAsync()
        {
            await RegisterAsync(FirstUser, FirstClient);
            await RegisterAsync(SecondUser, SecondClient);
        }

        protected async Task ProcessAsync(Guid actor, string operation, string resourceType, Guid resourceId, long baseVersion, object payload)
        {
            Guid clientId = actor == FirstUser ? FirstClient : SecondClient;
            long sequence = sequences.GetValueOrDefault(actor) + 1;
            sequences[actor] = sequence;
            var command = new ProcessSyncMutationCommand(
                Guid.NewGuid(),
                new CanonicalMutationContent(
                    3,
                    clientId,
                    sequence,
                    operation,
                    [new CanonicalResourceVersion(resourceType, resourceId, baseVersion)],
                    null,
                    JsonSerializer.SerializeToElement(payload, JsonOptions)));
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString, actor);
            var user = new TestUserContext(actor);
            var processor = new SyncMutationProcessor(
                context, user, new SyncMutationExecutor(context, user, TimeProvider.System), TimeProvider.System);
            await processor.ProcessAsync(command);
        }

        /// <summary>Unknown ids fall back to version 1 so the request reaches the not-found path instead of failing validation.</summary>
        protected async Task<long> VersionAsync(string table, Guid id)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString);
            long version = table == "exercise"
                ? await context.Exercises.IgnoreQueryFilters().Where(item => item.Id == id).Select(item => item.Version).FirstOrDefaultAsync()
                : await context.ExerciseCategories.IgnoreQueryFilters().Where(item => item.Id == id).Select(item => item.Version).FirstOrDefaultAsync();
            return Math.Max(1, version);
        }

        protected static IsolationApiResponse Success(string representation) =>
            new(HttpStatusCode.OK, string.Empty, representation);

        protected static IsolationApiResponse NotFound() =>
            new(HttpStatusCode.NotFound, "resource-not-found", "{\"code\":\"resource-not-found\"}");

        protected static bool Conflicts(Exception exception) => exception is SyncMutationConflictException;

        private async Task RegisterAsync(Guid userId, Guid clientId)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString, userId);
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

        protected static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

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
    }

    private sealed class CustomExerciseScenario(string connectionString, Guid first, Guid second)
        : ScenarioBase(connectionString, first, second), ITwoUserApiIsolationScenario<Guid>
    {
        public static async Task<CustomExerciseScenario> CreateScenarioAsync()
        {
            (string connectionString, Guid first, Guid second) = await CreateDatabaseAsync();
            var scenario = new CustomExerciseScenario(connectionString, first, second);
            await scenario.RegisterClientsAsync();
            return scenario;
        }

        public async Task<Guid> CreateAsync(Guid actor, string privateMarker)
        {
            Guid id = Guid.NewGuid();
            await ProcessAsync(actor, "createCustomExercise", "CustomExercise", id, 0,
                new { exerciseId = id, values = new CustomExerciseValues(privateMarker, "strength") });
            return id;
        }

        public async Task<IReadOnlyList<Guid>> ListIdsAsync(Guid actor, int offset, int limit)
        {
            List<Guid> owned = (await OwnedAsync(actor)).Select(item => item.Id).ToList();
            return owned.Skip(offset).Take(limit).ToArray();
        }

        public async Task<int> CountAsync(Guid actor) => (await OwnedAsync(actor)).Count;

        public async Task<IsolationApiResponse> DetailAsync(Guid actor, Guid id)
        {
            ExerciseCatalogItem? item = await ResolveAsync(actor, id);
            return item is { IsCustom: true }
                ? Success($"{{\"name\":\"{item.Name}\"}}")
                : NotFound();
        }

        public async Task<IsolationApiResponse> UpdateAsync(Guid actor, Guid id, string privateMarker)
        {
            try
            {
                long version = await VersionAsync("exercise", id);
                await ProcessAsync(actor, "updateCustomExercise", "CustomExercise", id, version,
                    new { exerciseId = id, baseVersion = version, values = new CustomExerciseValues(privateMarker, "strength") });
            }
            catch (Exception exception) when (Conflicts(exception))
            {
                return NotFound();
            }
            return Success($"{{\"name\":\"{privateMarker}\"}}");
        }

        public async Task<IsolationApiResponse> DeleteAsync(Guid actor, Guid id)
        {
            try
            {
                long version = await VersionAsync("exercise", id);
                await ProcessAsync(actor, "archiveCustomExercise", "CustomExercise", id, version,
                    new { exerciseId = id, baseVersion = version });
            }
            catch (Exception exception) when (Conflicts(exception))
            {
                return NotFound();
            }
            return new IsolationApiResponse(HttpStatusCode.NoContent, string.Empty, string.Empty);
        }

        private async Task<ExerciseCatalogItem?> ResolveAsync(Guid actor, Guid id)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString, actor);
            return await new ExerciseCatalogQueries(context, new TestUserContext(actor)).ResolveAsync(id, includeArchived: false);
        }

        private async Task<List<ExerciseCatalogItem>> OwnedAsync(Guid actor)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString, actor);
            var queries = new ExerciseCatalogQueries(context, new TestUserContext(actor));
            var owned = new List<ExerciseCatalogItem>();
            for (int offset = 0; ; offset += 100)
            {
                ExerciseCatalogPage page = await queries.SearchAsync(new ExerciseCatalogFilter(Offset: offset, Limit: 100));
                owned.AddRange(page.Items.Where(item => item.IsCustom));
                if (offset + page.Items.Count >= page.Total) break;
            }
            return owned.OrderBy(item => item.Id).ToList();
        }
    }

    private sealed class ExerciseCategoryScenario(string connectionString, Guid first, Guid second)
        : ScenarioBase(connectionString, first, second), ITwoUserApiIsolationScenario<Guid>
    {
        public static async Task<ExerciseCategoryScenario> CreateScenarioAsync()
        {
            (string connectionString, Guid first, Guid second) = await CreateDatabaseAsync();
            var scenario = new ExerciseCategoryScenario(connectionString, first, second);
            await scenario.RegisterClientsAsync();
            return scenario;
        }

        public async Task<Guid> CreateAsync(Guid actor, string privateMarker)
        {
            Guid id = Guid.NewGuid();
            await ProcessAsync(actor, "createExerciseCategory", "ExerciseCategory", id, 0,
                new { categoryId = id, name = privateMarker });
            return id;
        }

        public async Task<IReadOnlyList<Guid>> ListIdsAsync(Guid actor, int offset, int limit)
        {
            List<Guid> owned = (await OwnedAsync(actor)).Select(item => item.Id).ToList();
            return owned.Skip(offset).Take(limit).ToArray();
        }

        public async Task<int> CountAsync(Guid actor) => (await OwnedAsync(actor)).Count;

        public async Task<IsolationApiResponse> DetailAsync(Guid actor, Guid id)
        {
            ExerciseCategoryItem? item = (await OwnedAsync(actor)).SingleOrDefault(category => category.Id == id);
            return item is null ? NotFound() : Success($"{{\"name\":\"{item.Name}\"}}");
        }

        public async Task<IsolationApiResponse> UpdateAsync(Guid actor, Guid id, string privateMarker)
        {
            try
            {
                long version = await VersionAsync("category", id);
                await ProcessAsync(actor, "updateExerciseCategory", "ExerciseCategory", id, version,
                    new { categoryId = id, baseVersion = version, name = privateMarker });
            }
            catch (Exception exception) when (Conflicts(exception))
            {
                return NotFound();
            }
            return Success($"{{\"name\":\"{privateMarker}\"}}");
        }

        public async Task<IsolationApiResponse> DeleteAsync(Guid actor, Guid id)
        {
            try
            {
                long version = await VersionAsync("category", id);
                await ProcessAsync(actor, "archiveExerciseCategory", "ExerciseCategory", id, version,
                    new { categoryId = id, baseVersion = version });
            }
            catch (Exception exception) when (Conflicts(exception))
            {
                return NotFound();
            }
            return new IsolationApiResponse(HttpStatusCode.NoContent, string.Empty, string.Empty);
        }

        private async Task<List<ExerciseCategoryItem>> OwnedAsync(Guid actor)
        {
            await using AppDbContext context = PostgreSqlTestFixture.CreateContext(ConnectionString, actor);
            ExerciseCatalogPage page = await new ExerciseCatalogQueries(context, new TestUserContext(actor))
                .SearchAsync(new ExerciseCatalogFilter(Limit: 1));
            return page.Categories.Where(item => !item.IsBase).OrderBy(item => item.Id).ToList();
        }
    }

    private sealed record TestUserContext(Guid Value) : IUserContext
    {
        Guid? IUserContext.UserId => Value;
    }
}
