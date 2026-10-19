import CoreBluetooth
import Foundation

/// Reicht die CoreBluetooth-Rückrufe an den Monitor weiter. Der Central läuft auf der
/// Main Queue (`queue: nil`), die Rückrufe sind deshalb auf dem Main Actor.
private final class HeartRateCentralBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  weak var owner: NativeHeartRateMonitor?

  /// Die Rückrufe kommen auf der Main Queue; der Monitor ist an den Main Actor gebunden.
  private func onMain(_ body: @MainActor (NativeHeartRateMonitor) -> Void) {
    MainActor.assumeIsolated {
      if let owner { body(owner) }
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    onMain { $0.centralStateChanged() }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let signal = RSSI.intValue
    onMain { $0.didDiscover(peripheral, advertisementData: advertisementData, rssi: signal) }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    onMain { $0.didConnect(peripheral) }
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    onMain { $0.didFailToConnect(peripheral) }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    onMain { $0.didDisconnect(peripheral) }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let failed = error != nil
    onMain { $0.didDiscoverServices(peripheral, failed: failed) }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    let failed = error != nil
    onMain { $0.didDiscoverCharacteristics(peripheral, service: service, failed: failed) }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    let failed = error != nil
    onMain { $0.didUpdateValue(peripheral, characteristic: characteristic, failed: failed) }
  }
}

/// Pulsgurt über CoreBluetooth (Heart Rate Service 0x180D) mit nativem Puffer und
/// Zonenalarm (Design D3 und D4). Der Central entsteht erst bei der ersten Nutzung, damit
/// die Bluetooth-Berechtigung nicht beim Appstart abgefragt wird.
@MainActor
final class NativeHeartRateMonitor {
  static let heartRateService = CBUUID(string: "180D")
  static let heartRateMeasurement = CBUUID(string: "2A37")
  static let batteryService = CBUUID(string: "180F")
  static let batteryLevel = CBUUID(string: "2A19")
  nonisolated static let storedSensorKey = "com.gainer.mobile.cardio.sensorId"
  nonisolated static let tickIntervalSeconds: TimeInterval = 1
  nonisolated static let defaultSensorName = "Pulsgurt"

  private struct ScanEntry {
    var name: String
    var rssi: Int?
    var isConnected: Bool
  }

  private struct ActiveMonitoring {
    var config: PlatformCardioMonitoringConfig
    var alarm: CardioZoneAlarm
    var voiceSchedule: CardioVoiceSchedule
    var samples: [PlatformHeartRateSample] = []
    var sequence: Int64 = 0
  }

  private let defaults: UserDefaults
  private let alerts: NativeCardioAlerts
  private let liveActivity = NativeCardioLiveActivity()
  private let voice = NativeCardioVoice()
  private let bridge = HeartRateCentralBridge()

  private var central: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var knownPeripherals: [UUID: CBPeripheral] = [:]
  private var scanResults: [UUID: ScanEntry] = [:]
  private var scanGeneration = 0

  /// Gemerkte Gurt-ID; nicht nil heißt, dass bei jedem Abbruch neu verbunden wird.
  private var targetSensorId: String?
  private var connectionState = "idle"
  private var hasConnected = false
  private var batteryPercent: Int?
  private var latestBpm: Int?
  private var latestAtMilliseconds: Int64?

  private var monitoring: ActiveMonitoring?
  private var tickTimer: Timer?

  init(defaults: UserDefaults? = nil, alerts: NativeCardioAlerts? = nil) {
    // Im Initialisierer erzeugt, weil Standardargumente nicht auf dem Main Actor laufen.
    self.defaults = defaults ?? .standard
    self.alerts = alerts ?? NativeCardioAlerts()
    self.targetSensorId = self.defaults.string(forKey: Self.storedSensorKey)
    bridge.owner = self
  }

  // MARK: - Pigeon-Operationen

