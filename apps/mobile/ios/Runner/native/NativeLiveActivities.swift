import ActivityKit
import Foundation

@available(iOS 17.0, *)
@MainActor
final class NativeLiveActivities {
  private let now: () -> Date

  init(now: @escaping () -> Date = Date.init) {
    self.now = now
  }

  func start(
    sessionId: String,
    status: String,
    startedAtUtcEpochMilliseconds: Int64,
    restEndsAtUtcEpochMilliseconds: Int64?,
    staleAtUtcEpochMilliseconds: Int64
  ) async throws -> Bool {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let state = Self.makeState(
        status: status,
        startedAtUtcEpochMilliseconds: startedAtUtcEpochMilliseconds,
        restEndsAtUtcEpochMilliseconds: restEndsAtUtcEpochMilliseconds,
        staleAtUtcEpochMilliseconds: staleAtUtcEpochMilliseconds,
        now: now()
      ),
      let attributes = Self.makeAttributes(sessionId: sessionId)
    else { return false }

    let content = ActivityContent(state: state.state, staleDate: state.staleAt)

    if let activity = Activity<GainerWorkoutActivityAttributes>.activities.first(where: {
      $0.attributes.sessionId == attributes.sessionId
    }) {
      await activity.update(content)
      return true
    }

    _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    return true
  }

  func update(
    sessionId: String,
    status: String,
    startedAtUtcEpochMilliseconds: Int64,
    restEndsAtUtcEpochMilliseconds: Int64?,
    staleAtUtcEpochMilliseconds: Int64
  ) async throws -> Bool {
    guard let attributes = Self.makeAttributes(sessionId: sessionId),
      let state = Self.makeState(
      status: status,
      startedAtUtcEpochMilliseconds: startedAtUtcEpochMilliseconds,
      restEndsAtUtcEpochMilliseconds: restEndsAtUtcEpochMilliseconds,
      staleAtUtcEpochMilliseconds: staleAtUtcEpochMilliseconds,
      now: now()
    ) else { return false }

    guard let activity = Activity<GainerWorkoutActivityAttributes>.activities.first(where: {
      $0.attributes.sessionId == attributes.sessionId
    }) else { return false }

    await activity.update(ActivityContent(state: state.state, staleDate: state.staleAt))
    return true
  }

  func end(sessionId: String) async {
    guard let attributes = Self.makeAttributes(sessionId: sessionId) else { return }
    let activities = Activity<GainerWorkoutActivityAttributes>.activities.filter {
      $0.attributes.sessionId == attributes.sessionId
    }
    for activity in activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  func endAll() async {
    for activity in Activity<GainerWorkoutActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  func reconcileStaleActivities() async {
    let instant = now()
    for activity in Activity<GainerWorkoutActivityAttributes>.activities {
      guard let staleDate = activity.content.staleDate, staleDate <= instant else { continue }
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private static func makeAttributes(sessionId: String) -> GainerWorkoutActivityAttributes? {
    guard UUID(uuidString: sessionId) != nil else { return nil }
    return GainerWorkoutActivityAttributes(sessionId: sessionId.lowercased())
  }

  private static func makeState(
    status: String,
    startedAtUtcEpochMilliseconds: Int64,
    restEndsAtUtcEpochMilliseconds: Int64?,
    staleAtUtcEpochMilliseconds: Int64,
    now: Date
  ) -> (state: GainerWorkoutActivityAttributes.ContentState, staleAt: Date)? {
    guard status == "workout" || status == "rest",
      startedAtUtcEpochMilliseconds > 0,
      startedAtUtcEpochMilliseconds <= Int64(now.addingTimeInterval(300).timeIntervalSince1970 * 1000),
      staleAtUtcEpochMilliseconds > Int64(now.timeIntervalSince1970 * 1000),
      staleAtUtcEpochMilliseconds > startedAtUtcEpochMilliseconds,
      staleAtUtcEpochMilliseconds <= Int64(now.addingTimeInterval(24 * 60 * 60).timeIntervalSince1970 * 1000)
    else { return nil }

    let restEnd = restEndsAtUtcEpochMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    if status == "rest" {
      guard let restEnd, restEnd > now,
        restEnd <= now.addingTimeInterval(24 * 60 * 60)
      else { return nil }
    } else if restEnd != nil {
      return nil
    }

    return (
      GainerWorkoutActivityAttributes.ContentState(
        status: status,
        startedAt: Date(timeIntervalSince1970: Double(startedAtUtcEpochMilliseconds) / 1000),
        restEndsAt: restEnd
      ),
      Date(timeIntervalSince1970: Double(staleAtUtcEpochMilliseconds) / 1000)
    )
  }
}
