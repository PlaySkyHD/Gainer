import Foundation
import UserNotifications

/// Text und Ton einer Cardio-Benachrichtigung, rein und ohne UserNotifications-Zugriff.
struct CardioAlertMessage: Equatable {
  /// Art der Meldung; Teil der Kennung, damit eine neue Meldung die alte ersetzt.
  let kind: String
  let title: String
  let body: String
  let playsSound: Bool

  static func make(for event: CardioZoneEvent, zoneLowBpm: Int?, zoneHighBpm: Int?) -> CardioAlertMessage {
    let target: String
    if let low = zoneLowBpm, let high = zoneHighBpm {
      target = "Ziel \(low)–\(high)"
    } else {
      target = ""
    }
    switch event {
    case .tooHigh(let bpm):
      return CardioAlertMessage(
        kind: "zone", title: "Puls zu hoch", body: bodyText(bpm: bpm, target: target), playsSound: true)
    case .tooLow(let bpm):
      return CardioAlertMessage(
        kind: "zone", title: "Puls zu niedrig", body: bodyText(bpm: bpm, target: target), playsSound: true)
    case .backInZone:
      return CardioAlertMessage(
        kind: "zone", title: "Wieder im Zielbereich", body: target, playsSound: false)
    case .signalLost:
      return CardioAlertMessage(
        kind: "signal", title: "Kein Pulssignal", body: "Prüfe den Sitz des Gurts.", playsSound: true)
    case .phaseStarted(let index, let count, let name, let durationSeconds, let low, let high):
      let title = "Phase \(index + 1)/\(count) · \(name) \(clockText(seconds: durationSeconds))"
      var phaseTarget = ""
      if let low, let high { phaseTarget = "Ziel \(low)–\(high)" }
      return CardioAlertMessage(kind: "phase", title: title, body: phaseTarget, playsSound: true)
    case .templateFinished:
      return CardioAlertMessage(
        kind: "phase", title: "Vorlage beendet", body: "Du kannst beenden oder weiterfahren.",
        playsSound: true)
    }
  }

  /// Dauer als Minuten und Sekunden, z. B. 240 -> „4:00“.
  static func clockText(seconds: Int) -> String {
    let clamped = max(seconds, 0)
    return String(format: "%d:%02d", clamped / 60, clamped % 60)
  }

  private static func bodyText(bpm: Int, target: String) -> String {
    target.isEmpty ? "\(bpm) bpm" : "\(bpm) bpm – \(target)"
  }
}

/// Sofortige lokale Benachrichtigungen des Zonenalarms. Pro Art gibt es genau eine
/// Kennung, eine neue Meldung ersetzt die vorherige im Mitteilungszentrum.
@MainActor
final class NativeCardioAlerts {
  nonisolated static let identifierPrefix = "com.gainer.mobile.cardio."

  private let notificationCenter: LocalNotificationCenter
  private let sounds: NativeTimerSounds

  init(
    notificationCenter: LocalNotificationCenter? = nil,
    sounds: NativeTimerSounds? = nil
  ) {
    // Im Initialisierer erzeugt, weil Standardargumente nicht auf dem Main Actor laufen.
    self.notificationCenter = notificationCenter ?? UNUserNotificationCenter.current()
    self.sounds = sounds ?? NativeTimerSounds()
  }

  nonisolated static func identifier(forKind kind: String) -> String {
    "\(identifierPrefix)\(kind)"
  }

  /// Zeigt die Meldung sofort. Fehlt die Berechtigung, bleibt der Aufruf wirkungslos.
  ///
  /// Bei `silent` bleibt die Meldung ohne Ton, etwa weil eine Sprachansage läuft.
  func post(
    event: CardioZoneEvent, zoneLowBpm: Int?, zoneHighBpm: Int?, soundId: String, silent: Bool = false
  ) async {
    let message = CardioAlertMessage.make(for: event, zoneLowBpm: zoneLowBpm, zoneHighBpm: zoneHighBpm)
    let content = UNMutableNotificationContent()
    content.title = message.title
    content.body = message.body
    if message.playsSound && !silent {
      content.sound = sounds.notificationSound(forSoundId: soundId)
    }
    let identifier = Self.identifier(forKind: message.kind)
    // Dieselbe Kennung ersetzt die vorherige Meldung dieser Art.
    notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    try? await notificationCenter.add(request)
  }

  /// Entfernt alle gelieferten Cardio-Meldungen, etwa nach dem Ende der Einheit.
  func clearDelivered() async {
    let delivered = await notificationCenter.deliveredNotificationIdentifiers()
    let identifiers = delivered.filter { $0.hasPrefix(Self.identifierPrefix) }
    notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}
