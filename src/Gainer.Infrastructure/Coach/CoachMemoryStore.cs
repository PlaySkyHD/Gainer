using Gainer.Core.Coach;
using Gainer.Core.Security;
using Gainer.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Gainer.Infrastructure.Coach;

/// <summary>Stores coach memory of the authenticated user; the query filter hides every other user.</summary>
public sealed class CoachMemoryStore(AppDbContext context, IUserContext userContext, TimeProvider timeProvider)
    : ICoachMemoryStore
{
    /// <summary>Second key of the per-user advisory lock, so it cannot collide with other lock users.</summary>
    private const int LockNamespace = 110;

    public async Task<IReadOnlyList<CoachMemoryItem>> ListAsync(CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        List<CoachMemory> entries = await context.CoachMemories.AsNoTracking()
            .OrderByDescending(item => item.CreatedAtUtc)
            .ThenBy(item => item.Id)
            .ToListAsync(cancellationToken);
        return entries.Select(ToItem).ToList();
    }

    public async Task<CoachMemoryCreateResult> CreateAsync(
        CoachMemoryCategory category, string text, CancellationToken cancellationToken = default)
    {
        string normalized = CoachMemoryRules.RequireValidText(text);
        RequireKnown(category);
        await using IDbContextTransaction transaction = await LockAsync(cancellationToken);
        List<CoachMemory> existing = await context.CoachMemories.ToListAsync(cancellationToken);
        string key = CoachMemoryRules.DuplicateKey(normalized);
        if (existing.FirstOrDefault(item => CoachMemoryRules.DuplicateKey(item.Text) == key) is { } duplicate)
        {
            // Same text, other category: the user's latest choice wins, the entry keeps its place.
            if (duplicate.Category != category)
            {
                duplicate.Category = category;
                Touch(duplicate);
                await context.SaveChangesAsync(cancellationToken);
            }
            await transaction.CommitAsync(cancellationToken);
            return new CoachMemoryCreateResult(ToItem(duplicate), Created: false);
        }
        if (existing.Count >= CoachMemoryRules.MaxEntriesPerUser)
        {
            throw new CoachMemoryException(CoachMemoryException.LimitReached, "The coach memory is full.");
        }
        DateTime now = timeProvider.GetUtcNow().UtcDateTime;
        var memory = new CoachMemory
        {
            Id = Guid.NewGuid(),
            Category = category,
            Text = normalized,
            CreatedAtUtc = now,
            UpdatedAtUtc = now,
            Version = 1,
        };
        context.CoachMemories.Add(memory);
        await context.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new CoachMemoryCreateResult(ToItem(memory), Created: true);
    }

    public async Task<CoachMemoryItem> UpdateAsync(
        Guid id,
        CoachMemoryCategory category,
        string text,
        long? baseVersion = null,
        CancellationToken cancellationToken = default)
    {
        string normalized = CoachMemoryRules.RequireValidText(text);
        RequireKnown(category);
        await using IDbContextTransaction transaction = await LockAsync(cancellationToken);
        List<CoachMemory> existing = await context.CoachMemories.ToListAsync(cancellationToken);
        CoachMemory memory = existing.SingleOrDefault(item => item.Id == id) ?? throw NotFound();
        if (baseVersion is { } expected && memory.Version != expected)
        {
            throw new CoachMemoryException(CoachMemoryException.Conflict, "The memory entry was changed in the meantime.");
        }
        string key = CoachMemoryRules.DuplicateKey(normalized);
        if (existing.Any(item => item.Id != id && CoachMemoryRules.DuplicateKey(item.Text) == key))
        {
            throw new CoachMemoryException(CoachMemoryException.Duplicate, "Another entry already has this text.");
        }
        if (memory.Category != category || memory.Text != normalized)
        {
            memory.Category = category;
            memory.Text = normalized;
            Touch(memory);
            await context.SaveChangesAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return ToItem(memory);
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        return await context.CoachMemories.Where(item => item.Id == id).ExecuteDeleteAsync(cancellationToken) > 0;
    }

    public async Task<int> DeleteAllAsync(CancellationToken cancellationToken = default)
    {
        _ = CurrentUserId();
        return await context.CoachMemories.ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>Serializes create and update per user so the limit and the duplicate check hold under double taps.</summary>
    private async Task<IDbContextTransaction> LockAsync(CancellationToken cancellationToken)
    {
        int userKey = CurrentUserId().GetHashCode();
        IDbContextTransaction transaction = await context.Database.BeginTransactionAsync(cancellationToken);
        await context.Database.ExecuteSqlInterpolatedAsync(
            $"SELECT pg_advisory_xact_lock({LockNamespace}, {userKey})", cancellationToken);
        return transaction;
    }

    private void Touch(CoachMemory memory)
    {
        memory.UpdatedAtUtc = timeProvider.GetUtcNow().UtcDateTime;
        memory.Version++;
    }

    private Guid CurrentUserId() => userContext.UserId ?? throw new UserIsolationViolationException();

    private static void RequireKnown(CoachMemoryCategory category)
    {
        if (!Enum.IsDefined(category))
            throw new CoachMemoryException(CoachMemoryException.Invalid, "The memory category is unknown.");
    }

    private static CoachMemoryException NotFound() =>
        new(CoachMemoryException.NotFound, "The memory entry does not exist.");

    private static CoachMemoryItem ToItem(CoachMemory memory) => new(
        memory.Id, memory.Category, memory.Text, memory.CreatedAtUtc, memory.UpdatedAtUtc, memory.Version);
}