  /// Zustand und neue Messwerte. Legt den Central nur an, wenn ein Gurt gemerkt ist.
  func status(afterSequence: Int64) -> PlatformHeartRateStatus {
    if central == nil, targetSensorId != nil { ensureCentral() }
    evaluateAlarm(now: Date())

    var samples: [PlatformHeartRateSample] = []
    if let monitoring {
      let start = min(Int(clamping: max(afterSequence, 0)), monitoring.samples.count)
      samples = Array(monitoring.samples[start...])
    }
    return PlatformHeartRateStatus(
      bluetoothState: bluetoothStateName,
      connectionState: connectionState,
      lastSequence: monitoring?.sequence ?? 0,
      samples: samples,
      sensorId: targetSensorId,
      sensorName: targetSensorId == nil ? nil : (peripheral?.name ?? Self.defaultSensorName),
      batteryPercent: batteryPercent.map { Int64($0) },
      latestBpm: latestBpm.map { Int64($0) },
      latestAtUtcEpochMilliseconds: latestAtMilliseconds,
      monitoringSessionId: monitoring?.config.sessionId,
      zoneState: monitoring?.alarm.zoneState.rawValue
    )
  }

  func scan(durationMilliseconds: Int64) async throws -> [PlatformHeartRateSensor] {
    let manager = try await requirePoweredOn()
    let duration = min(max(durationMilliseconds, 500), 30_000)
    scanGeneration += 1
    let generation = scanGeneration
    scanResults.removeAll()

    for connected in manager.retrieveConnectedPeripherals(withServices: [Self.heartRateService]) {
      knownPeripherals[connected.identifier] = connected
      scanResults[connected.identifier] = ScanEntry(
        name: Self.displayName(connected.name), rssi: nil, isConnected: true)
    }
    if let peripheral, peripheral.state == .connected {
      scanResults[peripheral.identifier] = ScanEntry(
        name: Self.displayName(peripheral.name), rssi: nil, isConnected: true)
    }

    manager.scanForPeripherals(
      withServices: [Self.heartRateService],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000)
    if scanGeneration == generation { manager.stopScan() }

    return scanResults
      .sorted { lhs, rhs in
        if lhs.value.isConnected != rhs.value.isConnected { return lhs.value.isConnected }
        let lhsRssi = lhs.value.rssi ?? Int.min
        let rhsRssi = rhs.value.rssi ?? Int.min
        if lhsRssi != rhsRssi { return lhsRssi > rhsRssi }
        return lhs.value.name < rhs.value.name
      }
      .map { id, entry in
        PlatformHeartRateSensor(
          id: id.uuidString,
          name: entry.name,
          isConnected: entry.isConnected,
          signalStrength: entry.rssi.map { Int64($0) }
        )
      }
  }

  /// Merkt den Gurt und beginnt zu verbinden; der Fortschritt steht in `status`.
  /// False, wenn das System den Gurt nicht kennt.
  func connect(sensorId: String) async throws -> Bool {
    guard let uuid = UUID(uuidString: sensorId) else { return false }
    let manager = try await requirePoweredOn()
    guard let found = knownPeripherals[uuid] ?? manager.retrievePeripherals(withIdentifiers: [uuid]).first
    else { return false }
    knownPeripherals[uuid] = found
    targetSensorId = uuid.uuidString
    defaults.set(uuid.uuidString, forKey: Self.storedSensorKey)
    attach(found, manager: manager)
    return true
  }

  /// Trennt den Gurt und vergisst ihn; es folgt kein automatisches Neuverbinden.
  func disconnect() {
    targetSensorId = nil
    defaults.removeObject(forKey: Self.storedSensorKey)
    if let peripheral {
      central?.cancelPeripheralConnection(peripheral)
    }
    peripheral = nil
    connectionState = "idle"
    hasConnected = false
    batteryPercent = nil
    latestBpm = nil
    latestAtMilliseconds = nil
  }

