using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Gainer.Core.Coach;
using Gainer.Core.Insights;
using Gainer.Core.Training;

namespace Gainer.Infrastructure.Coach;

public sealed partial class CoachService(
    IOpenAiResponsesProvider provider,
    IInsightQueries insights,
    IWorkoutHistoryQueries workoutHistory,
    IExerciseCatalogQueries exercises,
    TimeProvider timeProvider) : ICoachService
{
    private const int MaximumRounds = 3;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<CoachAnswer> AnswerAsync(string question, CancellationToken cancellationToken = default)
    {
        string normalized = question.Trim();
        if (normalized.Length is < 1 or > 1_000) throw new ArgumentException("Question must contain 1 to 1000 characters.", nameof(question));
        if (MedicalPattern().IsMatch(normalized))
        {
            return new CoachAnswer(
                "Ich kann keine medizinische Diagnose oder Behandlungsempfehlung geben.",
                [], [], ["Für diese Frage sind medizinische Untersuchung und Kontext erforderlich."],
                ["Bitte wende dich bei Beschwerden an qualifiziertes medizinisches Fachpersonal."], 0);
        }

        var inputs = new List<JsonElement>
        {
            JsonSerializer.SerializeToElement(new
            {
                role = "user",
                content = new[] { new { type = "input_text", text = normalized } },
            }, JsonOptions),
        };
        var facts = new Dictionary<string, CoachFact>(StringComparer.Ordinal);
        long asOfRevision = 0;
        for (int round = 0; round < MaximumRounds; round++)
        {
            JsonElement response = await provider.CreateResponseAsync(Request(inputs), cancellationToken);
            JsonElement[] output = ReadOutput(response);
            inputs.AddRange(output.Select(item => item.Clone()));
            JsonElement[] calls = output.Where(item => item.TryGetProperty("type", out JsonElement type) &&
                type.GetString() == "function_call").ToArray();
            if (calls.Length == 0)
            {
                ModelAnswer model = ParseModelAnswer(output);
                return Validate(model, facts, asOfRevision);
            }
            foreach (JsonElement call in calls)
            {
                string callId = RequiredString(call, "call_id");
                string name = RequiredString(call, "name");
                string arguments = RequiredString(call, "arguments");
                ToolResult result = await ExecuteToolAsync(name, arguments, cancellationToken);
                asOfRevision = Math.Max(asOfRevision, result.AsOfRevision);
                MergeFacts(facts, result.Facts);
                inputs.Add(JsonSerializer.SerializeToElement(new
                {
                    type = "function_call_output",
                    call_id = callId,
                    output = JsonSerializer.Serialize(result, JsonOptions),
                }, JsonOptions));
            }
        }
        throw new CoachResponseValidationException("The tool round limit was exceeded.");
    }

    private static void MergeFacts(Dictionary<string, CoachFact> facts, IReadOnlyList<CoachFact> items)
    {
        foreach (CoachFact fact in items)
        {
            if (facts.Count >= 100 && !facts.ContainsKey(fact.FactId))
                throw new CoachResponseValidationException("The fact limit was exceeded.");
            facts[fact.FactId] = fact;
        }
    }

    private static JsonElement Request(IReadOnlyList<JsonElement> inputs) => JsonSerializer.SerializeToElement(new
    {
        instructions = """
            You are a read-only fitness progress summarizer. Use only tool facts. Never diagnose, prescribe,
            or invent measurements. Do not recommend numeric calorie targets or numeric training changes.
            Every observation containing a measured claim must cite its factIds. State missing data plainly.
            """,
        input = inputs,
        tools = CoachToolCatalog.Definitions,
        tool_choice = "auto",
        parallel_tool_calls = true,
        text = new
        {
            format = new
            {
                type = "json_schema",
                name = "coach_progress_answer",
                strict = true,
                schema = CoachToolCatalog.OutputSchema,
            },
        },
    }, JsonOptions);

    private async Task<ToolResult> ExecuteToolAsync(string name, string arguments, CancellationToken cancellationToken)
    {
        using JsonDocument document = ParseArguments(arguments);
        JsonElement args = document.RootElement;
        return name switch
        {
            "get_goal" => await Goal(args, cancellationToken),
            "get_weight_summary" => await Weight(args, cancellationToken),
            "get_nutrition_summary" => await Nutrition(args, cancellationToken),
            "get_recent_workouts" => await RecentWorkouts(args, cancellationToken),
            "get_strength_overview" => await Strength(args, cancellationToken),
            "get_exercise_progress" => await ExerciseProgress(args, cancellationToken),
            "compare_periods" => await Compare(args, cancellationToken),
            _ => throw new CoachResponseValidationException("The model requested an unknown tool."),
        };
    }

    private async Task<ToolResult> Goal(JsonElement args, CancellationToken cancellationToken)
    {
        RequireProperties(args);
        DashboardInsightSnapshot data = await Dashboard(30, cancellationToken);
        return data.ActiveGoal is null
            ? new ToolResult(data.AsOfRevision, [], ["No active goal is available."])
            : new ToolResult(data.AsOfRevision, [
                Fact(data, "goal.kind", "goal", "Active goal", null, data.ActiveGoal.Kind.ToString(), null, "current", null),
                Fact(data, "goal.target_weight", "goal", "Target weight", data.ActiveGoal.TargetWeightKg, null, "kg", "current", null),
            ], []);
    }

    private async Task<ToolResult> Weight(JsonElement args, CancellationToken cancellationToken)
    {
        int days = RequiredDays(args, "days");
        DashboardInsightSnapshot data = await Dashboard(days, cancellationToken);
        var result = new List<CoachFact>();
        if (data.Weight.AverageKg is { } average)
            result.Add(Fact(data, $"weight.avg.{days}", "weight", "Average weight", average, null, "kg", $"last {days} days", data.Weight.AverageAlgorithmVersion));
        if (data.Weight.TrendKgPerWeek is { } trend)
            result.Add(Fact(data, $"weight.trend.{days}", "weight", "Weekly weight trend", trend, null, "kg/week", $"last {days} days", data.Weight.TrendAlgorithmVersion));
        return new ToolResult(data.AsOfRevision, result, result.Count == 0 ? ["No weight measurements are available."] : []);
    }

    private async Task<ToolResult> Nutrition(JsonElement args, CancellationToken cancellationToken)
    {
        int days = RequiredDays(args, "days");
        DashboardInsightSnapshot data = await Dashboard(days, cancellationToken);
        var result = new List<CoachFact>();
        AddMetric(result, data, $"nutrition.calories.{days}", "Average calories", data.Nutrition.CaloriesKcal.Value, "kcal/day", days, data.Nutrition.AlgorithmVersion);
        AddMetric(result, data, $"nutrition.protein.{days}", "Average protein", data.Nutrition.ProteinGrams.Value, "g/day", days, data.Nutrition.AlgorithmVersion);
        if (data.Nutrition.MealDiaryDays > 0)
            result.Add(Fact(data, $"nutrition.source.diary.{days}", "nutrition-source", "Days sourced from meal diary",
                data.Nutrition.MealDiaryDays, NutritionSources.MealDiary, "days", $"last {days} days", data.Nutrition.AlgorithmVersion));
        if (data.Nutrition.LegacyCheckInDays > 0)
            result.Add(Fact(data, $"nutrition.source.legacy.{days}", "nutrition-source", "Days sourced from legacy check-ins",
                data.Nutrition.LegacyCheckInDays, NutritionSources.LegacyCheckIn, "days", $"last {days} days", data.Nutrition.AlgorithmVersion));
        return new ToolResult(data.AsOfRevision, result, result.Count == 0 ? ["No nutrition entries are available."] : []);
    }

    private async Task<ToolResult> RecentWorkouts(JsonElement args, CancellationToken cancellationToken)
    {
        RequireProperties(args, "limit");
        int limit = args.GetProperty("limit").GetInt32();
        if (limit is < 1 or > 10) throw new CoachResponseValidationException("Workout limit is invalid.");
        IReadOnlyList<WorkoutHistorySummary> items = await workoutHistory.ListAsync(0, limit, cancellationToken);
        List<CoachFact> facts = items.Select((item, index) => new CoachFact(
            $"workout:{item.WorkoutId:N}:completed",
            "workout",
            $"Recent workout {index + 1}",
            item.CompletedSetCount,
            item.TemplateNameSnapshot,
            "completed sets",
            item.CompletedAtUtc.ToString("O", CultureInfo.InvariantCulture),
            null)).ToList();
        DashboardInsightSnapshot dashboard = await Dashboard(30, cancellationToken);
        return new ToolResult(dashboard.AsOfRevision, facts, facts.Count == 0 ? ["No completed workouts are available."] : []);
    }

    private async Task<ToolResult> Strength(JsonElement args, CancellationToken cancellationToken)
    {
        int days = RequiredDays(args, "days");
        DashboardInsightSnapshot data = await Dashboard(days, cancellationToken);
        var facts = new List<CoachFact>
        {
            Fact(data, $"training.volume.{days}", "training", "Training volume", data.Training.VolumeKgRepetitions,
                null, data.Training.VolumeUnit, $"last {days} days", data.Training.VolumeAlgorithmVersion),
            Fact(data, $"training.workouts.{days}", "training", "Completed workouts", data.Training.WorkoutCount,
                null, "workouts", $"last {days} days", null),
        };
        if (data.Training.BestSet is { } best)
            facts.Add(Fact(data, $"training.e1rm.{best.ExerciseId:N}.{days}", "strength", "Best estimated one-rep max",
                best.EstimatedOneRepMaxKg, null, "kg", $"last {days} days", data.Training.EstimatedOneRepMaxAlgorithmVersion));
        return new ToolResult(data.AsOfRevision, facts, []);
    }

    private async Task<ToolResult> ExerciseProgress(JsonElement args, CancellationToken cancellationToken)
    {
        RequireProperties(args, "exerciseId", "days");
        if (!Guid.TryParse(args.GetProperty("exerciseId").GetString(), out Guid exerciseId))
            throw new CoachResponseValidationException("Exercise id is invalid.");
        int? days = args.GetProperty("days").ValueKind == JsonValueKind.Null ? null : args.GetProperty("days").GetInt32();
        if (days is not (null or 7 or 30 or 90)) throw new CoachResponseValidationException("Exercise window is invalid.");
        ExerciseCatalogPage allowed = await exercises.SearchAsync(new ExerciseCatalogFilter(Limit: 200), cancellationToken);
        if (!allowed.Items.Any(item => item.Id == exerciseId))
            throw new CoachResponseValidationException("Exercise id is not approved for this user.");
        ExerciseProgressSnapshot data = await insights.ExerciseProgressAsync(
            exerciseId, days, timeProvider.GetUtcNow().UtcDateTime, TimeZoneInfo.Utc, cancellationToken);
        if (data.BestSet is null) return new ToolResult(data.AsOfRevision, [], ["No completed sets are available for this exercise."]);
        return new ToolResult(data.AsOfRevision, [new CoachFact(
            $"exercise:{exerciseId:N}:e1rm:{days?.ToString() ?? "all"}", "strength", "Exercise best estimated one-rep max",
            data.BestSet.EstimatedOneRepMaxKg, null, "kg", days is null ? "all time" : $"last {days} days",
            InsightAlgorithmVersions.EstimatedOneRepMax)], []);
    }

    private async Task<ToolResult> Compare(JsonElement args, CancellationToken cancellationToken)
    {
        RequireProperties(args, "metric", "currentDays", "previousDays");
        string metric = RequiredString(args, "metric");
        int currentDays = DaysValue(args, "currentDays");
        int previousDays = DaysValue(args, "previousDays");
        if (metric is not ("weight_average" or "calories_average" or "protein_average" or "training_volume"))
            throw new CoachResponseValidationException("Comparison metric is invalid.");
        DashboardInsightSnapshot current = await Dashboard(currentDays, cancellationToken);
        DashboardInsightSnapshot previous = await Dashboard(previousDays, cancellationToken);
        decimal? currentValue = MetricValue(current, metric);
        decimal? previousValue = MetricValue(previous, metric);
        var facts = new List<CoachFact>();
        AddComparisonFact(facts, current, metric, "current", currentDays, currentValue);
        AddComparisonFact(facts, previous, metric, "comparison", previousDays, previousValue);
        return new ToolResult(Math.Max(current.AsOfRevision, previous.AsOfRevision), facts,
            facts.Count < 2 ? ["The selected periods do not both contain enough data."] : []);
    }

    private async Task<DashboardInsightSnapshot> Dashboard(int days, CancellationToken cancellationToken) =>
        await insights.DashboardAsync(DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime), days, cancellationToken);

    private static CoachAnswer Validate(ModelAnswer model, IReadOnlyDictionary<string, CoachFact> facts, long revision)
    {
        if (string.IsNullOrWhiteSpace(model.Summary) || model.Summary.Length > 1_000 || model.Observations.Count > 8 ||
            model.DataGaps.Count > 8 || model.Suggestions.Count > 6)
            throw new CoachResponseValidationException("The structured coach response is outside its limits.");
        foreach (ModelObservation observation in model.Observations)
        {
            if (observation.FactIds.Any(id => !facts.ContainsKey(id)))
                throw new CoachResponseValidationException("The response referenced an unknown fact.");
            if (NumberPattern().IsMatch(observation.Text) && observation.FactIds.Count == 0)
                throw new CoachResponseValidationException("A numeric observation has no evidence fact.");
        }
        if (model.Suggestions.Any(item => NumberPattern().IsMatch(item)))
            throw new CoachResponseValidationException("Numeric prescriptions are not allowed in suggestions.");
        return new CoachAnswer(
            model.Summary,
            model.Observations.Select(item => new CoachObservation(item.Text, item.FactIds)).ToList(),
            facts.Values.OrderBy(item => item.FactId, StringComparer.Ordinal).ToList(),
            model.DataGaps,
            model.Suggestions,
            revision);
    }

    private static ModelAnswer ParseModelAnswer(IReadOnlyList<JsonElement> output)
    {
        string? text = output.SelectMany(item => item.TryGetProperty("content", out JsonElement content) && content.ValueKind == JsonValueKind.Array
                ? content.EnumerateArray() : [])
            .Where(item => item.TryGetProperty("type", out JsonElement type) && type.GetString() == "output_text")
            .Select(item => item.TryGetProperty("text", out JsonElement value) ? value.GetString() : null)
            .FirstOrDefault(value => value is not null);
        if (text is null) throw new CoachResponseValidationException("The provider returned no structured answer.");
        try { return JsonSerializer.Deserialize<ModelAnswer>(text, JsonOptions) ?? throw new JsonException(); }
        catch (JsonException exception) { throw new CoachResponseValidationException($"The structured answer is invalid: {exception.Message}"); }
    }

    private static JsonElement[] ReadOutput(JsonElement response)
    {
        if (!response.TryGetProperty("output", out JsonElement output) || output.ValueKind != JsonValueKind.Array)
            throw new CoachResponseValidationException("The provider response has no output array.");
        return output.EnumerateArray().Select(item => item.Clone()).ToArray();
    }

    private static JsonDocument ParseArguments(string arguments)
    {
        try
        {
            JsonDocument document = JsonDocument.Parse(arguments);
            if (document.RootElement.ValueKind != JsonValueKind.Object) { document.Dispose(); throw new JsonException(); }
            return document;
        }
        catch (JsonException exception) { throw new CoachResponseValidationException($"Tool arguments are invalid: {exception.Message}"); }
    }

    private static void RequireProperties(JsonElement args, params string[] allowed)
    {
        HashSet<string> names = args.EnumerateObject().Select(item => item.Name).ToHashSet(StringComparer.Ordinal);
        if (!names.SetEquals(allowed)) throw new CoachResponseValidationException("Tool arguments do not match the strict schema.");
    }

    private static int RequiredDays(JsonElement args, string name)
    {
        RequireProperties(args, name);
        return DaysValue(args, name);
    }

    private static int DaysValue(JsonElement args, string name)
    {
        int value = args.GetProperty(name).GetInt32();
        return value is 7 or 30 or 90 ? value : throw new CoachResponseValidationException("Tool period is invalid.");
    }

    private static string RequiredString(JsonElement element, string name) =>
        element.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(value.GetString())
            ? value.GetString()! : throw new CoachResponseValidationException($"{name} is required.");

    private static CoachFact Fact(
        DashboardInsightSnapshot data, string suffix, string kind, string label, decimal? number, string? text,
        string? unit, string period, string? algorithm) =>
        new($"rev:{data.AsOfRevision}:{suffix}", kind, label, number, text, unit, period, algorithm);

    private static void AddMetric(List<CoachFact> facts, DashboardInsightSnapshot data, string suffix, string label,
        decimal? value, string unit, int days, string algorithm)
    {
        if (value is { } number) facts.Add(Fact(data, suffix, "nutrition", label, number, null, unit, $"last {days} days", algorithm));
    }

    private static decimal? MetricValue(DashboardInsightSnapshot value, string metric) => metric switch
    {
        "weight_average" => value.Weight.AverageKg,
        "calories_average" => value.Nutrition.CaloriesKcal.Value,
        "protein_average" => value.Nutrition.ProteinGrams.Value,
        "training_volume" => value.Training.VolumeKgRepetitions,
        _ => null,
    };

    private static void AddComparisonFact(List<CoachFact> facts, DashboardInsightSnapshot data, string metric,
        string side, int days, decimal? value)
    {
        if (value is { } number) facts.Add(Fact(data, $"compare.{metric}.{side}.{days}", "comparison", metric,
            number, null, null, $"last {days} days", null));
    }

    private sealed record ToolResult(long AsOfRevision, IReadOnlyList<CoachFact> Facts, IReadOnlyList<string> DataGaps);
    private sealed record ModelAnswer(
        string Summary,
        IReadOnlyList<ModelObservation> Observations,
        IReadOnlyList<string> DataGaps,
        IReadOnlyList<string> Suggestions);
    private sealed record ModelObservation(string Text, IReadOnlyList<string> FactIds);

    [GeneratedRegex(@"\b(pain|injury|diagnos|medical|doctor|arzt|schmerz|verletz|krank|medikament)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex MedicalPattern();

    [GeneratedRegex(@"\d", RegexOptions.CultureInvariant)]
    private static partial Regex NumberPattern();
}
