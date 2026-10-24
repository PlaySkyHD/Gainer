using Gainer.Core.Coach;

namespace Gainer.IntegrationTests;

/// <summary>Coach memory with a fixed list of entries (newest first) for CoachService tests.</summary>
internal sealed class FixedCoachMemories(params CoachMemoryItem[] items) : ICoachMemoryQueries
{
    public Task<IReadOnlyList<CoachMemoryItem>> ListAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<CoachMemoryItem>>(items);
}