  /// Startet Puffer und Alarm und ersetzt eine laufende Überwachung.
  func startMonitoring(_ config: PlatformCardioMonitoringConfig) async {
    let previousUsedLiveActivity = monitoring?.config.liveActivityEnabled ?? false
    let now = Date()
    monitoring = ActiveMonitoring(
      config: config,
      alarm: CardioZoneAlarm(config: Self.alarmConfig(from: config), now: now),
      voiceSchedule: Self.voiceSchedule(from: config, now: now)
    )
    if config.voiceEnabled != true { voice.stop() }
    startTimer()
    if central == nil {
      if targetSensorId != nil { ensureCentral() }
    } else {
      reconnectStoredSensor()
    }

    if config.liveActivityEnabled {
      await liveActivity.start(
        sessionId: config.sessionId,
        title: config.title,
        startedAt: Date(timeIntervalSince1970: Double(config.startedAtUtcEpochMilliseconds) / 1000),
        state: liveActivityState(now: now)
      )
    } else if previousUsedLiveActivity {
      await liveActivity.end()
    }
  }

  /// Ändert Zone und Optionen, ohne Puffer und Sequenzen zurückzusetzen.
  func updateMonitoring(_ config: PlatformCardioMonitoringConfig) async {
    guard let current = monitoring, current.config.sessionId == config.sessionId else { return }
    let now = Date()
    monitoring?.config = config
    if current.config.voiceIntervalMinutes != config.voiceIntervalMinutes {
      monitoring?.voiceSchedule = Self.voiceSchedule(from: config, now: now)
    }
    if config.voiceEnabled != true { voice.stop() }
    let events = monitoring?.alarm.update(config: Self.alarmConfig(from: config), now: now) ?? []
    handle(events)

    if config.liveActivityEnabled {
      if current.config.liveActivityEnabled {
        await liveActivity.update(state: liveActivityState(now: now))
      } else {
        await liveActivity.start(
          sessionId: config.sessionId,
          title: config.title,
          startedAt: Date(timeIntervalSince1970: Double(config.startedAtUtcEpochMilliseconds) / 1000),
          state: liveActivityState(now: now)
        )
      }
    } else if current.config.liveActivityEnabled {
      await liveActivity.end()
    }
  }

  /// Beendet die Überwachung der Session; andere Session-IDs werden ignoriert.
  func stopMonitoring(sessionId: String) async {
    guard let current = monitoring, current.config.sessionId == sessionId else { return }
    monitoring = nil
    tickTimer?.invalidate()
    tickTimer = nil
    voice.stop()
    await liveActivity.end()
    await alerts.clearDelivered()
  }

  /// Beendet Activities, die ein früherer Prozess hinterlassen hat. Die Überwachung ist
  /// nach einem Neustart weg; Dart startet sie bei Bedarf neu.
  func endOrphanedLiveActivities() async {
    guard monitoring == nil else { return }
    await liveActivity.end()
  }

  // MARK: - Central

  private var bluetoothStateName: String {
    guard let central else { return "unknown" }
    switch central.state {
    case .poweredOn: return "poweredOn"
    case .poweredOff: return "poweredOff"
    case .unauthorized: return "unauthorized"
    case .unsupported: return "unsupported"
    case .resetting: return "resetting"
    case .unknown: return "unknown"
    @unknown default: return "unknown"
    }
  }

  @discardableResult
  private func ensureCentral() -> CBCentralManager {
    if let central { return central }
    // Keine System-Warnung bei ausgeschaltetem Bluetooth; die App erklärt es selbst.
    let manager = CBCentralManager(
      delegate: bridge,
      queue: nil,
      options: [CBCentralManagerOptionShowPowerAlertKey: false]
    )
    central = manager
    return manager
  }

