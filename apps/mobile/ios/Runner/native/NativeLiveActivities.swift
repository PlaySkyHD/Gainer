import ActivityKit
import Foundation

@available(iOS 17.0, *)
@MainActor
final class NativeLiveActivities {
  private typealias Activity = ActivityKit.Activity<GainerWorkoutActivityAttributes>

  private static let maximumRestSeconds = 30 * 60
  private static let maximumValidity: TimeInterval = 24 * 60 * 60

  private let now: () -> Date

  init(now: @escaping () -> Date = Date.init) {
    self.now = now
  }

  /// Startet die Activity des Trainings oder aktualisiert sie. Activities anderer
  /// Trainings oder Konten werden vorher beendet, damit höchstens eine übrig bleibt.
  func start(_ request: PlatformLiveActivityState) async throws -> Bool {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let attributes = Self.makeAttributes(sessionId: request.sessionId),
      let content = Self.makeContent(request, now: now())
    else { return false }

    await endActivities { $0.attributes.sessionId != attributes.sessionId }

    if let activity = Self.activity(sessionId: attributes.sessionId) {
      await activity.update(content)
      return true
    }

    _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
    return true
  }

  func update(_ request: PlatformLiveActivityState) async throws -> Bool {
    guard let attributes = Self.makeAttributes(sessionId: request.sessionId),
      let content = Self.makeContent(request, now: now()),
      let activity = Self.activity(sessionId: attributes.sessionId)
    else { return false }

    await activity.update(content)
    return true
  }

  func end(sessionId: String) async {
    guard let attributes = Self.makeAttributes(sessionId: sessionId) else { return }
    await endActivities { $0.attributes.sessionId == attributes.sessionId }
  }

  func endAll() async {
    await endActivities { _ in true }
  }

  /// Beendet Activities, deren Gültigkeit abgelaufen ist, etwa nach einem Prozessende.
  func reconcileStaleActivities() async {
    let instant = now()
    await endActivities { activity in
      guard let staleDate = activity.content.staleDate else { return false }
      return staleDate <= instant
    }
  }

  private func endActivities(where shouldEnd: (Activity) -> Bool) async {
    for activity in Activity.activities where shouldEnd(activity) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private static func activity(sessionId: String) -> Activity? {
    Activity.activities.first { $0.attributes.sessionId == sessionId }
  }

  private static func makeAttributes(sessionId: String) -> GainerWorkoutActivityAttributes? {
    guard UUID(uuidString: sessionId) != nil else { return nil }
    return GainerWorkoutActivityAttributes(sessionId: sessionId.lowercased())
  }

  /// Prüft den Zustand aus dem Dart-Aufruf. Ungültige Werte liefern nil, damit
  /// die Anzeige nie aus unplausiblen Zeiten entsteht.
  private static func makeContent(
    _ request: PlatformLiveActivityState,
    now: Date
  ) -> ActivityContent<GainerWorkoutActivityAttributes.ContentState>? {
    let horizon = now.addingTimeInterval(maximumValidity)
    let startedAt = Date(timeIntervalSince1970: Double(request.startedAtUtcEpochMilliseconds) / 1000)
    let staleAt = Date(timeIntervalSince1970: Double(request.staleAtUtcEpochMilliseconds) / 1000)
    guard request.startedAtUtcEpochMilliseconds > 0,
      startedAt <= now.addingTimeInterval(300),
      staleAt > now,
      staleAt > startedAt,
      staleAt <= horizon
    else { return nil }

    let timerTargetAt = request.timerTargetAtUtcEpochMilliseconds.map {
      Date(timeIntervalSince1970: Double($0) / 1000)
    }
    let pausedRemaining = request.pausedRemainingSeconds.map { Int($0) }
    let targetIsValid = timerTargetAt.map { $0 > now && $0 <= horizon } ?? false
    let remainingIsValid = pausedRemaining.map { (0...maximumRestSeconds).contains($0) } ?? false

    let phaseIsValid: Bool
    switch request.timerPhase {
    case "running":
      phaseIsValid = targetIsValid && pausedRemaining == nil
    case "paused":
      phaseIsValid = timerTargetAt == nil && remainingIsValid
    case "ready", "expired":
      phaseIsValid = timerTargetAt == nil && pausedRemaining == nil
    default:
      phaseIsValid = false
    }
    guard phaseIsValid, request.expired == (request.timerPhase == "expired") else { return nil }

    let detail = request.detail.map {
      GainerWorkoutActivityAttributes.ContentState.Detail(
        title: $0.title,
        exerciseName: $0.exerciseName,
        setIndex: Int($0.setIndex),
        setCount: Int($0.setCount)
      )
    }
    let state = GainerWorkoutActivityAttributes.ContentState(
      startedAt: startedAt,
      timerPhase: request.timerPhase,
      timerTargetAt: timerTargetAt,
      pausedRemainingSeconds: pausedRemaining,
      expired: request.expired,
      detail: detail
    )
    return ActivityContent(state: state, staleDate: staleAt)
  }
}
