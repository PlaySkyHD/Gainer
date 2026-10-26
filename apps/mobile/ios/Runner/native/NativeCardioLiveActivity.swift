import ActivityKit
import Foundation

/// Entscheidet, wann die Live Activity aktualisiert wird: bei Wechsel des Zonenstatus
/// sofort, sonst höchstens alle `minimumInterval` Sekunden und nur bei geändertem Puls.
/// So bleibt das ActivityKit-Budget geschont. Rein und ohne ActivityKit testbar.
struct CardioLiveActivityThrottle {
  static let minimumInterval: TimeInterval = 5

  private var last: (zoneState: String, bpm: Int?, phaseIndex: Int?, at: Date)?

  /// Ein Wechsel von Zonenstatus oder Phase wird sofort übernommen.
  mutating func shouldPush(zoneState: String, bpm: Int?, phaseIndex: Int? = nil, now: Date) -> Bool {
    guard let last else {
      self.last = (zoneState, bpm, phaseIndex, now)
      return true
    }
    let zoneChanged = last.zoneState != zoneState || last.phaseIndex != phaseIndex
    let bpmChanged = last.bpm != bpm
    let due = now.timeIntervalSince(last.at) >= Self.minimumInterval
    guard zoneChanged || (bpmChanged && due) else { return false }
    self.last = (zoneState, bpm, phaseIndex, now)
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
    _ = throttle.shouldPush(
      zoneState: state.zoneState, bpm: state.bpm, phaseIndex: state.phaseIndex, now: state.updatedAt)
  }

  /// Zustand für den Status an Dart: `running`, `disabled` (in den iOS-Einstellungen aus)
  /// oder `missing` (erlaubt, aber keine Activity, etwa weil sie beim Start aus waren).
  func state(sessionId: String) -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "disabled" }
    let running = Activity.activities.contains { $0.attributes.sessionId == sessionId }
    return running ? "running" : "missing"
  }

  /// Aktualisiert die Activity, sofern der Drosselregler es zulässt.
  func update(state: GainerCardioActivityAttributes.ContentState) async {
    guard let sessionId,
      throttle.shouldPush(
        zoneState: state.zoneState, bpm: state.bpm, phaseIndex: state.phaseIndex, now: state.updatedAt),
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
