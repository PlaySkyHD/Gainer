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
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class SyncMutationProcessor(
    AppDbContext context,
    IUserContext userContext,
    ISyncMutationExecutor executor,
    TimeProvider timeProvider) : ISyncMutationProcessor
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    public async Task<ProcessedSyncMutationResult> ProcessAsync(
        ProcessSyncMutationCommand command,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(command);
        Guid userId = userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        ValidateCommand(command);
        byte[] hash = CanonicalMutationHasher.Hash(command.Content);

        await using var transaction = await context.Database.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);
        try
        {
            ProcessedMutation? existing = await context.ProcessedMutations.AsNoTracking()
                .SingleOrDefaultAsync(item => item.MutationId == command.MutationId, cancellationToken);
            if (existing is not null) return await ReplayAsync(command, existing, hash, transaction, cancellationToken);

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

            SyncMutationExecutionResult execution = await executor.ExecuteAsync(
                command.MutationId, command.Content, cancellationToken);
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
        catch (Exception exception) when (exception is DailyCheckInConflictException or CustomExerciseConflictException or
            BodyGoalConflictException or WorkoutTemplateConflictException or WorkoutRotationConflictException or WorkoutConflictException or
            NutritionDayConflictException or ReusableMealConflictException or NutritionTargetScheduleConflictException)
        {
            throw new SyncMutationConflictException("stale_base_version", "The resource changed since the supplied base version.");
        }
        catch (Exception exception) when (exception is DailyCheckInNotFoundException or CustomExerciseNotFoundException or
            WorkoutTemplateNotFoundException or WorkoutRotationNotFoundException or WorkoutNotFoundException or NutritionDayNotFoundException or
            ReusableMealNotFoundException or NutritionTargetScheduleNotFoundException)
        {
            throw new SyncMutationConflictException("resource_not_found", "The resource is no longer available.");
        }
        catch (NutritionValidationException)
        {
            throw new SyncMutationValidationException("invalid_payload", "The nutrition payload is invalid.");
        }
        catch (Exception exception) when (IsRetryableConcurrency(exception))
        {
            throw new SyncMutationConflictException("concurrent_mutation", "Another mutation advanced the user state concurrently.");
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
                ResourceKey.Create(Enum.Parse<ResourceKind>(change.ResourceType), change.ResourceId),
                change.Version,
                change.Snapshot,
                change.IsTombstone)).ToList());
    }

    private static void ValidateCommand(ProcessSyncMutationCommand command)
    {
        if (command.MutationId == Guid.Empty || command.Content.ClientId == Guid.Empty ||
            command.Content.ClientSequence <= 0 || string.IsNullOrWhiteSpace(command.Content.Operation))
        {
            throw new SyncMutationValidationException("invalid_envelope", "The mutation envelope is invalid.");
        }
        if (command.Content.ProtocolVersion is not (SyncProtocol.CurrentVersion or SyncProtocol.PreviousVersion))
        {
            throw new SyncUpgradeRequiredException();
        }
        if (command.Content.Resources.Count is < 1 or > SyncProtocol.MaximumResourcesPerMutation ||
            command.Content.Resources.Any(item => item.ResourceId == Guid.Empty || item.BaseVersion < 0 || string.IsNullOrWhiteSpace(item.ResourceType)))
        {
            throw new SyncMutationValidationException("invalid_resources", "The mutation resource expectations are invalid.");
        }
    }

    private static bool IsRetryableConcurrency(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres && postgres.SqlState is
                PostgresErrorCodes.UniqueViolation or PostgresErrorCodes.SerializationFailure or PostgresErrorCodes.DeadlockDetected)
                return true;
        }
        return false;
    }

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
