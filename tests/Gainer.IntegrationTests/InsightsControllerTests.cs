using Gainer.Api.Controllers;
using Gainer.Contracts.Insights;
using Gainer.Core.Insights;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class InsightsControllerTests
{
    public TestContext TestContext { get; set; } = null!;

    [TestMethod]
    public async Task DashboardDefaultsToTheLocalDayAroundMidnight()
    {
        var queries = new RecordingInsights();
        // 00:30 on 18 August in Berlin (CEST) is still 17 August in UTC.
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 17, 22, 30, 0, TimeSpan.Zero));
        var controller = new InsightsController(queries, time);

        ActionResult<DashboardInsightsResponse> result = await controller.Dashboard(
            cancellationToken: TestContext.CancellationToken);

        Assert.IsInstanceOfType<OkObjectResult>(result.Result);
        Assert.AreEqual(new DateOnly(2026, 8, 18), queries.Through);
    }

    [TestMethod]
    public async Task DashboardDefaultUsesTheRequestedTimeZone()
    {
        var queries = new RecordingInsights();
        var time = new FixedTimeProvider(new DateTimeOffset(2026, 8, 17, 22, 30, 0, TimeSpan.Zero));
        var controller = new InsightsController(queries, time);

        await controller.Dashboard(timeZone: "UTC", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(new DateOnly(2026, 8, 17), queries.Through);
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class RecordingInsights : IInsightQueries
    {
        public DateOnly? Through { get; private set; }

        public Task<DashboardInsightSnapshot> DashboardAsync(
            DateOnly through, int days, TimeZoneInfo timeZone, CancellationToken cancellationToken = default)
        {
            Through = through;
            DateOnly from = through.AddDays(1 - days);
            return Task.FromResult(new DashboardInsightSnapshot(
                1, from, through, null, null, [],
                InsightAlgorithms.Weight([], through.AddDays(-6), through),
                InsightAlgorithms.Weight([], from, through),
                InsightAlgorithms.Nutrition([], from, through),
                InsightAlgorithms.Training([], 0), 0));
        }

        public Task<ExerciseProgressSnapshot> ExerciseProgressAsync(
            Guid exerciseId, int? windowDays, DateTime throughUtc, TimeZoneInfo timeZone,
            CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }
}