  /// Wartet kurz auf einen bekannten Zustand und wirft, wenn Bluetooth nicht bereit ist.
  private func requirePoweredOn() async throws -> CBCentralManager {
    let manager = ensureCentral()
    let deadline = Date().addingTimeInterval(3)
    while (manager.state == .unknown || manager.state == .resetting), Date() < deadline {
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    switch manager.state {
    case .poweredOn:
      return manager
    case .unauthorized:
      throw PigeonError(
        code: "bluetooth_unauthorized", message: "Bluetooth access is not allowed for Gainer.", details: nil)
    case .unsupported:
      throw PigeonError(
        code: "bluetooth_unsupported", message: "Bluetooth Low Energy is not supported on this device.",
        details: nil)
    default:
      throw PigeonError(
        code: "bluetooth_powered_off", message: "Bluetooth is turned off or not ready.", details: nil)
    }
  }

  private static func displayName(_ name: String?) -> String {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return defaultSensorName
    }
    return name
  }

  /// Verbindet den Gurt; ein anderer, noch verbundener Gurt wird zuvor getrennt.
  private func attach(_ target: CBPeripheral, manager: CBCentralManager) {
    if let current = peripheral, current.identifier != target.identifier {
      manager.cancelPeripheralConnection(current)
      hasConnected = false
      batteryPercent = nil
    }
    peripheral = target
    target.delegate = bridge
    switch target.state {
    case .connected:
      connectionState = "connected"
      hasConnected = true
      target.discoverServices([Self.heartRateService, Self.batteryService])
    case .connecting:
      connectionState = hasConnected ? "reconnecting" : "connecting"
    default:
      connectionState = hasConnected ? "reconnecting" : "connecting"
      manager.connect(target, options: nil)
    }
  }

  /// Verbindet den gemerkten Gurt nach dem Start oder nach einem Bluetooth-Neustart.
  private func reconnectStoredSensor() {
    guard let central, central.state == .poweredOn, let id = targetSensorId,
      let uuid = UUID(uuidString: id)
    else { return }
    if let current = peripheral, current.identifier == uuid,
      current.state == .connected || current.state == .connecting
    {
      return
    }
    guard let found = knownPeripherals[uuid] ?? central.retrievePeripherals(withIdentifiers: [uuid]).first
    else { return }
    knownPeripherals[uuid] = found
    attach(found, manager: central)
  }

  // MARK: - Rückrufe der Bridge

  fileprivate func centralStateChanged() {
    guard let central else { return }
    if central.state == .poweredOn {
      reconnectStoredSensor()
    } else {
      connectionState = targetSensorId == nil ? "idle" : "reconnecting"
    }
  }

  fileprivate func didDiscover(_ discovered: CBPeripheral, advertisementData: [String: Any], rssi: Int) {
    knownPeripherals[discovered.identifier] = discovered
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    // 127 heißt „nicht verfügbar“.
    let signal: Int? = rssi == 127 ? nil : rssi
    scanResults[discovered.identifier] = ScanEntry(
      name: Self.displayName(discovered.name ?? advertisedName),
      rssi: signal,
      isConnected: scanResults[discovered.identifier]?.isConnected ?? false
    )
  }

  fileprivate func didConnect(_ connected: CBPeripheral) {
    guard connected.identifier == peripheral?.identifier else { return }
    hasConnected = true
    connectionState = "connected"
    connected.discoverServices([Self.heartRateService, Self.batteryService])
  }

