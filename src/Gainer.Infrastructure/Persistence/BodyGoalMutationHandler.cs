using System.Data;
using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Values;
using Gainer.Core.Mutations;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace Gainer.Infrastructure.Persistence;

public sealed class BodyGoalMutationHandler(
    AppDbContext context,
    IUserContext userContext,
    TimeProvider timeProvider,
    IChangeCollector? changeCollector = null) : IBodyGoalMutationHandler
{
    public async Task<BodyGoalSnapshot> ActivateAsync(
        ActivateBodyGoalMutation mutation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(mutation);
        _ = userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        Validate(mutation);

        await using IDbContextTransaction? transaction = context.Database.CurrentTransaction is null
            ? await context.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken)
            : null;
        try
        {
            BodyGoal? active = await context.BodyGoals
                .SingleOrDefaultAsync(goal => goal.EndedAtUtc == null, cancellationToken);
            EnsureExpectedActiveGoal(mutation.ExpectedActiveGoal, active);

            DateTime utcNow = timeProvider.GetUtcNow().UtcDateTime;
            if (active is not null)
            {
                active.EndedAtUtc = utcNow;
                active.Version++;
            }

            var goal = new BodyGoal
            {
                Id = mutation.GoalId,
                Kind = mutation.Kind,
                StartWeightKg = mutation.StartWeightKg,
                TargetWeightKg = mutation.TargetWeightKg,
                StartDate = mutation.StartDate,
                TargetDate = mutation.TargetDate,
                CreatedAtUtc = utcNow,
                Version = 1,
            };
            context.BodyGoals.Add(goal);
            await context.SaveChangesAsync(cancellationToken);
            if (transaction is not null) await transaction.CommitAsync(cancellationToken);
            if (active is not null)
            {
                changeCollector?.CaptureUpsert(BodyTrackingSnapshots.Goal(active));
            }
            BodyGoalSnapshot snapshot = BodyTrackingSnapshots.Goal(goal);
            changeCollector?.CaptureUpsert(snapshot);
            return snapshot;
        }
        catch (DbUpdateException exception) when (
            context.IsKeyViolation<BodyGoal>(exception) ||
            context.IsUniqueIndexViolation<BodyGoal>(exception, nameof(BodyGoal.UserId)))
        {
            throw new BodyGoalConflictException("The active body goal changed concurrently.");
        }
        catch (Exception exception) when (IsConcurrencyConflict(exception))
        {
            throw new BodyGoalConflictException("The active body goal changed concurrently.");
        }
    }

    private static void Validate(ActivateBodyGoalMutation mutation)
    {
        var errors = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!Enum.IsDefined(mutation.Kind))
        {
            errors[nameof(mutation.Kind)] = "Goal kind must be Bulk, Maintain, or Cut.";
        }
        if (!Kilograms.TryCreate(mutation.StartWeightKg, out Kilograms startWeight) || !startWeight.IsPositive ||
            mutation.StartWeightKg > BodyTrackingLimits.MaxWeightKg)
        {
            errors[nameof(mutation.StartWeightKg)] = $"Start weight must be positive and at most {BodyTrackingLimits.MaxWeightKg} kg.";
        }
        if (!Kilograms.TryCreate(mutation.TargetWeightKg, out Kilograms targetWeight) || !targetWeight.IsPositive ||
            mutation.TargetWeightKg > BodyTrackingLimits.MaxWeightKg)
        {
            errors[nameof(mutation.TargetWeightKg)] = $"Target weight must be positive and at most {BodyTrackingLimits.MaxWeightKg} kg.";
        }
        if (mutation.TargetDate < mutation.StartDate)
        {
            errors[nameof(mutation.TargetDate)] = "Target date cannot precede the start date.";
        }
        if (mutation.ExpectedActiveGoal is { GoalId: var id } && id == Guid.Empty)
        {
            errors[nameof(mutation.ExpectedActiveGoal)] = "Expected active goal identifier cannot be empty.";
        }
        if (mutation.ExpectedActiveGoal is { Version: <= 0 })
        {
            errors[nameof(mutation.ExpectedActiveGoal)] = "Expected active goal version must be positive.";
        }
        if (errors.Count > 0)
        {
            throw new BodyGoalValidationException(errors);
        }
    }

    private static void EnsureExpectedActiveGoal(ActiveBodyGoalExpectation? expectation, BodyGoal? active)
    {
        bool matches = expectation switch
        {
            null => active is null,
            _ => active is not null && active.Id == expectation.GoalId && active.Version == expectation.Version,
        };
        if (!matches)
        {
            throw new BodyGoalConflictException("The expected active body goal does not match the current state.");
        }
    }

    private static bool IsConcurrencyConflict(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is PostgresException postgres && postgres.SqlState is
                PostgresErrorCodes.SerializationFailure or PostgresErrorCodes.DeadlockDetected)
                return true;
        }
        return false;
    }
}
