import Foundation

/// Ereignis des Zonenalarms. Der Wert ist der zuletzt gemessene Puls.
enum CardioZoneEvent: Equatable {
  case tooHigh(bpm: Int)
  case tooLow(bpm: Int)
  case backInZone
  case signalLost
  /// Eine Phase der Vorlage beginnt. `index` zählt ab 0; Zone nur, wenn die Phase eine hat.
  case phaseStarted(
    index: Int, count: Int, name: String, durationSeconds: Int, zoneLowBpm: Int?, zoneHighBpm: Int?)
  /// Die letzte Phase ist abgelaufen; die Einheit läuft weiter.
  case templateFinished
}

/// Zustand für die Anzeige; die Rohwerte stehen so in `PlatformHeartRateStatus.zoneState`.
enum CardioZoneState: String, Equatable {
  case none
  case inZone
  case above
  case below
  case noSignal
}

/// Abschnitt einer Vorlage, relativ zum Start der Einheit.
struct CardioPhase: Equatable {
  var startOffsetSeconds: Int
  var durationSeconds: Int
  var name: String
  var zoneLowBpm: Int?
  var zoneHighBpm: Int?

  var endOffsetSeconds: Int { startOffsetSeconds + durationSeconds }

  var zone: ClosedRange<Int>? {
    guard let low = zoneLowBpm, let high = zoneHighBpm, low <= high else { return nil }
    return low...high
  }
}

struct CardioZoneAlarmConfig: Equatable {
  var zoneLowBpm: Int?
  var zoneHighBpm: Int?
  var graceSeconds: Int
  var repeatSeconds: Int
  var warmupSeconds: Int
  var startedAt: Date
  var alertsEnabled: Bool
  /// Leer ohne Vorlage; dann gilt immer die Zone der obersten Ebene.
  var phases: [CardioPhase] = []

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
  /// Index der laufenden Phase; nil vor der ersten, in Lücken und nach der letzten Phase.
  private(set) var currentPhaseIndex: Int?

  private var lastReading: (at: Date, bpm: Int)?
  /// Beginn der Überwachung bzw. der letzte Messwert dient als Bezug für den Signalverlust.
  private let monitoringStartedAt: Date
  private var outsideSince: Date?
  private var outsideState: CardioZoneState?
  private var lastAlertAt: Date?
  private var hasAlerted = false
  private var signalLostEmitted = false
  private var phaseTracked = false
  private var templateFinishedEmitted = false

  init(config: CardioZoneAlarmConfig, now: Date) {
    self.config = config
    self.monitoringStartedAt = now
  }

  /// Laufende Phase der aktuellen Konfiguration.
  var currentPhase: CardioPhase? {
    guard let index = currentPhaseIndex, config.phases.indices.contains(index) else { return nil }
    return config.phases[index]
  }

  /// Gültige Zone: die der laufenden Phase, sonst die der obersten Ebene.
  var activeZone: ClosedRange<Int>? {
    if let phase = currentPhase { return phase.zone }
    return config.zone
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
    let phaseEvents = evaluatePhase(now: now)
    return phaseEvents + evaluateZone(now: now)
  }

  /// Erkennt Phasenwechsel. Ein Wechsel setzt Abweichung und Karenzzeit zurück, damit
  /// die Karenz je Phase neu beginnt.
  private mutating func evaluatePhase(now: Date) -> [CardioZoneEvent] {
    let phases = config.phases
    guard !phases.isEmpty else {
      currentPhaseIndex = nil
      return []
    }
    let elapsed = now.timeIntervalSince(config.startedAt)
    let index = phases.firstIndex {
      elapsed >= TimeInterval($0.startOffsetSeconds) && elapsed < TimeInterval($0.endOffsetSeconds)
    }
    let isFirstEvaluation = !phaseTracked
    phaseTracked = true

    var events: [CardioZoneEvent] = []
    if index != currentPhaseIndex {
      currentPhaseIndex = index
      resetOutside()
      if let index {
        let phase = phases[index]
        events.append(
          .phaseStarted(
            index: index,
            count: phases.count,
            name: phase.name,
            durationSeconds: phase.durationSeconds,
            zoneLowBpm: phase.zone?.lowerBound,
            zoneHighBpm: phase.zone?.upperBound
          ))
      }
    }
    if let templateEnd = phases.map(\.endOffsetSeconds).max(), elapsed >= TimeInterval(templateEnd),
      !templateFinishedEmitted
    {
      templateFinishedEmitted = true
      // Nach einem Neustart weit hinter dem Ende wird nichts mehr angekündigt.
      if !isFirstEvaluation { events.append(.templateFinished) }
    }
    return events
  }

  private mutating func evaluateZone(now: Date) -> [CardioZoneEvent] {
    let reference = lastReading?.at ?? monitoringStartedAt
    guard let reading = lastReading, now.timeIntervalSince(reference) <= Self.signalTimeoutSeconds else {
      return evaluateNoSignal(now: now, reference: reference)
    }
    guard let zone = activeZone else {
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
      zoneState = activeZone == nil ? .none : .noSignal
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
