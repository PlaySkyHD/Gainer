namespace Gainer.Core.BodyTracking;

public interface IBodyTrackingQueries
{
    Task<BodyGoalSnapshot?> GetActiveGoalAsync(CancellationToken cancellationToken = default);

    Task<IReadOnlyList<BodyGoalSnapshot>> GetGoalHistoryAsync(CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyCheckInSnapshot>> GetCheckInsAsync(
        int offset,
        int limit,
        CancellationToken cancellationToken = default);
}
