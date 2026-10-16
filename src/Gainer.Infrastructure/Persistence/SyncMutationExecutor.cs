using System.Text.Json;
using Gainer.Core.BodyTracking;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Core.Nutrition;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncMutationExecutor(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider) : ISyncMutationExecutor
{
    private const string InvalidPayloadCode = "invalid_payload";

    public async Task<SyncMutationExecutionResult> ExecuteAsync(
        Guid mutationId,
        CanonicalMutationContent content,
        CancellationToken cancellationToken = default)
    {
        var collector = new ChangeCollector();
        switch (content.Operation)
        {
            case "createDailyCheckIn":
                {
                    CreateCheckInPayload payload = Deserialize<CreateCheckInPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.DailyCheckIn, payload.CheckInId, 0);
                    DailyCheckInSnapshot snapshot = await new DailyCheckInMutationHandler(context, userContext, timeProvider, collector)
                        .CreateAsync(CreateDailyCheckInMutation.Create(
                            Metadata(mutationId, content), payload.CheckInId, payload.LocalDate, payload.Values), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "correctDailyCheckIn":
                {
                    CorrectCheckInPayload payload = Deserialize<CorrectCheckInPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.DailyCheckIn, payload.CheckInId, payload.BaseVersion);
                    DailyCheckInSnapshot snapshot = await new DailyCheckInMutationHandler(context, userContext, timeProvider, collector)
                        .CorrectAsync(CorrectDailyCheckInMutation.Create(
                            Metadata(mutationId, content), payload.CheckInId, payload.BaseVersion, payload.Values), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "createCustomExercise":
                {
                    CreateCustomExercisePayload payload = Deserialize<CreateCustomExercisePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.CustomExercise, payload.ExerciseId, 0);
                    CustomExerciseSnapshot snapshot = await new CustomExerciseMutationHandler(context, userContext, timeProvider, collector)
                        .CreateAsync(CreateCustomExerciseMutation.Create(
                            Metadata(mutationId, content), payload.ExerciseId, payload.Values), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "updateCustomExercise":
                {
                    UpdateCustomExercisePayload payload = Deserialize<UpdateCustomExercisePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.CustomExercise, payload.ExerciseId, payload.BaseVersion);
                    CustomExerciseSnapshot snapshot = await new CustomExerciseMutationHandler(context, userContext, timeProvider, collector)
                        .UpdateAsync(UpdateCustomExerciseMutation.Create(
                            Metadata(mutationId, content), payload.ExerciseId, payload.BaseVersion, payload.Values), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "archiveCustomExercise":
                {
                    ArchiveCustomExercisePayload payload = Deserialize<ArchiveCustomExercisePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.CustomExercise, payload.ExerciseId, payload.BaseVersion);
                    CustomExerciseSnapshot snapshot = await new CustomExerciseMutationHandler(context, userContext, timeProvider, collector)
                        .ArchiveAsync(ArchiveCustomExerciseMutation.Create(
                            Metadata(mutationId, content), payload.ExerciseId, payload.BaseVersion), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "activateBodyGoal":
                {
                    ActivateBodyGoalPayload payload = Deserialize<ActivateBodyGoalPayload>(content.Payload);
                    BodyGoalKind kind = Enum.TryParse(payload.Kind, ignoreCase: true, out BodyGoalKind parsedKind)
                        ? parsedKind
                        : throw new SyncMutationValidationException(InvalidPayloadCode, "The body goal kind is invalid.");
                    ActiveBodyGoalExpectation? expected = payload.ExpectedActiveGoalId is { } activeId &&
                        payload.ExpectedActiveGoalVersion is { } activeVersion
                            ? new ActiveBodyGoalExpectation(activeId, activeVersion)
                            : null;
                    var expectations = new List<(ResourceKind Kind, Guid Id, long Version)>
                    {
                        (ResourceKind.BodyGoal, payload.GoalId, 0),
                    };
                    if (expected is not null) expectations.Add((ResourceKind.BodyGoal, expected.GoalId, expected.Version));
                    ValidateExpectations(content, expectations);
                    BodyGoalSnapshot snapshot = await new BodyGoalMutationHandler(context, userContext, timeProvider, collector)
                        .ActivateAsync(ActivateBodyGoalMutation.Create(
                            Metadata(mutationId, content), payload.GoalId, kind, payload.StartWeightKg,
                            payload.TargetWeightKg, payload.StartDate, payload.TargetDate, expected), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveWorkoutTemplate":
                {
                    SaveWorkoutTemplatePayload payload = Deserialize<SaveWorkoutTemplatePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.WorkoutTemplate, payload.TemplateId, payload.BaseVersion);
                    WorkoutTemplateSnapshot snapshot = await new WorkoutTemplateMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveWorkoutTemplateMutation.Create(
                            Metadata(mutationId, content), payload.TemplateId, payload.BaseVersion, payload.Name, payload.Items), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "archiveWorkoutTemplate":
                {
                    ArchiveWorkoutTemplatePayload payload = Deserialize<ArchiveWorkoutTemplatePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.WorkoutTemplate, payload.TemplateId, payload.BaseVersion);
                    WorkoutTemplateSnapshot snapshot = await new WorkoutTemplateMutationHandler(context, userContext, timeProvider, collector)
                        .ArchiveAsync(ArchiveWorkoutTemplateMutation.Create(
                            Metadata(mutationId, content), payload.TemplateId, payload.BaseVersion), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveWorkoutRotation":
                {
                    SaveWorkoutRotationPayload payload = Deserialize<SaveWorkoutRotationPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.WorkoutRotation, payload.RotationId, payload.BaseVersion);
                    WorkoutRotationSnapshot snapshot = await new WorkoutRotationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveWorkoutRotationMutation.Create(
                            Metadata(mutationId, content), payload.RotationId, payload.BaseVersion, payload.Entries), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "startWorkout":
                {
                    StartWorkoutPayload payload = Deserialize<StartWorkoutPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.Workout, payload.WorkoutId, 0);
                    WorkoutSnapshot snapshot = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .StartAsync(StartWorkoutMutation.Create(
                            Metadata(mutationId, content), payload.WorkoutId, payload.TemplateId), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "editWorkout":
                {
                    EditWorkoutPayload payload = Deserialize<EditWorkoutPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.Workout, payload.WorkoutId, payload.BaseVersion);
                    WorkoutSnapshot snapshot = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .EditAsync(EditWorkoutMutation.Create(
                            Metadata(mutationId, content), payload.WorkoutId, payload.BaseVersion, payload.Exercises), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "completeWorkout":
                {
                    CompleteWorkoutPayload payload = Deserialize<CompleteWorkoutPayload>(content.Payload);
                    var expectations = new List<(ResourceKind Kind, Guid Id, long Version)>
                    {
                        (ResourceKind.Workout, payload.WorkoutId, payload.BaseVersion),
                    };
                    if (payload.RotationId is { } rotationId && payload.RotationBaseVersion is { } rotationVersion)
                    {
                        expectations.Add((ResourceKind.WorkoutRotation, rotationId, rotationVersion));
                    }
                    ValidateExpectations(content, expectations);
                    CompleteWorkoutResult result = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .CompleteAsync(CompleteWorkoutMutation.Create(
                            Metadata(mutationId, content), payload.WorkoutId, payload.BaseVersion,
                            payload.RotationId, payload.RotationBaseVersion), cancellationToken);
                    return Result(collector, result.Workout);
                }
            case "discardWorkout":
                {
                    DiscardWorkoutPayload payload = Deserialize<DiscardWorkoutPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.Workout, payload.WorkoutId, payload.BaseVersion);
                    WorkoutSnapshot snapshot = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .DiscardAsync(DiscardWorkoutMutation.Create(
                            Metadata(mutationId, content), payload.WorkoutId, payload.BaseVersion), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveNutritionDay":
                {
                    SaveNutritionDayPayload payload = Deserialize<SaveNutritionDayPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionDay, payload.NutritionDayId, payload.BaseVersion);
                    NutritionEntryInput[] entries = payload.Entries.Select(item => NutritionEntryInput.Create(
                        item.EntryId,
                        ParseMeal(item.Meal),
                        item.Position,
                        item.ProductName,
                        item.AmountGrams,
                        new NutritionPer100Grams(
                            item.KilocaloriesPer100Grams,
                            item.ProteinGramsPer100Grams,
                            item.CarbohydrateGramsPer100Grams,
                            item.FatGramsPer100Grams),
                        item.Brand,
                        item.Source)).ToArray();
                    NutritionDaySnapshot snapshot = await new NutritionDayMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveNutritionDayMutation.Create(
                            Metadata(mutationId, content), payload.NutritionDayId, payload.LocalDate,
                            payload.BaseVersion, entries), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "deleteNutritionDay":
                {
                    DeleteNutritionDayPayload payload = Deserialize<DeleteNutritionDayPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionDay, payload.NutritionDayId, payload.BaseVersion);
                    _ = await new NutritionDayMutationHandler(context, userContext, timeProvider, collector)
                        .DeleteAsync(DeleteNutritionDayMutation.Create(
                            Metadata(mutationId, content), payload.NutritionDayId, payload.BaseVersion), cancellationToken);
                    return Result(collector);
                }
            case "saveReusableMeal":
                {
                    SaveReusableMealPayload payload = Deserialize<SaveReusableMealPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.ReusableMeal, payload.ReusableMealId, payload.BaseVersion);
                    ReusableMealComponentDraft[] components = payload.Components.Select(item =>
                        ReusableMealComponentDraft.Create(
                            item.ComponentId,
                            item.Position,
                            item.Name,
                            item.AmountGrams,
                            new NutritionPer100Grams(
                                item.KilocaloriesPer100Grams,
                                item.ProteinGramsPer100Grams,
                                item.CarbohydrateGramsPer100Grams,
                                item.FatGramsPer100Grams),
                            item.Brand,
                            item.Source)).ToArray();
                    ReusableMealDraft values = ReusableMealDraft.Create(
                        payload.Name, payload.Description, payload.StandardPortion, components);
                    ReusableMealSnapshot snapshot = await new ReusableMealMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveReusableMealMutation.Create(
                            Metadata(mutationId, content), payload.ReusableMealId, payload.BaseVersion, values), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "archiveReusableMeal":
                {
                    ArchiveReusableMealPayload payload = Deserialize<ArchiveReusableMealPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.ReusableMeal, payload.ReusableMealId, payload.BaseVersion);
                    ReusableMealSnapshot snapshot = await new ReusableMealMutationHandler(context, userContext, timeProvider, collector)
                        .ArchiveAsync(ArchiveReusableMealMutation.Create(
                            Metadata(mutationId, content), payload.ReusableMealId, payload.BaseVersion), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveNutritionTargetSchedule":
                {
                    SaveNutritionTargetSchedulePayload payload = Deserialize<SaveNutritionTargetSchedulePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionTargetSchedule, payload.NutritionTargetScheduleId, payload.BaseVersion);
                    NutritionTargetVersionPayload[] orderedPayloads = payload.Versions
                        .OrderBy(item => item.EffectiveFrom)
                        .ToArray();
                    NutritionTargetVersionDraft[] versions = ToTargetVersionDrafts(orderedPayloads);
                    NutritionTargetScheduleSnapshot snapshot = await new NutritionTargetScheduleMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveNutritionTargetScheduleMutation.Create(
                            Metadata(mutationId, content), payload.NutritionTargetScheduleId, payload.BaseVersion,
                            NutritionTargetScheduleDraft.Create(versions)), cancellationToken);
                    return Result(collector, snapshot);
                }
            default:
                throw new SyncMutationValidationException("unsupported_operation", "The mutation operation is not supported.");
        }
    }

    private static NutritionTargetVersionDraft[] ToTargetVersionDrafts(NutritionTargetVersionPayload[] orderedPayloads) =>
        orderedPayloads.Select((item, index) =>
        {
            bool legacy = string.IsNullOrWhiteSpace(item.Name) &&
                string.IsNullOrWhiteSpace(item.Category) &&
                string.IsNullOrWhiteSpace(item.InputMode);
            DateOnly? effectiveUntil = item.EffectiveUntil;
            if (legacy && effectiveUntil is null && index + 1 < orderedPayloads.Length)
                effectiveUntil = orderedPayloads[index + 1].EffectiveFrom.AddDays(-1);
            return NutritionTargetVersionDraft.Restore(
                item.TargetVersionId,
                string.IsNullOrWhiteSpace(item.Name) ? "Ziel" : item.Name,
                string.IsNullOrWhiteSpace(item.Category)
                    ? NutritionGoalCategory.Custom
                    : ParseGoalCategory(item.Category),
                item.EffectiveFrom,
                effectiveUntil,
                item.Kilocalories,
                string.IsNullOrWhiteSpace(item.InputMode)
                    ? NutritionTargetInputMode.Grams
                    : ParseTargetInputMode(item.InputMode),
                item.ProteinGrams,
                item.CarbohydrateGrams,
                item.FatGrams,
                item.ProteinPercent,
                item.CarbohydratePercent,
                item.FatPercent,
                ParseTargetOrigin(item.Origin),
                item.AlgorithmVersion,
                item.Reason);
        }).ToArray();

    private static T Deserialize<T>(JsonElement payload)
    {
        try
        {
            return payload.Deserialize<T>(SerializerOptions)
                ?? throw new JsonException("Payload was null.");
        }
        catch (JsonException exception)
        {
            throw new SyncMutationValidationException(InvalidPayloadCode, exception.Message);
        }
    }

    private static MutationMetadata Metadata(Guid mutationId, CanonicalMutationContent content) =>
        MutationMetadata.Create(mutationId, content.ClientId, content.ClientSequence);

    private static void ValidateExpectation(
        CanonicalMutationContent content,
        ResourceKind kind,
        Guid resourceId,
        long baseVersion)
    {
        CanonicalResourceVersion? expected = content.Resources.Count == 1 ? content.Resources[0] : null;
        if (expected is null ||
            !string.Equals(expected.ResourceType, kind.ToString(), StringComparison.Ordinal) ||
            expected.ResourceId != resourceId ||
            expected.BaseVersion != baseVersion)
        {
            throw new SyncMutationValidationException(
                "resource_expectation_mismatch",
                "The payload does not match its declared resource expectation.");
        }
    }

    private static void ValidateExpectations(
        CanonicalMutationContent content,
        List<(ResourceKind Kind, Guid Id, long Version)> expected)
    {
        bool matches = content.Resources.Count == expected.Count && expected.All(item =>
            content.Resources.Any(resource =>
                string.Equals(resource.ResourceType, item.Kind.ToString(), StringComparison.Ordinal) &&
                resource.ResourceId == item.Id && resource.BaseVersion == item.Version));
        if (!matches)
        {
            throw new SyncMutationValidationException(
                "resource_expectation_mismatch",
                "The payload does not match its declared resource expectations.");
        }
    }

    private static SyncMutationExecutionResult Result(ChangeCollector collector, IResourceSnapshot snapshot)
    {
        _ = snapshot;
        return new SyncMutationExecutionResult(collector.Changes.Select(change => change switch
        {
            UpsertedResourceChange upsert => new ExecutedSyncChange(
                upsert.Resource, upsert.Version, upsert.Snapshot),
            DeletedResourceChange deletion => new ExecutedSyncChange(
                deletion.Resource, deletion.Version, null, IsTombstone: true),
            _ => throw new InvalidOperationException("Unknown captured change."),
        }).ToList());
    }

    private static SyncMutationExecutionResult Result(ChangeCollector collector) =>
        new(collector.Changes.Select(change => change switch
        {
            UpsertedResourceChange upsert => new ExecutedSyncChange(upsert.Resource, upsert.Version, upsert.Snapshot),
            DeletedResourceChange deletion => new ExecutedSyncChange(deletion.Resource, deletion.Version, null, IsTombstone: true),
            _ => throw new InvalidOperationException("Unknown captured change."),
        }).ToList());

    private static MealType ParseMeal(string value) =>
        Enum.TryParse(value, ignoreCase: true, out MealType meal) && Enum.IsDefined(meal)
            ? meal
            : throw new SyncMutationValidationException(InvalidPayloadCode, "The meal type is invalid.");

    private static NutritionTargetOrigin ParseTargetOrigin(string value) =>
        Enum.TryParse(value, ignoreCase: true, out NutritionTargetOrigin origin) && Enum.IsDefined(origin)
            ? origin
            : throw new SyncMutationValidationException(InvalidPayloadCode, "The nutrition target origin is invalid.");

    private static NutritionGoalCategory ParseGoalCategory(string value) =>
        Enum.TryParse(value, ignoreCase: true, out NutritionGoalCategory category) && Enum.IsDefined(category)
            ? category
            : throw new SyncMutationValidationException(InvalidPayloadCode, "The nutrition goal category is invalid.");

    private static NutritionTargetInputMode ParseTargetInputMode(string value) =>
        Enum.TryParse(value, ignoreCase: true, out NutritionTargetInputMode inputMode) && Enum.IsDefined(inputMode)
            ? inputMode
            : throw new SyncMutationValidationException(InvalidPayloadCode, "The nutrition target input mode is invalid.");

    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web);

    private sealed record CreateCheckInPayload(Guid CheckInId, DateOnly LocalDate, DailyCheckInValues Values);
    private sealed record CorrectCheckInPayload(Guid CheckInId, long BaseVersion, DailyCheckInValues Values);
    private sealed record CreateCustomExercisePayload(Guid ExerciseId, CustomExerciseValues Values);
    private sealed record UpdateCustomExercisePayload(Guid ExerciseId, long BaseVersion, CustomExerciseValues Values);
    private sealed record ArchiveCustomExercisePayload(Guid ExerciseId, long BaseVersion);
    private sealed record ActivateBodyGoalPayload(
        Guid GoalId,
        string Kind,
        decimal StartWeightKg,
        decimal TargetWeightKg,
        DateOnly StartDate,
        DateOnly? TargetDate,
        Guid? ExpectedActiveGoalId,
        long? ExpectedActiveGoalVersion);
    private sealed record SaveWorkoutTemplatePayload(
        Guid TemplateId,
        long BaseVersion,
        string Name,
        IReadOnlyList<WorkoutTemplateItemValues> Items);
    private sealed record ArchiveWorkoutTemplatePayload(Guid TemplateId, long BaseVersion);
    private sealed record SaveWorkoutRotationPayload(
        Guid RotationId,
        long BaseVersion,
        IReadOnlyList<WorkoutRotationEntry> Entries);
    private sealed record StartWorkoutPayload(Guid WorkoutId, Guid TemplateId);
    private sealed record EditWorkoutPayload(
        Guid WorkoutId,
        long BaseVersion,
        IReadOnlyList<WorkoutExerciseSnapshotValues> Exercises);
    private sealed record CompleteWorkoutPayload(
        Guid WorkoutId,
        long BaseVersion,
        Guid? RotationId,
        long? RotationBaseVersion);
    private sealed record DiscardWorkoutPayload(Guid WorkoutId, long BaseVersion);
    private sealed record SaveNutritionDayPayload(
        Guid NutritionDayId,
        DateOnly LocalDate,
        long BaseVersion,
        IReadOnlyList<NutritionEntryPayload> Entries);
    private sealed record DeleteNutritionDayPayload(Guid NutritionDayId, long BaseVersion);
    private sealed record SaveReusableMealPayload(
        Guid ReusableMealId,
        long BaseVersion,
        string Name,
        string? Description,
        decimal StandardPortion,
        IReadOnlyList<ReusableMealComponentPayload> Components);
    private sealed record ArchiveReusableMealPayload(Guid ReusableMealId, long BaseVersion);
    private sealed record ReusableMealComponentPayload(
        Guid ComponentId,
        int Position,
        string Name,
        string? Brand,
        decimal AmountGrams,
        decimal KilocaloriesPer100Grams,
        decimal? ProteinGramsPer100Grams,
        decimal? CarbohydrateGramsPer100Grams,
        decimal? FatGramsPer100Grams,
        NutritionSourceSnapshot? Source);
    private sealed record SaveNutritionTargetSchedulePayload(
        Guid NutritionTargetScheduleId,
        long BaseVersion,
        IReadOnlyList<NutritionTargetVersionPayload> Versions);
    private sealed record NutritionTargetVersionPayload(
        Guid TargetVersionId,
        string? Name,
        string? Category,
        DateOnly EffectiveFrom,
        DateOnly? EffectiveUntil,
        decimal Kilocalories,
        string? InputMode,
        decimal ProteinGrams,
        decimal CarbohydrateGrams,
        decimal FatGrams,
        decimal? ProteinPercent,
        decimal? CarbohydratePercent,
        decimal? FatPercent,
        string Origin,
        string? AlgorithmVersion,
        string? Reason);
    private sealed record NutritionEntryPayload(
        Guid EntryId,
        string Meal,
        int Position,
        string ProductName,
        string? Brand,
        decimal AmountGrams,
        decimal KilocaloriesPer100Grams,
        decimal? ProteinGramsPer100Grams,
        decimal? CarbohydrateGramsPer100Grams,
        decimal? FatGramsPer100Grams,
        NutritionSourceSnapshot? Source);
}
