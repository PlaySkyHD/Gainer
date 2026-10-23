using System.Text.Json;
using Gainer.Core.BodyTracking;
using Gainer.Core.Coach;
using Gainer.Core.Insights;
using Gainer.Core.Training;
using Gainer.Infrastructure.Coach;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class CoachServiceTests
{
    [TestMethod]
    public async Task ToolLoopUsesBackendFactAndAcceptsOnlyKnownFactReference()
    {
        var provider = new FakeProvider(
            Response(FunctionCall("call_1", "get_weight_summary", "{\"days\":30}")),
            Response(Message("""
                {"summary":"Der Verlauf ist messbar.","observations":[{"text":"Das Mittel liegt bei 80 kg.","factIds":["rev:5:weight.avg.30"]}],"dataGaps":[],"suggestions":["Beobachte den Verlauf weiter."]}
                """)));
        CoachAnswer answer = await Service(provider).AnswerAsync("Wie entwickelt sich mein Gewicht?");
        Assert.HasCount(2, provider.Requests);
        Assert.HasCount(2, answer.Facts);
        Assert.AreEqual(80m, answer.Facts.Single(item => item.FactId == "rev:5:weight.avg.30").NumericValue);
        Assert.AreEqual("rev:5:weight.avg.30", answer.Observations[0].FactIds[0]);
        Assert.Contains("function_call_output", provider.Requests[1].GetRawText());
    }

    [TestMethod]
    public async Task UnknownToolsManipulatedExerciseIdsAndRoundOverflowFailClosed()
    {
        await Assert.ThrowsAsync<CoachResponseValidationException>(() => Service(new FakeProvider(
            Response(FunctionCall("bad", "run_sql", "{}")))).AnswerAsync("Analysiere mich"));
        await Assert.ThrowsAsync<CoachResponseValidationException>(() => Service(new FakeProvider(
            Response(FunctionCall("bad", "get_exercise_progress", $"{{\"exerciseId\":\"{Guid.NewGuid()}\",\"days\":30}}"))))
            .AnswerAsync("Analysiere die Übung"));
        await Assert.ThrowsAsync<CoachResponseValidationException>(() => Service(new FakeProvider(
            Response(FunctionCall("1", "get_weight_summary", "{\"days\":30}")),
            Response(FunctionCall("2", "get_weight_summary", "{\"days\":30}")),
            Response(FunctionCall("3", "get_weight_summary", "{\"days\":30}"))))
            .AnswerAsync("Analysiere mich"));
    }

    [TestMethod]
    public async Task HallucinatedFactsAndNumericPrescriptionsFailWhileMedicalQuestionAvoidsProvider()
    {
        await Assert.ThrowsAsync<CoachResponseValidationException>(() => Service(new FakeProvider(
            Response(Message("""
                {"summary":"Test","observations":[{"text":"Gewicht 99 kg","factIds":["invented"]}],"dataGaps":[],"suggestions":[]}
                """)))).AnswerAsync("Fortschritt?"));
        await Assert.ThrowsAsync<CoachResponseValidationException>(() => Service(new FakeProvider(
            Response(Message("""
                {"summary":"Test","observations":[],"dataGaps":[],"suggestions":["Iss 2200 kcal."]}
                """)))).AnswerAsync("Fortschritt?"));
        var provider = new FakeProvider();
        CoachAnswer medical = await Service(provider).AnswerAsync("Diagnostiziere meine Knieschmerzen");
        Assert.HasCount(0, provider.Requests);
        Assert.Contains("keine medizinische Diagnose", medical.Summary);
    }

    [TestMethod]
    public async Task DataScarcityIsReportedWithoutInventingFacts()
    {
        var provider = new FakeProvider(
            Response(FunctionCall("call_1", "get_weight_summary", "{\"days\":30}")),
            Response(Message("""
                {"summary":"Noch keine belastbare Auswertung möglich.","observations":[],"dataGaps":["Es fehlen Gewichtsmessungen."],"suggestions":["Erfasse zunächst regelmäßig Daten."]}
                """)));
        CoachAnswer answer = await new CoachService(
            provider, new NoDataInsights(), new FakeHistory(), new FakeExercises(), new FixedTimeProvider())
            .AnswerAsync("Wie entwickelt sich mein Gewicht?");

        Assert.IsEmpty(answer.Facts);
        Assert.IsEmpty(answer.Observations);
        Assert.HasCount(1, answer.DataGaps);
        Assert.AreEqual(5, answer.AsOfRevision);
    }

    [TestMethod]
    public async Task NutritionToolExposesTraceableProjectionSources()
    {
        var provider = new FakeProvider(
            Response(FunctionCall("call_1", "get_nutrition_summary", "{\"days\":30}")),
            Response(Message("""
                {"summary":"ErnÃ¤hrungsdaten vorhanden.","observations":[],"dataGaps":[],"suggestions":[]}
                """)));
        CoachAnswer answer = await new CoachService(
            provider, new NutritionInsightsStub(), new FakeHistory(), new FakeExercises(), new FixedTimeProvider())
            .AnswerAsync("Wie sieht meine ErnÃ¤hrung aus?");

        Assert.IsTrue(answer.Facts.Any(item => item.TextValue == NutritionSources.MealDiary));
        Assert.IsTrue(answer.Facts.Any(item => item.TextValue == NutritionSources.LegacyCheckIn));
        CoachFact fiber = answer.Facts.Single(item => item.Label == "Average fiber on days with fiber data");
        Assert.AreEqual(24m, fiber.NumericValue);
        Assert.AreEqual("g/day", fiber.Unit);
    }

    private static CoachService Service(FakeProvider provider) => new(
        provider,
        new FakeInsights(),
        new FakeHistory(),
        new FakeExercises(),
        new FixedTimeProvider());

    private static JsonElement Response(params object[] output) => JsonSerializer.SerializeToElement(new { output });
    private static object FunctionCall(string callId, string name, string arguments) => new
    {
        type = "function_call",
        call_id = callId,
        name,
        arguments,
    };
    private static object Message(string text) => new
    {
        type = "message",
        content = new[] { new { type = "output_text", text } },
    };

    private sealed class FakeProvider(params JsonElement[] responses) : IOpenAiResponsesProvider
    {
        private readonly Queue<JsonElement> responses = new(responses);
        public List<JsonElement> Requests { get; } = [];
        public Task<JsonElement> CreateResponseAsync(JsonElement request, CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            Requests.Add(request.Clone());
            return Task.FromResult(responses.Dequeue());
        }
    }

    private sealed class FakeInsights : IInsightQueries
    {
        public Task<DashboardInsightSnapshot> DashboardAsync(DateOnly through, int days, TimeZoneInfo timeZone, CancellationToken cancellationToken = default)
        {
            DateOnly from = through.AddDays(1 - days);
            WeightInsights weight = InsightAlgorithms.Weight([
                new(through.AddDays(-2), 79m), new(through.AddDays(-1), 80m), new(through, 81m),
            ], from, through);
            return Task.FromResult(new DashboardInsightSnapshot(
                5, from, through, null, new WeightPoint(through, 81m), [],
                InsightAlgorithms.Weight([], through.AddDays(-6), through), weight,
                InsightAlgorithms.Nutrition([], from, through),
                InsightAlgorithms.Training([], 0), 0));
        }

        public Task<ExerciseProgressSnapshot> ExerciseProgressAsync(Guid exerciseId, int? windowDays, DateTime throughUtc, TimeZoneInfo timeZone, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseProgressSnapshot(5, exerciseId, windowDays, DateTime.UnixEpoch, throughUtc, [], null, EmptyRecords));
    }

    private sealed class NoDataInsights : IInsightQueries
    {
        public Task<DashboardInsightSnapshot> DashboardAsync(DateOnly through, int days, TimeZoneInfo timeZone, CancellationToken cancellationToken = default)
        {
            DateOnly from = through.AddDays(1 - days);
            return Task.FromResult(new DashboardInsightSnapshot(
                5, from, through, null, null, [],
                InsightAlgorithms.Weight([], through.AddDays(-6), through),
                InsightAlgorithms.Weight([], from, through),
                InsightAlgorithms.Nutrition([], from, through),
                InsightAlgorithms.Training([], 0), 0));
        }

        public Task<ExerciseProgressSnapshot> ExerciseProgressAsync(Guid exerciseId, int? windowDays, DateTime throughUtc, TimeZoneInfo timeZone, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseProgressSnapshot(5, exerciseId, windowDays, DateTime.UnixEpoch, throughUtc, [], null, EmptyRecords));
    }

    private sealed class NutritionInsightsStub : IInsightQueries
    {
        public Task<DashboardInsightSnapshot> DashboardAsync(DateOnly through, int days, TimeZoneInfo timeZone, CancellationToken cancellationToken = default)
        {
            DateOnly from = through.AddDays(1 - days);
            NutritionInsights nutrition = InsightAlgorithms.Nutrition([
                new NutritionPoint(through.AddDays(-1), 2400m, 180m, null, null, NutritionSources.LegacyCheckIn),
                new NutritionPoint(through, 2500m, 190m, 300m, 70m, NutritionSources.MealDiary, 24m),
            ], from, through);
            return Task.FromResult(new DashboardInsightSnapshot(
                7, from, through, null, null, [],
                InsightAlgorithms.Weight([], through.AddDays(-6), through),
                InsightAlgorithms.Weight([], from, through), nutrition,
                InsightAlgorithms.Training([], 0), 0));
        }

        public Task<ExerciseProgressSnapshot> ExerciseProgressAsync(Guid exerciseId, int? windowDays, DateTime throughUtc, TimeZoneInfo timeZone, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseProgressSnapshot(7, exerciseId, windowDays, DateTime.UnixEpoch, throughUtc, [], null, EmptyRecords));
    }

    private sealed class FakeHistory : IWorkoutHistoryQueries
    {
        public Task<IReadOnlyList<WorkoutHistorySummary>> ListAsync(int offset, int limit, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<WorkoutHistorySummary>>([]);
        public Task<WorkoutSnapshot?> GetAsync(Guid workoutId, CancellationToken cancellationToken = default) => Task.FromResult<WorkoutSnapshot?>(null);
    }

    private sealed class FakeExercises : IExerciseCatalogQueries
    {
        public Task<ExerciseCatalogPage> SearchAsync(ExerciseCatalogFilter filter, CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExerciseCatalogPage([], 0, filter.Limit, 0, []));
    }

    private static readonly ExerciseRecords EmptyRecords = new([], [], [], [], []);

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2026, 8, 18, 12, 0, 0, TimeSpan.Zero);
    }
}
