import Foundation

/// Ereignis des Zonenalarms. Der Wert ist der zuletzt gemessene Puls.
enum CardioZoneEvent: Equatable {
  case tooHigh(bpm: Int)
  case tooLow(bpm: Int)
  case backInZone
  case signalLost
}

/// Zustand für die Anzeige; die Rohwerte stehen so in `PlatformHeartRateStatus.zoneState`.
enum CardioZoneState: String, Equatable {
  case none
  case inZone
  case above
  case below
  case noSignal
}

struct CardioZoneAlarmConfig: Equatable {
  var zoneLowBpm: Int?
  var zoneHighBpm: Int?
  var graceSeconds: Int
  var repeatSeconds: Int
  var warmupSeconds: Int
  var startedAt: Date
  var alertsEnabled: Bool

  /// Beide Grenzen müssen gesetzt sein, sonst gibt es keine Zone.
  var zone: ClosedRange<Int>? {
    guard let low = zoneLowBpm, let high = zoneHighBpm, low <= high else { return nil }
    return low...high
  }
}

/// Reine, deterministische Zonenlogik (Design D4). Die Zeit kommt immer von außen,
/// damit sich jeder Ablauf ohne Uhr testen lässt.
///
/// - Außerhalb der Zone länger als `graceSeconds` (frühestens ab Ende der Aufwärmzeit)
///   ergibt einen Alarm; bleibt der Puls draußen, wiederholt er sich höchstens alle
///   `repeatSeconds`.
/// - Nach einem Alarm meldet die Rückkehr in die Zone einmal `.backInZone`.
/// - Ohne Messwert seit `signalTimeoutSeconds` folgt einmal `.signalLost`; der nächste
///   Messwert schaltet das wieder scharf.
struct CardioZoneAlarm {
  static let signalTimeoutSeconds: TimeInterval = 30

  private(set) var config: CardioZoneAlarmConfig
  private(set) var zoneState: CardioZoneState = .none

  private var lastReading: (at: Date, bpm: Int)?
  /// Beginn der Überwachung bzw. der letzte Messwert dient als Bezug für den Signalverlust.
  private let monitoringStartedAt: Date
  private var outsideSince: Date?
  private var outsideState: CardioZoneState?
  private var lastAlertAt: Date?
  private var hasAlerted = false
  private var signalLostEmitted = false

  init(config: CardioZoneAlarmConfig, now: Date) {
    self.config = config
    self.monitoringStartedAt = now
  }

  /// Neuer Messwert; wertet sofort aus.
  mutating func record(bpm: Int, at time: Date) -> [CardioZoneEvent] {
    lastReading = (time, bpm)
    signalLostEmitted = false
    return evaluate(now: time)
  }

  /// Zeitablauf ohne Messwert (Signalverlust) und Wiederholungen.
  mutating func tick(now: Date) -> [CardioZoneEvent] {
    evaluate(now: now)
  }

  /// Ändert Zone und Optionen, ohne die Sitzung zurückzusetzen.
  mutating func update(config newConfig: CardioZoneAlarmConfig, now: Date) -> [CardioZoneEvent] {
    config = newConfig
    return evaluate(now: now)
  }

  private mutating func evaluate(now: Date) -> [CardioZoneEvent] {
    let reference = lastReading?.at ?? monitoringStartedAt
    guard let reading = lastReading, now.timeIntervalSince(reference) <= Self.signalTimeoutSeconds else {
      return evaluateNoSignal(now: now, reference: reference)
    }
    guard let zone = config.zone else {
      zoneState = .none
      resetOutside()
      return []
    }

    let state: CardioZoneState
    if reading.bpm < zone.lowerBound {
      state = .below
    } else if reading.bpm > zone.upperBound {
      state = .above
    } else {
      state = .inZone
    }
    zoneState = state

    if state == .inZone {
      let wasAlerted = hasAlerted
      resetOutside()
      return wasAlerted && config.alertsEnabled ? [.backInZone] : []
    }

    if outsideState != state {
      outsideState = state
      outsideSince = now
      lastAlertAt = nil
    }
    guard config.alertsEnabled, let since = outsideSince else { return [] }
    let warmupEnd = config.startedAt.addingTimeInterval(TimeInterval(config.warmupSeconds))
    guard now >= warmupEnd else { return [] }
    // Die Karenzzeit zählt frühestens ab Ende der Aufwärmzeit.
    let countedSince = max(since, warmupEnd)
    guard now.timeIntervalSince(countedSince) > TimeInterval(config.graceSeconds) else { return [] }
    if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < TimeInterval(config.repeatSeconds) {
      return []
    }
    lastAlertAt = now
    hasAlerted = true
    return [state == .above ? .tooHigh(bpm: reading.bpm) : .tooLow(bpm: reading.bpm)]
  }

  private mutating func evaluateNoSignal(now: Date, reference: Date) -> [CardioZoneEvent] {
    if lastReading == nil && now.timeIntervalSince(reference) <= Self.signalTimeoutSeconds {
      // Noch kein Messwert, aber auch noch nicht lange genug gewartet.
      zoneState = config.zone == nil ? .none : .noSignal
      return []
    }
    zoneState = .noSignal
    resetOutside()
    guard !signalLostEmitted else { return [] }
    signalLostEmitted = true
    return config.alertsEnabled ? [.signalLost] : []
  }

  private mutating func resetOutside() {
    outsideSince = nil
    outsideState = nil
    lastAlertAt = nil
    hasAlerted = false
  }
}