  fileprivate func didFailToConnect(_ failed: CBPeripheral) {
    guard failed.identifier == peripheral?.identifier, targetSensorId != nil else { return }
    connectionState = hasConnected ? "reconnecting" : "connecting"
    // Kurze Pause, damit ein dauerhaft fehlschlagender Versuch keine enge Schleife bildet.
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard let self, let central = self.central, central.state == .poweredOn,
        self.targetSensorId != nil, self.peripheral?.identifier == failed.identifier
      else { return }
      central.connect(failed, options: nil)
    }
  }

  fileprivate func didDisconnect(_ disconnected: CBPeripheral) {
    guard disconnected.identifier == peripheral?.identifier, targetSensorId != nil else { return }
    // Nicht vom Nutzer getrennt: sofort wieder verbinden, ohne Timeout. iOS stellt die
    // Verbindung her, sobald der Gurt wieder sendet.
    connectionState = "reconnecting"
    central?.connect(disconnected, options: nil)
  }

  fileprivate func didDiscoverServices(_ discovered: CBPeripheral, failed: Bool) {
    guard !failed, discovered.identifier == peripheral?.identifier else { return }
    for service in discovered.services ?? [] {
      if service.uuid == Self.heartRateService {
        discovered.discoverCharacteristics([Self.heartRateMeasurement], for: service)
      } else if service.uuid == Self.batteryService {
        discovered.discoverCharacteristics([Self.batteryLevel], for: service)
      }
    }
  }

  fileprivate func didDiscoverCharacteristics(_ discovered: CBPeripheral, service: CBService, failed: Bool) {
    guard !failed, discovered.identifier == peripheral?.identifier else { return }
    for characteristic in service.characteristics ?? [] {
      if characteristic.uuid == Self.heartRateMeasurement {
        discovered.setNotifyValue(true, for: characteristic)
      } else if characteristic.uuid == Self.batteryLevel {
        discovered.readValue(for: characteristic)
        discovered.setNotifyValue(true, for: characteristic)
      }
    }
  }

  fileprivate func didUpdateValue(_ source: CBPeripheral, characteristic: CBCharacteristic, failed: Bool) {
    guard !failed, source.identifier == peripheral?.identifier, let data = characteristic.value else { return }
    let bytes = [UInt8](data)
    if characteristic.uuid == Self.heartRateMeasurement {
      if let measurement = HeartRateMeasurementParser.parse(bytes) {
        handle(measurement, at: Date())
      }
    } else if characteristic.uuid == Self.batteryLevel {
      if let level = HeartRateMeasurementParser.parseBattery(bytes) { batteryPercent = level }
    }
  }

  // MARK: - Messwerte und Alarm

  private func handle(_ measurement: HeartRateMeasurement, at time: Date) {
    // 0 bpm meldet der Gurt ohne Hautkontakt; das zählt als „kein Signal“.
    guard measurement.bpm > 0 else { return }
    let milliseconds = Self.milliseconds(time)
    latestBpm = measurement.bpm
    latestAtMilliseconds = milliseconds
    guard monitoring != nil else { return }

    monitoring?.sequence += 1
    if let sequence = monitoring?.sequence {
      monitoring?.samples.append(
        PlatformHeartRateSample(
          sequence: sequence,
          atUtcEpochMilliseconds: milliseconds,
          bpm: Int64(measurement.bpm),
          rrIntervalsMs: measurement.rrIntervalsMs.map { Int64($0) }
        ))
    }
    let events = monitoring?.alarm.record(bpm: measurement.bpm, at: time) ?? []
    handle(events)
    pushLiveActivity(now: time)
  }

  /// Zeit für Signalverlust und Wiederholungen, unabhängig von neuen Messwerten.
  private func evaluateAlarm(now: Date) {
    guard monitoring != nil else { return }
    let events = monitoring?.alarm.tick(now: now) ?? []
    handle(events)
  }

  private func tick() {
    guard monitoring != nil else { return }
    let now = Date()
    evaluateAlarm(now: now)
    announceInterval(now: now)
    pushLiveActivity(now: now)
  }

  /// Sagt im gewählten Intervall Dauer und Puls an.
  private func announceInterval(now: Date) {
    guard monitoring?.config.voiceEnabled == true,
      let minutes = monitoring?.voiceSchedule.due(now: now)
    else { return }
    // Ein veralteter Puls (Signalverlust) wird nicht vorgelesen.
    var bpm = latestBpm
    if let latestAtMilliseconds,
      now.timeIntervalSince1970 * 1000 - Double(latestAtMilliseconds) > CardioZoneAlarm.signalTimeoutSeconds * 1000
    {
      bpm = nil
    }
    voice.speak(CardioVoiceText.intervalText(minutes: minutes, bpm: bpm))
  }

  private func handle(_ events: [CardioZoneEvent]) {
    guard let config = monitoring?.config, !events.isEmpty else { return }
    // Zonenmeldungen nennen die Zone, die gerade gilt (ggf. die der Phase).
    let zone = monitoring?.alarm.activeZone
    let speaks = config.voiceEnabled == true
    for event in events {
      if speaks { voice.speak(CardioVoiceText.text(for: event)) }
      let alerts = alerts
      let soundId = config.soundId
      Task {
        // Mit Sprachansage bleibt die Meldung stumm, damit nichts doppelt klingt.
        await alerts.post(
          event: event,
          zoneLowBpm: zone?.lowerBound,
          zoneHighBpm: zone?.upperBound,
          soundId: soundId,
          silent: speaks
        )
      }
    }
  }

  private func startTimer() {
    tickTimer?.invalidate()
    let timer = Timer(timeInterval: Self.tickIntervalSeconds, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        if let self { self.tick() }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    tickTimer = timer
  }

  // MARK: - Live Activity

  private func liveActivityState(now: Date) -> GainerCardioActivityAttributes.ContentState {
    let zoneState = monitoring?.alarm.zoneState ?? .none
    // Ohne Signal zeigt die Activity keinen veralteten Puls.
    let bpm = zoneState == .noSignal ? nil : latestBpm
    let zone = monitoring?.alarm.activeZone
    let phase = monitoring?.alarm.currentPhase
    let phaseIndex = monitoring?.alarm.currentPhaseIndex
    let startedAt = monitoring.map {
      Date(timeIntervalSince1970: Double($0.config.startedAtUtcEpochMilliseconds) / 1000)
    }
    return GainerCardioActivityAttributes.ContentState(
      bpm: bpm,
      zoneLowBpm: zone?.lowerBound,
      zoneHighBpm: zone?.upperBound,
      zoneState: zoneState.rawValue,
      updatedAt: now,
      phaseName: phase?.name,
      phaseIndex: phaseIndex.map { $0 + 1 },
      phaseCount: phase == nil ? nil : monitoring?.config.phases?.count,
      phaseEndsAt: phase.flatMap { phase in
        startedAt?.addingTimeInterval(TimeInterval(phase.endOffsetSeconds))
      }
    )
  }

  private func pushLiveActivity(now: Date) {
    guard monitoring?.config.liveActivityEnabled == true else { return }
    let state = liveActivityState(now: now)
    Task { await liveActivity.update(state: state) }
  }

  // MARK: - Hilfen

  nonisolated static func alarmConfig(from config: PlatformCardioMonitoringConfig) -> CardioZoneAlarmConfig {
    CardioZoneAlarmConfig(
      zoneLowBpm: config.zoneLowBpm.map { Int(clamping: $0) },
      zoneHighBpm: config.zoneHighBpm.map { Int(clamping: $0) },
      graceSeconds: Int(clamping: config.graceSeconds),
      repeatSeconds: Int(clamping: config.repeatSeconds),
      warmupSeconds: Int(clamping: config.warmupSeconds),
      startedAt: Date(timeIntervalSince1970: Double(config.startedAtUtcEpochMilliseconds) / 1000),
      alertsEnabled: config.alertsEnabled,
      phases: (config.phases ?? []).map {
        CardioPhase(
          startOffsetSeconds: Int(clamping: $0.startOffsetSeconds),
          durationSeconds: Int(clamping: $0.durationSeconds),
          name: $0.name,
          zoneLowBpm: $0.zoneLowBpm.map { Int(clamping: $0) },
          zoneHighBpm: $0.zoneHighBpm.map { Int(clamping: $0) }
        )
      }
    )
  }

  nonisolated static func voiceSchedule(from config: PlatformCardioMonitoringConfig, now: Date) -> CardioVoiceSchedule {
    CardioVoiceSchedule(
      intervalMinutes: config.voiceIntervalMinutes.map { Int(clamping: $0) },
      startedAt: Date(timeIntervalSince1970: Double(config.startedAtUtcEpochMilliseconds) / 1000),
      now: now
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
