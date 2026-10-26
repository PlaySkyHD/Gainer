using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using Gainer.Contracts.Sync;
using Gainer.Core.BodyTracking;
using Gainer.Core.Mutations;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Gainer.Core.Nutrition;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncMutationProcessor(
    AppDbContext context,
    IUserContext userContext,
    ISyncMutationExecutor executor,
    TimeProvider timeProvider,
    ILogger<SyncMutationProcessor>? logger = null) : ISyncMutationProcessor
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();
    private readonly ILogger log = logger ?? NullLogger<SyncMutationProcessor>.Instance;

    /// <summary>Operations of the rebuilt training contract and of the contract it replaces; older clients must upgrade before sending them.</summary>
    private static readonly HashSet<string> TrainingOperations = new(StringComparer.Ordinal)
    {
        "createWorkout", "saveWorkout", "deleteWorkout", "startWorkout", "editWorkout", "completeWorkout", "discardWorkout",
        "createTrainingPlan", "updateTrainingPlan", "archiveTrainingPlan", "reorderTrainingPlans",
        "saveWorkoutTemplate", "archiveWorkoutTemplate", "saveTrainingSchedule", "deleteTrainingSchedule",
        "createCustomExercise", "updateCustomExercise", "archiveCustomExercise",
        "createExerciseCategory", "updateExerciseCategory", "archiveExerciseCategory",
        "mergeExercises",
    };

    public async Task<ProcessedSyncMutationResult> ProcessAsync(
        ProcessSyncMutationCommand command,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);
        Guid userId = userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        ValidateCommand(command);
        byte[] hash = HashOrInvalid(command.Content);

        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);
        try
        {
            ProcessedMutation? existing = await context.ProcessedMutations.AsNoTracking()
                .SingleOrDefaultAsync(item => item.MutationId == command.MutationId, cancellationToken);
            if (existing is not null) return await ReplayAsync(command, existing, hash, transaction, cancellationToken);
            EnsureProtocolCoversMutation(command);

            SyncClient client = await context.SyncClients.SingleOrDefaultAsync(
                item => item.Id == command.Content.ClientId,
                cancellationToken) ?? throw new SyncMutationConflictException("client_not_registered", "The sync client is not registered.");
            UserSyncState state = await context.UserSyncStates
                .FromSqlInterpolated($"SELECT * FROM sync.user_state WHERE \"UserId\" = {userId} FOR UPDATE")
                .SingleAsync(cancellationToken);
            DateTime now = timeProvider.GetUtcNow().UtcDateTime;
            await EnsureNoHandoverInProgressAsync(userId, now, cancellationToken);
            if (state.ActiveClientId != client.Id)
            {
                throw new SyncMutationConflictException("inactive_client", "This client is not the active writing device.");
            }
            if (command.Content.DependsOnMutationId is { } dependency &&
                !await context.ProcessedMutations.AnyAsync(item => item.MutationId == dependency, cancellationToken))
            {
                throw new SyncMutationConflictException("dependency_not_applied", "The preceding mutation has not been applied.");
            }

            SyncMutationExecutionResult execution = await ExecuteDomainAsync(command, cancellationToken);
            if (execution.Changes.Count is < 1 or > 100)
            {
                throw new InvalidOperationException("A sync mutation must emit between one and 100 changes.");
            }
            long revision = checked(state.CurrentRevision + 1);
            state.CurrentRevision = revision;
            state.UpdatedAtUtc = now;
            state.Version++;
            client.LastSeenAtUtc = state.UpdatedAtUtc;

            Guid batchId = Guid.NewGuid();
            context.ChangeBatches.Add(new ChangeBatch
            {
                Id = batchId,
                Revision = revision,
                MutationId = command.MutationId,
                CreatedAtUtc = state.UpdatedAtUtc,
            });
            AddChangeItems(batchId, execution.Changes);
            var storedResult = new StoredMutationResult(revision, ToStoredChanges(execution.Changes));
            context.ProcessedMutations.Add(new ProcessedMutation
            {
                MutationId = command.MutationId,
                ClientId = client.Id,
                ClientSequence = command.Content.ClientSequence,
                ContentHash = hash,
                ResultJson = JsonSerializer.Serialize(storedResult, JsonOptions),
                Revision = revision,
                AppliedAtUtc = state.UpdatedAtUtc,
            });
            await context.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return new ProcessedSyncMutationResult(command.MutationId, false, revision, execution.Changes);
        }
        catch (ActiveWorkoutExistsException)
        {
            throw new SyncMutationConflictException("active_workout_exists", "The user already has an active workout.");
        }
        catch (Exception exception) when (exception is DailyCheckInConflictException or CustomExerciseConflictException or
            ExerciseCategoryConflictException or
            BodyGoalConflictException or TrainingPlanConflictException or TrainingScheduleConflictException or WorkoutConflictException or
            NutritionDayConflictException or NutritionDayTemplateConflictException or ReusableMealConflictException or NutritionTargetScheduleConflictException or
            CardioSessionConflictException or WaterIntakeConflictException)
        {
            throw new SyncMutationConflictException("stale_base_version", "The resource changed since the supplied base version.");
        }
        catch (Exception exception) when (exception is DailyCheckInNotFoundException or CustomExerciseNotFoundException or
            ExerciseCategoryNotFoundException or
            TrainingPlanNotFoundException or TrainingScheduleNotFoundException or WorkoutNotFoundException or NutritionDayNotFoundException or
            NutritionDayTemplateNotFoundException or ReusableMealNotFoundException or NutritionTargetScheduleNotFoundException or CardioSessionNotFoundException or
            WaterIntakeNotFoundException)
        {
            throw new SyncMutationConflictException("resource_not_found", "The resource is no longer available.");
        }
        catch (NutritionValidationException)
        {
            throw new SyncMutationValidationException("invalid_payload", "The nutrition payload is invalid.");
        }
        catch (WaterIntakeDayExistsException)
        {
            throw new SyncMutationValidationException(
                "water_day_exists",
                "Another water intake id already holds this local date.");
        }
        catch (Exception exception) when (IsRetryableConcurrency(exception))
        {
            throw new SyncMutationConflictException("concurrent_mutation", "Another mutation advanced the user state concurrently.");
        }
        catch (DbUpdateException exception) when (IsClientSequenceReuse(exception))
        {
            // Another mutation id already holds this client sequence (e.g. a reset sequence counter). Resending fails
            // the same way on every retry, so it is a permanent envelope error, not a concurrent mutation.
            log.LogWarning(
                "Sync mutation rejected: client sequence already used (SqlState {SqlState}, constraint {Constraint}).",
                PersistenceErrors.FindPostgres(exception)?.SqlState,
                PersistenceErrors.FindPostgres(exception)?.ConstraintName);
            throw new SyncMutationValidationException(
                "invalid_envelope",
                "The client sequence was already used by another mutation.",
                exception);
        }
    }

    /// <summary>
    /// Runs the domain handler. Every handler saves its own changes, so a database error raised here comes from the
    /// domain tables, while the sync tables are written afterwards. Integrity violations (class 23) and data
    /// exceptions such as numeric overflow (class 22) that the handler did not classify as a stored stand fail the
    /// same way on every retry: they become a permanent invalid payload. The phase decides instead of the schema of
    /// the error, because data exceptions carry no schema or table name.
    /// </summary>
    private async Task<SyncMutationExecutionResult> ExecuteDomainAsync(
        ProcessSyncMutationCommand command,
        CancellationToken cancellationToken)
    {
        try
        {
            return await executor.ExecuteAsync(command.MutationId, command.Content, cancellationToken);
        }
        catch (DbUpdateException exception) when (
            PersistenceErrors.FindPostgres(exception) is { SqlState: { } state } &&
            (state.StartsWith("23", StringComparison.Ordinal) || state.StartsWith("22", StringComparison.Ordinal)))
        {
            PostgresException postgres = PersistenceErrors.FindPostgres(exception)!;
            // Identifiers of the violated rule only: the message and detail texts can quote stored or sent values.
            log.LogWarning(
                "Sync mutation {Operation} rejected by the database: SqlState {SqlState}, constraint {Constraint}, table {Schema}.{Table}, column {Column}.",
                command.Content.Operation,
                postgres.SqlState,
                postgres.ConstraintName,
                postgres.SchemaName,
                postgres.TableName,
                postgres.ColumnName);
            throw new SyncMutationValidationException(
                "invalid_payload",
                "The mutation payload conflicts with stored data.",
                exception);
        }
        catch (SyncMutationValidationException exception) when (exception.InnerException is JsonException json)
        {
            // The path names the field only; the serializer message could quote payload values.
            log.LogWarning(
                "Sync mutation {Operation} has an invalid payload at {JsonPath}.",
                command.Content.Operation,
                json.Path);
            throw;
        }
    }

    private byte[] HashOrInvalid(CanonicalMutationContent content)
    {
        try
        {
            return CanonicalMutationHasher.Hash(content);
        }
        catch (InvalidOperationException exception)
        {
            // Missing payload, duplicate keys or numbers outside the decimal range cannot be hashed canonically. The
            // hasher's messages name the rule without quoting payload values; the operation is not validated yet and
            // stays out of the log.
            log.LogWarning("Sync mutation payload cannot be hashed canonically: {Reason}", exception.Message);
            throw new SyncMutationValidationException("invalid_payload", "The mutation payload is invalid.", exception);
        }
    }

    private async Task EnsureNoHandoverInProgressAsync(Guid userId, DateTime now, CancellationToken cancellationToken)
    {
        List<SyncHandover> expiredHandovers = await context.SyncHandovers
            .Where(item => item.UserId == userId
                && item.Status == SyncHandoverStatuses.Pending
                && item.ExpiresAtUtc <= now)
            .ToListAsync(cancellationToken);
        foreach (SyncHandover expired in expiredHandovers)
        {
            expired.Status = SyncHandoverStatuses.Expired;
            expired.ProtectedCode = null;
        }
        if (await context.SyncHandovers.AnyAsync(
                item => item.UserId == userId
                    && item.Status == SyncHandoverStatuses.Pending
                    && item.ExpiresAtUtc > now,
                cancellationToken))
        {
            throw new SyncMutationConflictException(
                "handover_in_progress",
                "Writes are paused while a device handover is in progress.");
        }
    }

    private void AddChangeItems(Guid batchId, IReadOnlyList<ExecutedSyncChange> changes)
    {
        for (int position = 0; position < changes.Count; position++)
        {
            ExecutedSyncChange change = changes[position];
            context.ChangeItems.Add(new ChangeItem
            {
                Id = Guid.NewGuid(),
                BatchId = batchId,
                Position = position,
                ResourceType = change.Resource.Kind.ToString(),
                ResourceId = change.Resource.ResourceId,
                ResourceVersion = change.Version,
                IsTombstone = change.IsTombstone,
                SnapshotJson = change.IsTombstone ? null : JsonSerializer.Serialize(change.Snapshot, JsonOptions),
            });
        }
    }

    private static List<StoredChange> ToStoredChanges(IReadOnlyList<ExecutedSyncChange> changes) =>
        changes.Select(change => new StoredChange(
            change.Resource.Kind.ToString(),
            change.Resource.ResourceId,
            change.Version,
            change.IsTombstone ? null : JsonSerializer.SerializeToElement(change.Snapshot, JsonOptions),
            change.IsTombstone)).ToList();

    private static async Task<ProcessedSyncMutationResult> ReplayAsync(
        ProcessSyncMutationCommand command,
        ProcessedMutation existing,
        byte[] hash,
        IDbContextTransaction transaction,
        CancellationToken cancellationToken)
    {
        if (!CryptographicOperations.FixedTimeEquals(existing.ContentHash, hash))
        {
            throw new SyncMutationConflictException(
                "mutation_id_reused",
                "The mutation id was already used with different content.");
        }
        StoredMutationResult stored = JsonSerializer.Deserialize<StoredMutationResult>(existing.ResultJson, JsonOptions)
            ?? throw new InvalidOperationException("The stored mutation receipt is invalid.");
        await transaction.RollbackAsync(cancellationToken);
        return new ProcessedSyncMutationResult(
            command.MutationId, true, stored.Revision,
            stored.Changes.Select(change => new ExecutedSyncChange(
                ResourceKey.Create(StoredResourceKind(change.ResourceType), change.ResourceId),
                change.Version,
                change.Snapshot,
                change.IsTombstone)).ToList());
    }

    /// <summary>Receipts of removed resource types (such as the workout rotation) are rejected like their operation.</summary>
    private static ResourceKind StoredResourceKind(string resourceType) =>
        Enum.TryParse(resourceType, ignoreCase: false, out ResourceKind kind) && Enum.IsDefined(kind) &&
        string.Equals(kind.ToString(), resourceType, StringComparison.Ordinal)
            ? kind
            : throw new SyncMutationValidationException("unsupported_operation", "The mutation operation is not supported.");

    private static void ValidateCommand(ProcessSyncMutationCommand command)
    {
        if (command.Content.Resources is null || command.Content.Resources.Any(item => item is null))
        {
            throw new SyncMutationValidationException("invalid_resources", "The mutation resource expectations are invalid.");
        }
        if (command.MutationId == Guid.Empty || command.Content.ClientId == Guid.Empty ||
            command.Content.ClientSequence <= 0 || string.IsNullOrWhiteSpace(command.Content.Operation))
        {
            throw new SyncMutationValidationException("invalid_envelope", "The mutation envelope is invalid.");
        }
        if (command.Content.ProtocolVersion is < SyncProtocol.PreviousVersion or > SyncProtocol.CurrentVersion)
        {
            throw new SyncUpgradeRequiredException();
        }
        if (command.Content.Resources.Count is < 1 or > SyncProtocol.MaximumResourcesPerMutation ||
            command.Content.Resources.Any(item => item.ResourceId == Guid.Empty || item.BaseVersion < 0 || string.IsNullOrWhiteSpace(item.ResourceType)))
        {
            throw new SyncMutationValidationException("invalid_resources", "The mutation resource expectations are invalid.");
        }
    }

    /// <summary>
    /// Rejects a new mutation whose resources or operation its protocol does not cover. Runs after the receipt
    /// lookup: a retry of a mutation that was applied before a type got its minimum protocol must still get its
    /// receipt, or the updated app would resend the id with another protocol and hit <c>mutation_id_reused</c>.
    /// The operation check stays next to the resource check because it does not depend on the declared resources
    /// and also covers operations of removed types.
    /// </summary>
    private static void EnsureProtocolCoversMutation(ProcessSyncMutationCommand command)
    {
        int protocol = command.Content.ProtocolVersion;
        if (command.Content.Resources.Any(item => !SyncResourceProtocol.Supports(protocol, item.ResourceType)) ||
            (protocol < SyncProtocol.TrainingContractVersion && TrainingOperations.Contains(command.Content.Operation)))
        {
            throw new SyncUpgradeRequiredException();
        }
    }

    /// <summary>
    /// Serialization failures and deadlocks resolve on retry. A unique violation only does so where a parallel request
    /// won a real race: the same mutation id (receipt key or its batch) or the same revision. Every other unique
    /// violation stays on every retry. Rejections this processor already classified are never retried.
    /// </summary>
    private bool IsRetryableConcurrency(Exception exception) =>
        exception is not SyncMutationException &&
        PersistenceErrors.FindPostgres(exception) is { } postgres && (
            postgres.SqlState is PostgresErrorCodes.SerializationFailure or PostgresErrorCodes.DeadlockDetected ||
            context.IsKeyViolation<ProcessedMutation>(exception) ||
            context.IsUniqueIndexViolation<ChangeBatch>(exception, nameof(ChangeBatch.UserId), nameof(ChangeBatch.Revision)) ||
            context.IsUniqueIndexViolation<ChangeBatch>(exception, nameof(ChangeBatch.UserId), nameof(ChangeBatch.MutationId)));

    /// <summary>The unique index on user, client and client sequence of the mutation receipts.</summary>
    private bool IsClientSequenceReuse(DbUpdateException exception) =>
        context.IsUniqueIndexViolation<ProcessedMutation>(
            exception,
            nameof(ProcessedMutation.UserId),
            nameof(ProcessedMutation.ClientId),
            nameof(ProcessedMutation.ClientSequence));

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }

    private sealed record StoredMutationResult(long Revision, IReadOnlyList<StoredChange> Changes);
    private sealed record StoredChange(
        string ResourceType,
        Guid ResourceId,
        long Version,
        JsonElement? Snapshot,
        bool IsTombstone);
}
