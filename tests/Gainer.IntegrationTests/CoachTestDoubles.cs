using Gainer.Core.Security;
using Gainer.Infrastructure.Coach;

namespace Gainer.IntegrationTests;

internal sealed record CoachTestUser(Guid? UserId) : IUserContext
{
    public CoachTestUser() : this(Guid.NewGuid())
    {
    }
}

internal static class CoachTestBudget
{
    public static CoachRequestBudget Pass(Guid? userId = null) =>
        new(new PassCoachQuota(), new CoachTestUser(userId ?? Guid.NewGuid()));
}

internal sealed class PassCoachQuota : ICoachQuota
{
    public ValueTask<IAsyncDisposable> AcquireAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ValueTask.FromResult<IAsyncDisposable>(new Lease());

    private sealed class Lease : IAsyncDisposable
    {
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}
