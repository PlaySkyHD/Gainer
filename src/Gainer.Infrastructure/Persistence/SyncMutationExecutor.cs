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
            case "createExerciseCategory":
                {
                    CreateExerciseCategoryPayload payload = Deserialize<CreateExerciseCategoryPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.ExerciseCategory, payload.CategoryId, 0);
                    ExerciseCategorySnapshot snapshot = await new ExerciseCategoryMutationHandler(context, userContext, timeProvider, collector)
                        .CreateAsync(CreateExerciseCategoryMutation.Create(
                            Metadata(mutationId, content), payload.CategoryId, payload.Name), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "updateExerciseCategory":
                {
                    UpdateExerciseCategoryPayload payload = Deserialize<UpdateExerciseCategoryPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.ExerciseCategory, payload.CategoryId, payload.BaseVersion);
                    ExerciseCategorySnapshot snapshot = await new ExerciseCategoryMutationHandler(context, userContext, timeProvider, collector)
                        .UpdateAsync(UpdateExerciseCategoryMutation.Create(
                            Metadata(mutationId, content), payload.CategoryId, payload.BaseVersion, payload.Name), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "archiveExerciseCategory":
                {
                    ArchiveExerciseCategoryPayload payload = Deserialize<ArchiveExerciseCategoryPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.ExerciseCategory, payload.CategoryId, payload.BaseVersion);
                    ExerciseCategorySnapshot snapshot = await new ExerciseCategoryMutationHandler(context, userContext, timeProvider, collector)
                        .ArchiveAsync(ArchiveExerciseCategoryMutation.Create(
                            Metadata(mutationId, content), payload.CategoryId, payload.BaseVersion), cancellationToken);
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
            case "createWorkout":
                {
                    CreateWorkoutPayload payload = Deserialize<CreateWorkoutPayload>(content.Payload);
                    WorkoutValues workout = RequiredWorkout(payload.Workout);
                    ValidateExpectation(content, ResourceKind.Workout, workout.WorkoutId, 0);
                    WorkoutSnapshot snapshot = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .CreateAsync(CreateWorkoutMutation.Create(Metadata(mutationId, content), workout), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveWorkout":
                {
                    SaveWorkoutPayload payload = Deserialize<SaveWorkoutPayload>(content.Payload);
                    WorkoutValues workout = RequiredWorkout(payload.Workout);
                    ValidateExpectation(content, ResourceKind.Workout, workout.WorkoutId, payload.BaseVersion);
                    WorkoutSnapshot snapshot = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveWorkoutMutation.Create(Metadata(mutationId, content), payload.BaseVersion, workout), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "deleteWorkout":
                {
                    DeleteWorkoutPayload payload = Deserialize<DeleteWorkoutPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.Workout, payload.WorkoutId, payload.BaseVersion);
                    _ = await new WorkoutMutationHandler(context, userContext, timeProvider, collector)
                        .DeleteAsync(DeleteWorkoutMutation.Create(
                            Metadata(mutationId, content), payload.WorkoutId, payload.BaseVersion), cancellationToken);
                    return Result(collector);
                }
            case "createTrainingPlan":
                {
                    CreateTrainingPlanPayload payload = Deserialize<CreateTrainingPlanPayload>(content.Payload);
                    TrainingPlanValues plan = RequiredPlan(payload.Plan);
                    ValidateExpectation(content, ResourceKind.TrainingPlan, plan.PlanId, 0);
                    TrainingPlanSnapshot snapshot = await new TrainingPlanMutationHandler(context, userContext, timeProvider, collector)
                        .CreateAsync(CreateTrainingPlanMutation.Create(Metadata(mutationId, content), plan), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "updateTrainingPlan":
                {
                    UpdateTrainingPlanPayload payload = Deserialize<UpdateTrainingPlanPayload>(content.Payload);
                    TrainingPlanValues plan = RequiredPlan(payload.Plan);
                    ValidateExpectation(content, ResourceKind.TrainingPlan, plan.PlanId, payload.BaseVersion);
                    TrainingPlanSnapshot snapshot = await new TrainingPlanMutationHandler(context, userContext, timeProvider, collector)
                        .UpdateAsync(UpdateTrainingPlanMutation.Create(Metadata(mutationId, content), payload.BaseVersion, plan), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "archiveTrainingPlan":
                {
                    ArchiveTrainingPlanPayload payload = Deserialize<ArchiveTrainingPlanPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.TrainingPlan, payload.PlanId, payload.BaseVersion);
                    TrainingPlanSnapshot snapshot = await new TrainingPlanMutationHandler(context, userContext, timeProvider, collector)
                        .ArchiveAsync(ArchiveTrainingPlanMutation.Create(
                            Metadata(mutationId, content), payload.PlanId, payload.BaseVersion), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "reorderTrainingPlans":
                {
                    ReorderTrainingPlansPayload payload = Deserialize<ReorderTrainingPlansPayload>(content.Payload);
                    if (payload.Plans is null) throw new SyncMutationValidationException(InvalidPayloadCode, "The plan list is missing.");
                    ValidateExpectations(content, payload.Plans
                        .Select(item => (ResourceKind.TrainingPlan, item.PlanId, item.BaseVersion)).ToList());
                    IReadOnlyList<TrainingPlanSnapshot> snapshots = await new TrainingPlanMutationHandler(context, userContext, timeProvider, collector)
                        .ReorderAsync(ReorderTrainingPlansMutation.Create(
                            Metadata(mutationId, content),
                            payload.Plans.Select(item => new TrainingPlanVersion(item.PlanId, item.BaseVersion)).ToArray()), cancellationToken);
                    _ = snapshots;
                    return Result(collector);
                }
            case "saveTrainingSchedule":
                {
                    SaveTrainingSchedulePayload payload = Deserialize<SaveTrainingSchedulePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.TrainingSchedule, payload.ScheduleId, payload.BaseVersion);
                    if (payload.ValidFrom is null)
                    {
                        throw new SyncMutationValidationException(InvalidPayloadCode, "The valid-from date is missing.");
                    }
                    TrainingScheduleSnapshot snapshot = await new TrainingScheduleMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveTrainingScheduleMutation.Create(
                            Metadata(mutationId, content), payload.BaseVersion, payload.ToValues()), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "deleteTrainingSchedule":
                {
                    DeleteTrainingSchedulePayload payload = Deserialize<DeleteTrainingSchedulePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.TrainingSchedule, payload.ScheduleId, payload.BaseVersion);
                    if (payload.BaseVersion < 1)
                    {
                        throw new SyncMutationValidationException(InvalidPayloadCode, "A schedule can only be deleted from a stored version.");
                    }
                    _ = await new TrainingScheduleMutationHandler(context, userContext, timeProvider, collector)
                        .DeleteAsync(DeleteTrainingScheduleMutation.Create(
                            Metadata(mutationId, content), payload.ScheduleId, payload.BaseVersion), cancellationToken);
                    return Result(collector);
                }
            case "mergeExercises":
                {
                    MergeExercisesPayload payload = Deserialize<MergeExercisesPayload>(content.Payload);
                    if (payload.SourceExerciseId == payload.TargetExerciseId)
                    {
                        throw new SyncMutationValidationException("invalid_merge", "The source and target exercise must differ.");
                    }
                    long? targetBaseVersion = MergeExpectations(content, payload);
                    _ = await new ExerciseMergeMutationHandler(context, userContext, timeProvider, collector)
                        .MergeAsync(MergeExercisesMutation.Create(
                            Metadata(mutationId, content), payload.SourceExerciseId, payload.SourceBaseVersion,
                            payload.TargetExerciseId, targetBaseVersion), cancellationToken);
                    return Result(collector);
                }
            case "saveNutritionDay":
                {
                    SaveNutritionDayPayload payload = Deserialize<SaveNutritionDayPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionDay, payload.NutritionDayId, payload.BaseVersion);
                    NutritionEntryInput[] entries = ToEntryInputs(payload.Entries);
                    NutritionDaySnapshot snapshot = await new NutritionDayMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveNutritionDayMutation.Create(
                            Metadata(mutationId, content), payload.NutritionDayId, payload.LocalDate,
                            payload.BaseVersion, entries, ParseDayKind(payload.DayKind)), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "saveNutritionDayTemplate":
                {
                    SaveNutritionDayTemplatePayload payload = Deserialize<SaveNutritionDayTemplatePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionDayTemplate, payload.TemplateId, payload.BaseVersion);
                    NutritionDayTemplateSnapshot snapshot = await new NutritionDayTemplateMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveNutritionDayTemplateMutation.Create(
                            Metadata(mutationId, content), payload.TemplateId, payload.BaseVersion, payload.Name,
                            ParseDayKind(payload.DayKind), ToEntryInputs(payload.Entries ?? [])), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "deleteNutritionDayTemplate":
                {
                    DeleteNutritionDayTemplatePayload payload = Deserialize<DeleteNutritionDayTemplatePayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.NutritionDayTemplate, payload.TemplateId, payload.BaseVersion);
                    _ = await new NutritionDayTemplateMutationHandler(context, userContext, timeProvider, collector)
                        .DeleteAsync(DeleteNutritionDayTemplateMutation.Create(
                            Metadata(mutationId, content), payload.TemplateId, payload.BaseVersion), cancellationToken);
                    return Result(collector);
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
            case "saveCardioSession":
                {
                    SaveCardioSessionPayload payload = Deserialize<SaveCardioSessionPayload>(content.Payload);
                    CardioSessionValues session = payload.Session
                        ?? throw new SyncMutationValidationException(InvalidPayloadCode, "The cardio session is missing.");
                    ValidateExpectation(content, ResourceKind.CardioSession, session.SessionId, payload.BaseVersion);
                    CardioSessionSnapshot snapshot = await new CardioSessionMutationHandler(context, userContext, timeProvider, collector)
                        .SaveAsync(SaveCardioSessionMutation.Create(
                            Metadata(mutationId, content), payload.BaseVersion, session), cancellationToken);
                    return Result(collector, snapshot);
                }
            case "deleteCardioSession":
                {
                    DeleteCardioSessionPayload payload = Deserialize<DeleteCardioSessionPayload>(content.Payload);
                    ValidateExpectation(content, ResourceKind.CardioSession, payload.SessionId, payload.BaseVersion);
                    _ = await new CardioSessionMutationHandler(context, userContext, timeProvider, collector)
                        .DeleteAsync(DeleteCardioSessionMutation.Create(
                            Metadata(mutationId, content), payload.SessionId, payload.BaseVersion), cancellationToken);
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
                                item.FatGramsPer100Grams,
                                item.SaltGramsPer100Grams,
                                item.FiberGramsPer100Grams),
                            item.Brand,
                            item.Source,
                            NutritionPortion.From(item.PieceGrams, item.PieceCount))).ToArray();
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

    private static WorkoutValues RequiredWorkout(WorkoutValues? workout) =>
        workout ?? throw new SyncMutationValidationException(InvalidPayloadCode, "The workout is missing.");

    private static TrainingPlanValues RequiredPlan(TrainingPlanValues? plan) =>
        plan ?? throw new SyncMutationValidationException(InvalidPayloadCode, "The training plan is missing.");

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
                item.Reason,
                item.SaltGrams,
                ToRestDayDraft(item.RestDay),
                item.FiberGrams);
        }).ToArray();

    private static NutritionRestDayTargetDraft? ToRestDayDraft(NutritionRestDayPayload? payload) =>
        payload is null
            ? null
            : NutritionRestDayTargetDraft.Create(
                string.IsNullOrWhiteSpace(payload.InputMode)
                    ? NutritionTargetInputMode.Grams
                    : ParseTargetInputMode(payload.InputMode),
                payload.Kilocalories,
                payload.ProteinGrams,
                payload.CarbohydrateGrams,
                payload.FatGrams,
                payload.ProteinPercent,
                payload.CarbohydratePercent,
                payload.FatPercent);

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

    /// <summary>The source expectation is required; the target expectation is only declared for own target exercises.</summary>
    private static long? MergeExpectations(CanonicalMutationContent content, MergeExercisesPayload payload)
    {
        var mismatch = new SyncMutationValidationException(
            "resource_expectation_mismatch",
            "The payload does not match its declared resource expectations.");
        string customExercise = ResourceKind.CustomExercise.ToString();
        bool sourceDeclared = false;
        long? targetBaseVersion = null;
        foreach (CanonicalResourceVersion resource in content.Resources)
        {
            if (!string.Equals(resource.ResourceType, customExercise, StringComparison.Ordinal)) throw mismatch;
            if (!sourceDeclared && resource.ResourceId == payload.SourceExerciseId
                && resource.BaseVersion == payload.SourceBaseVersion)
            {
                sourceDeclared = true;
            }
            else if (targetBaseVersion is null && resource.ResourceId == payload.TargetExerciseId)
            {
                targetBaseVersion = resource.BaseVersion;
            }
            else
            {
                throw mismatch;
            }
        }
        if (!sourceDeclared) throw mismatch;
        return targetBaseVersion;
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

    private static NutritionEntryInput[] ToEntryInputs(IEnumerable<NutritionEntryPayload> entries) =>
        entries.Select(item => NutritionEntryInput.Create(
            item.EntryId,
            ParseMeal(item.Meal),
            item.Position,
            item.ProductName,
            item.AmountGrams,
            new NutritionPer100Grams(
                item.KilocaloriesPer100Grams,
                item.ProteinGramsPer100Grams,
                item.CarbohydrateGramsPer100Grams,
                item.FatGramsPer100Grams,
                item.SaltGramsPer100Grams,
                item.FiberGramsPer100Grams),
            item.Brand,
            item.Source,
            NutritionPortion.From(item.PieceGrams, item.PieceCount))).ToArray();

    private static NutritionDayKind? ParseDayKind(string? value) =>
        value is null
            ? null
            : Enum.TryParse(value, ignoreCase: true, out NutritionDayKind kind) && Enum.IsDefined(kind)
                ? kind
                : throw new SyncMutationValidationException(InvalidPayloadCode, "The day kind is invalid.");

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
    private sealed record CreateExerciseCategoryPayload(Guid CategoryId, string Name);
    private sealed record UpdateExerciseCategoryPayload(Guid CategoryId, long BaseVersion, string Name);
    private sealed record ArchiveExerciseCategoryPayload(Guid CategoryId, long BaseVersion);
    private sealed record MergeExercisesPayload(Guid SourceExerciseId, long SourceBaseVersion, Guid TargetExerciseId);
    private sealed record ActivateBodyGoalPayload(
        Guid GoalId,
        string Kind,
        decimal StartWeightKg,
        decimal TargetWeightKg,
        DateOnly StartDate,
        DateOnly? TargetDate,
        Guid? ExpectedActiveGoalId,
        long? ExpectedActiveGoalVersion);
    private sealed record CreateWorkoutPayload(WorkoutValues? Workout);
    private sealed record SaveWorkoutPayload(long BaseVersion, WorkoutValues? Workout);
    private sealed record DeleteWorkoutPayload(Guid WorkoutId, long BaseVersion);
    private sealed record SaveCardioSessionPayload(long BaseVersion, CardioSessionValues? Session);
    private sealed record DeleteCardioSessionPayload(Guid SessionId, long BaseVersion);
    private sealed record CreateTrainingPlanPayload(TrainingPlanValues? Plan);
    private sealed record UpdateTrainingPlanPayload(long BaseVersion, TrainingPlanValues? Plan);
    private sealed record ArchiveTrainingPlanPayload(Guid PlanId, long BaseVersion);
    private sealed record ReorderTrainingPlansPayload(IReadOnlyList<ReorderTrainingPlanItemPayload>? Plans);
    private sealed record ReorderTrainingPlanItemPayload(Guid PlanId, long BaseVersion);
    private sealed record SaveTrainingSchedulePayload(
        Guid ScheduleId,
        long BaseVersion,
        string? Mode,
        DateOnly? AnchorDate,
        DateOnly? ValidFrom,
        IReadOnlyList<TrainingScheduleSlotValues>? Slots,
        IReadOnlyList<TrainingScheduleShiftValues>? Shifts,
        IReadOnlyList<TrainingScheduleExceptionValues>? Exceptions)
    {
        public TrainingScheduleValues ToValues() =>
            new(ScheduleId, Mode ?? string.Empty, AnchorDate, ValidFrom!.Value, Slots!, Shifts!, Exceptions!);
    }
    private sealed record DeleteTrainingSchedulePayload(Guid ScheduleId, long BaseVersion);
    private sealed record SaveNutritionDayPayload(
        Guid NutritionDayId,
        DateOnly LocalDate,
        long BaseVersion,
        IReadOnlyList<NutritionEntryPayload> Entries,
        string? DayKind = null);
    private sealed record DeleteNutritionDayPayload(Guid NutritionDayId, long BaseVersion);
    private sealed record SaveNutritionDayTemplatePayload(
        Guid TemplateId,
        long BaseVersion,
        string Name,
        IReadOnlyList<NutritionEntryPayload>? Entries,
        string? DayKind = null);
    private sealed record DeleteNutritionDayTemplatePayload(Guid TemplateId, long BaseVersion);
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
        NutritionSourceSnapshot? Source,
        decimal? SaltGramsPer100Grams = null,
        decimal? PieceGrams = null,
        decimal? PieceCount = null,
        decimal? FiberGramsPer100Grams = null);
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
        string? Reason,
        decimal? SaltGrams = null,
        NutritionRestDayPayload? RestDay = null,
        decimal? FiberGrams = null);
    private sealed record NutritionRestDayPayload(
        string? InputMode,
        decimal Kilocalories,
        decimal ProteinGrams,
        decimal CarbohydrateGrams,
        decimal FatGrams,
        decimal? ProteinPercent,
        decimal? CarbohydratePercent,
        decimal? FatPercent);
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
        NutritionSourceSnapshot? Source,
        decimal? SaltGramsPer100Grams = null,
        decimal? PieceGrams = null,
        decimal? PieceCount = null,
        decimal? FiberGramsPer100Grams = null);
}
