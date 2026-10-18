import ActivityKit
import Foundation

/// Entscheidet, wann die Live Activity aktualisiert wird: bei Wechsel des Zonenstatus
/// sofort, sonst höchstens alle `minimumInterval` Sekunden und nur bei geändertem Puls.
/// So bleibt das ActivityKit-Budget geschont. Rein und ohne ActivityKit testbar.
struct CardioLiveActivityThrottle {
  static let minimumInterval: TimeInterval = 5

  private var last: (zoneState: String, bpm: Int?, at: Date)?

  mutating func shouldPush(zoneState: String, bpm: Int?, now: Date) -> Bool {
    guard let last else {
      self.last = (zoneState, bpm, now)
      return true
    }
    let zoneChanged = last.zoneState != zoneState
    let bpmChanged = last.bpm != bpm
    let due = now.timeIntervalSince(last.at) >= Self.minimumInterval
    guard zoneChanged || (bpmChanged && due) else { return false }
    self.last = (zoneState, bpm, now)
    return true
  }

  mutating func reset() {
    last = nil
  }
}

/// Steuert die Cardio-Live-Activity. Wirft nie: Sind Live Activities aus oder schlägt
/// ActivityKit fehl, bleibt die Überwachung davon unberührt.
@available(iOS 17.0, *)
@MainActor
final class NativeCardioLiveActivity {
  private typealias Activity = ActivityKit.Activity<GainerCardioActivityAttributes>

  private var throttle = CardioLiveActivityThrottle()
  private var sessionId: String?

  /// Startet die Activity der Session oder aktualisiert eine vorhandene. Activities
  /// anderer Sessions werden vorher beendet.
  func start(sessionId: String, title: String, startedAt: Date, state: GainerCardioActivityAttributes.ContentState) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    self.sessionId = sessionId
    throttle.reset()
    await endActivities { $0.attributes.sessionId != sessionId }
    let content = ActivityContent(state: state, staleDate: nil)
    if let existing = Activity.activities.first(where: { $0.attributes.sessionId == sessionId }) {
      await existing.update(content)
    } else {
      let attributes = GainerCardioActivityAttributes(sessionId: sessionId, title: title, startedAt: startedAt)
      do {
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
      } catch {
        // Zu viele Activities oder vom Nutzer verboten: die Einheit läuft ohne weiter.
        return
      }
    }
    _ = throttle.shouldPush(zoneState: state.zoneState, bpm: state.bpm, now: state.updatedAt)
  }

  /// Aktualisiert die Activity, sofern der Drosselregler es zulässt.
  func update(state: GainerCardioActivityAttributes.ContentState) async {
    guard let sessionId,
      throttle.shouldPush(zoneState: state.zoneState, bpm: state.bpm, now: state.updatedAt),
      let activity = Activity.activities.first(where: { $0.attributes.sessionId == sessionId })
    else { return }
    await activity.update(ActivityContent(state: state, staleDate: nil))
  }

  func end() async {
    sessionId = nil
    throttle.reset()
    await endActivities { _ in true }
  }

  private func endActivities(where shouldEnd: (Activity) -> Bool) async {
    for activity in Activity.activities where shouldEnd(activity) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
