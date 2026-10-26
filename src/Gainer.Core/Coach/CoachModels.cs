using System.Text.Json;

namespace Gainer.Core.Coach;

public sealed record CoachFact(
    string FactId,
    string Kind,
    string Label,
    decimal? NumericValue,
    string? TextValue,
    string? Unit,
    string Period,
    string? AlgorithmVersion);

public sealed record CoachObservation(string Text, IReadOnlyList<string> FactIds);

/// <summary>A durable note the model proposes; nothing is stored until the user confirms it.</summary>
public sealed record CoachMemorySuggestion(CoachMemoryCategory Category, string Text);

public sealed record CoachAnswer(
    string Summary,
    IReadOnlyList<CoachObservation> Observations,
    IReadOnlyList<CoachFact> Facts,
    IReadOnlyList<string> DataGaps,
    IReadOnlyList<string> Suggestions,
    long AsOfRevision,
    IReadOnlyList<CoachMemorySuggestion> MemorySuggestions);

public interface ICoachService
{
    Task<CoachAnswer> AnswerAsync(string question, CancellationToken cancellationToken = default);
}

public sealed class CoachResponseValidationException(string message) : Exception(message);

public static class CoachToolCatalog
{
    public static JsonElement Definitions { get; } = JsonDocument.Parse("""
    [
      {"type":"function","name":"get_goal","description":"Read the current body goal.","strict":true,"parameters":{"type":"object","properties":{},"required":[],"additionalProperties":false}},
      {"type":"function","name":"get_weight_summary","description":"Read deterministic weight metrics for a bounded period.","strict":true,"parameters":{"type":"object","properties":{"days":{"type":"integer","enum":[7,30,90]}},"required":["days"],"additionalProperties":false}},
      {"type":"function","name":"get_nutrition_summary","description":"Read deterministic nutrition averages for a bounded period.","strict":true,"parameters":{"type":"object","properties":{"days":{"type":"integer","enum":[7,30,90]}},"required":["days"],"additionalProperties":false}},
      {"type":"function","name":"get_recent_workouts","description":"Read a bounded list of completed workout summaries without notes.","strict":true,"parameters":{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":10}},"required":["limit"],"additionalProperties":false}},
      {"type":"function","name":"get_strength_overview","description":"Read deterministic completed-workout volume and best-set metrics.","strict":true,"parameters":{"type":"object","properties":{"days":{"type":"integer","enum":[7,30,90]}},"required":["days"],"additionalProperties":false}},
      {"type":"function","name":"get_exercise_progress","description":"Read progress only for a server-approved stable exercise id.","strict":true,"parameters":{"type":"object","properties":{"exerciseId":{"type":"string","format":"uuid"},"days":{"type":["integer","null"],"enum":[7,30,90,null]}},"required":["exerciseId","days"],"additionalProperties":false}},
      {"type":"function","name":"compare_periods","description":"Compare the same deterministic metric over two bounded periods. The previous period ends directly before the current one begins, so they never overlap. training_volume is returned as a per-day mean so periods of different length are comparable.","strict":true,"parameters":{"type":"object","properties":{"metric":{"type":"string","enum":["weight_average","calories_average","protein_average","training_volume"]},"currentDays":{"type":"integer","enum":[7,30,90]},"previousDays":{"type":"integer","enum":[7,30,90]}},"required":["metric","currentDays","previousDays"],"additionalProperties":false}}
    ]
    """).RootElement.Clone();

    public static JsonElement OutputSchema { get; } = JsonDocument.Parse("""
    {
      "type":"object",
      "properties":{
        "summary":{"type":"string","minLength":1,"maxLength":1000},
        "observations":{"type":"array","maxItems":8,"items":{"type":"object","properties":{"text":{"type":"string","minLength":1,"maxLength":500},"factIds":{"type":"array","maxItems":8,"items":{"type":"string","minLength":1,"maxLength":160}}},"required":["text","factIds"],"additionalProperties":false}},
        "dataGaps":{"type":"array","maxItems":8,"items":{"type":"string","minLength":1,"maxLength":300}},
        "suggestions":{"type":"array","maxItems":6,"items":{"type":"string","minLength":1,"maxLength":300}},
        "memorySuggestions":{"type":"array","maxItems":3,"items":{"type":"object","properties":{"category":{"type":"string","enum":["goal","preference","intolerance","injury","other"]},"text":{"type":"string","minLength":1,"maxLength":200}},"required":["category","text"],"additionalProperties":false}}
      },
      "required":["summary","observations","dataGaps","suggestions","memorySuggestions"],
      "additionalProperties":false
    }
    """).RootElement.Clone();
}
