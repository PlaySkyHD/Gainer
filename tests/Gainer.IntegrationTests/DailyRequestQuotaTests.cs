using Gainer.Infrastructure.Coach;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class DailyRequestQuotaTests
{
    [TestMethod]
    public async Task TheDailyBudgetResetsAtLocalMidnight()
    {
        var time = new MutableTimeProvider(new DateTimeOffset(2026, 8, 17, 21, 30, 0, TimeSpan.Zero));
        using var quota = new DailyRequestQuota(1, 1, time);
        Guid user = Guid.NewGuid();

        // 23:30 on 17 August in Berlin (CEST): the budget is used up afterwards.
        await (await quota.AcquireAsync(user, () => new InvalidOperationException(), TestContext.CancellationToken)).DisposeAsync();
        await Assert.ThrowsAsync<InvalidOperationException>(async () =>
            await quota.AcquireAsync(user, () => new InvalidOperationException(), TestContext.CancellationToken));

        // 00:30 on 18 August in Berlin is still 17 August in UTC, but a new local day.
        time.Now = new DateTimeOffset(2026, 8, 17, 22, 30, 0, TimeSpan.Zero);
        await (await quota.AcquireAsync(user, () => new InvalidOperationException(), TestContext.CancellationToken)).DisposeAsync();
    }

    private sealed class MutableTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    public TestContext TestContext { get; set; } = null!;
}
