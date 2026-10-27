using Gainer.Core.Coach;
using Gainer.Core.Security;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Coach;

public sealed class CoachOptions
{
    public const string SectionName = "Coach";
    public int DailyRequestsPerUser { get; set; } = 100;
    public int MaximumConcurrentRequests { get; set; } = 4;
}

public interface ICoachQuota
{
    ValueTask<IAsyncDisposable> AcquireAsync(Guid userId, CancellationToken cancellationToken = default);
}

/// <summary>Reserves a coach slot for the authenticated user of the current request.</summary>
public interface ICoachRequestBudget
{
    ValueTask<IAsyncDisposable> AcquireAsync(CancellationToken cancellationToken = default);
}

public sealed class CoachRequestBudget(ICoachQuota quota, IUserContext userContext) : ICoachRequestBudget
{
    public ValueTask<IAsyncDisposable> AcquireAsync(CancellationToken cancellationToken = default)
    {
        Guid userId = userContext.UserId ?? throw new UnauthorizedAccessException("An authenticated user is required.");
        return quota.AcquireAsync(userId, cancellationToken);
    }
}

/// <summary>Daily budget and concurrency limit of the coach; one user request costs one slot, however many tool rounds it takes.</summary>
public sealed class CoachQuota(IOptions<CoachOptions> options, TimeProvider timeProvider)
    : ICoachQuota, IDisposable
{
    private readonly DailyRequestQuota quota = new(
        Validate(options.Value).DailyRequestsPerUser,
        options.Value.MaximumConcurrentRequests,
        timeProvider);

    public ValueTask<IAsyncDisposable> AcquireAsync(Guid userId, CancellationToken cancellationToken = default) =>
        quota.AcquireAsync(
            userId,
            () => new OpenAiProviderException("daily_budget_exhausted", "The daily AI budget for the coach is exhausted.", 429),
            cancellationToken);

    public void Dispose() => quota.Dispose();

    private static CoachOptions Validate(CoachOptions value)
    {
        if (value.DailyRequestsPerUser is < 1 or > 1_000)
            throw new InvalidOperationException("Coach daily request limit is invalid.");
        if (value.MaximumConcurrentRequests is < 1 or > 32)
            throw new InvalidOperationException("Coach concurrency limit is invalid.");
        return value;
    }
}
