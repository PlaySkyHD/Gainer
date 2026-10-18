import CryptoKit
import Foundation
import HealthKit

struct NativeBodyMassSample {
  let uuid: String
  let measuredAtUtcEpochMilliseconds: Int64
  let weightKilograms: Double
  let sourceName: String
  let syncIdentifier: String?
}

/// Ein Schlaf-Abschnitt aus der Health-Schlafanalyse (`rawValue` = `HKCategoryValueSleepAnalysis`).
struct NativeSleepSegment {
  let start: Date
  let end: Date
  let rawValue: Int
  let sourceName: String
  let fromGainer: Bool
}

struct NativeSleepWindow: Equatable {
  let bedtimeUtcEpochMilliseconds: Int64
  let wakeUtcEpochMilliseconds: Int64
  let asleepMinutes: Int64
  let sourceName: String
  let fromGainer: Bool
}

/// Reine Auswertung der Schlafanalyse, ohne HealthKit-Zugriff.
enum NativeSleepAnalysis {
  /// Nur echte Schlafphasen zählen; „Im Bett“ und „Wach“ nicht.
  static func isAsleep(rawValue: Int) -> Bool {
    guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return false }
    switch value {
    case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
      return true
    default:
      return false
    }
  }

  /// Zu Bett = frühester Beginn, Aufgestanden = spätestes Ende. Fremde Quellen
  /// haben Vorrang; erst ohne sie zählen Gainer-eigene Proben. Überlappende
  /// Abschnitte (z. B. Uhr und iPhone) werden nur einmal gezählt.
  static func summarize(_ segments: [NativeSleepSegment]) -> NativeSleepWindow? {
    let asleep = segments.filter { isAsleep(rawValue: $0.rawValue) && $0.end > $0.start }
    let foreign = asleep.filter { !$0.fromGainer }
    let chosen = (foreign.isEmpty ? asleep : foreign).sorted { $0.start < $1.start }
    guard let first = chosen.first else { return nil }

    var bedtime = first.start
    var wake = first.end
    var coveredSeconds: TimeInterval = 0
    var runStart = first.start
    var runEnd = first.end
    for segment in chosen.dropFirst() {
      if segment.start <= runEnd {
        runEnd = max(runEnd, segment.end)
      } else {
        coveredSeconds += runEnd.timeIntervalSince(runStart)
        runStart = segment.start
        runEnd = segment.end
      }
      bedtime = min(bedtime, segment.start)
      wake = max(wake, segment.end)
    }
    coveredSeconds += runEnd.timeIntervalSince(runStart)

    return NativeSleepWindow(
      bedtimeUtcEpochMilliseconds: Int64(bedtime.timeIntervalSince1970 * 1000),
      wakeUtcEpochMilliseconds: Int64(wake.timeIntervalSince1970 * 1000),
      asleepMinutes: Int64((coveredSeconds / 60).rounded()),
      sourceName: first.sourceName,
      fromGainer: foreign.isEmpty
    )
  }
}

struct NativeWorkoutExportResult {
  let status: String
  let syncIdentifier: String
  let syncVersion: Int64
}

/// Beendete Cardio-Einheit, wie sie nach Apple Health geschrieben wird.
struct NativeCardioExport: Equatable {
  let accountId: String
  let sessionId: String
  let syncVersion: Int64
  let activityType: String
  let startedAt: Date
  let completedAt: Date
  let sampleIntervalSeconds: Int
  let heartRateBpm: [Int]
  let distanceKm: Double?
  let energyKcal: Double?
}

/// Ein Pulswert mit Zeitfenster für Apple Health.
struct NativeHeartRateWindow: Equatable {
  let start: Date
  let end: Date
  let bpm: Int
}

enum NativeHealthKitError: Error, Equatable {
  case unavailable
  case invalidDateRange
  case invalidWorkout
  case writePermissionNotGranted
  case queryFailed
  case saveFailed
  case invalidSample

  var flutterCode: String {
    switch self {
    case .unavailable: "health_unavailable"
    case .invalidDateRange: "health_invalid_range"
    case .invalidWorkout: "health_invalid_workout"
    case .writePermissionNotGranted: "health_write_permission_not_granted"
    case .queryFailed: "health_query_failed"
    case .saveFailed: "health_save_failed"
    case .invalidSample: "health_invalid_sample"
    }
  }

  var safeMessage: String {
    switch self {
    case .unavailable: "Apple Health data is unavailable on this device."
    case .invalidDateRange: "The requested HealthKit date range is invalid or too large."
    case .invalidWorkout: "The completed workout is invalid or outside the supported export range."
    case .writePermissionNotGranted: "Apple Health workout write access is not enabled."
    case .queryFailed: "Apple Health could not complete the requested query."
    case .saveFailed: "Apple Health could not save the requested data."
    case .invalidSample: "The Apple Health sample is invalid."
    }
  }
}

final class NativeHealthKit {
  private let store: HKHealthStore
  private let now: () -> Date

  init(store: HKHealthStore = HKHealthStore(), now: @escaping () -> Date = Date.init) {
    self.store = store
    self.now = now
  }

  static func stableWorkoutSyncIdentifier(accountId: String, workoutId: String) -> String? {
    guard let account = UUID(uuidString: accountId), let workout = UUID(uuidString: workoutId) else {
      return nil
    }
    let input = Data("gainer.health.workout.v1|\(account.uuidString.lowercased())|\(workout.uuidString.lowercased())".utf8)
    let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    return "gainer.health.workout.v1.\(digest)"
  }

  /// Stabile Kennung einer Cardio-Einheit in Apple Health. Wie beim Workout geht keine
  /// Konto-ID im Klartext in fremde Apps; Konto und Einheit müssen UUIDs sein.
  static func stableCardioSyncIdentifier(accountId: String, sessionId: String) -> String? {
    guard let account = UUID(uuidString: accountId), let session = UUID(uuidString: sessionId) else {
      return nil
    }
    let input = Data("gainer.cardio.v1|\(account.uuidString.lowercased())|\(session.uuidString.lowercased())".utf8)
    let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    return "gainer.cardio.v1.\(digest)"
  }

  /// Ein Zeitfenster je Pulswert größer 0: Beginn Start + Index × Intervall, Ende Beginn +
  /// Intervall, höchstens das Ende der Einheit. Fenster ohne Länge entfallen.
  static func heartRateWindows(
    startedAt: Date,
    completedAt: Date,
    intervalSeconds: Int,
    heartRateBpm: [Int]
  ) -> [NativeHeartRateWindow] {
    guard intervalSeconds > 0 else { return [] }
    var windows: [NativeHeartRateWindow] = []
    for (index, bpm) in heartRateBpm.enumerated() where bpm > 0 && bpm <= 300 {
      let start = startedAt.addingTimeInterval(TimeInterval(index * intervalSeconds))
      guard start < completedAt else { break }
      let end = min(start.addingTimeInterval(TimeInterval(intervalSeconds)), completedAt)
      windows.append(NativeHeartRateWindow(start: start, end: end, bpm: bpm))
    }
    return windows
  }

  static func validWorkoutInterval(startedAt: Date, completedAt: Date, now: Date) -> Bool {
    startedAt.timeIntervalSince1970 > 0
      && completedAt > startedAt
      && completedAt <= now.addingTimeInterval(300)
      && completedAt.timeIntervalSince(startedAt) <= 24 * 60 * 60
  }

  static func validCheckInSyncIdentifier(_ identifier: String) -> Bool {
    identifier.hasPrefix("gainer-checkin-") && identifier.count <= 200
  }

  private static func syncMetadata(identifier: String, version: Int64) -> [String: Any] {
    [
      HKMetadataKeySyncIdentifier: identifier,
      HKMetadataKeySyncVersion: NSNumber(value: version),
    ]
  }

  func isAvailable() -> Bool {
    HKHealthStore.isHealthDataAvailable()
  }

  /// HealthKit reports request-sheet completion, not whether read access was granted.
  func requestBodyMassReadAuthorization() async throws -> PlatformAuthorizationRequestResult {
    guard isAvailable(), let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
      throw NativeHealthKitError.unavailable
    }
    try await store.requestAuthorization(toShare: [], read: [bodyMass])
    return .requestCompleted
  }

  func readBodyMassSamples(from start: Date, to end: Date) async throws -> [NativeBodyMassSample] {
    guard isAvailable(), let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
      throw NativeHealthKitError.unavailable
    }
    try validateRange(from: start, to: end)

    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
    let samples = try await queryBodyMass(type: bodyMass, predicate: predicate, sort: sort)
    return samples.compactMap { sample in
      let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
      guard kilograms.isFinite, kilograms > 0 else { return nil }
      return NativeBodyMassSample(
        uuid: sample.uuid.uuidString.lowercased(),
        measuredAtUtcEpochMilliseconds: Int64(sample.startDate.timeIntervalSince1970 * 1000),
        weightKilograms: kilograms,
        sourceName: sample.sourceRevision.source.name,
        syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String
      )
    }
  }

  /// Ein Systemdialog für alle Check-in-Typen: Lesen Gewicht, Schritte, Schlaf;
  /// Schreiben Gewicht und Schlaf. Das Ergebnis verrät keine Lese-Berechtigung.
  func requestCheckInAuthorization() async throws -> PlatformAuthorizationRequestResult {
    guard isAvailable(),
      let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
      let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
      let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    else { throw NativeHealthKitError.unavailable }
    let share: Set<HKSampleType> = [bodyMass, sleep]
    let read: Set<HKObjectType> = [bodyMass, steps, sleep]
    try await store.requestAuthorization(toShare: share, read: read)
    return .requestCompleted
  }

  /// Tagessumme der Schritte (HealthKit dedupliziert Quellen); nil ohne Daten.
  func readStepCount(from start: Date, to end: Date) async throws -> Int64? {
    guard isAvailable(), let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
      throw NativeHealthKitError.unavailable
    }
    try validateRange(from: start, to: end)
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64?, Error>) in
      let query = HKStatisticsQuery(
        quantityType: steps,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum
      ) { _, statistics, error in
        if let error {
          if (error as? HKError)?.code == .errorNoData {
            continuation.resume(returning: nil)
          } else {
            continuation.resume(throwing: NativeHealthKitError.queryFailed)
          }
          return
        }
        guard let sum = statistics?.sumQuantity() else {
          continuation.resume(returning: nil)
          return
        }
        let count = sum.doubleValue(for: .count())
        if count.isFinite, count > 0 {
          continuation.resume(returning: Int64(count.rounded()))
        } else {
          continuation.resume(returning: nil)
        }
      }
      store.execute(query)
    }
  }

  /// Schlafanalyse der Nacht im Fenster; die Auswertung liegt in `NativeSleepAnalysis`.
  func readSleep(from start: Date, to end: Date) async throws -> NativeSleepWindow? {
    guard isAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      throw NativeHealthKitError.unavailable
    }
    try validateRange(from: start, to: end)
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    let samples = try await fetchSamples(type: sleepType, predicate: predicate)
    let ownBundle = Bundle.main.bundleIdentifier
    let segments = samples.compactMap { sample -> NativeSleepSegment? in
      guard let category = sample as? HKCategorySample else { return nil }
      let source = category.sourceRevision.source
      return NativeSleepSegment(
        start: category.startDate,
        end: category.endDate,
        rawValue: category.value,
        sourceName: source.name,
        fromGainer: source.bundleIdentifier == ownBundle
      )
    }
    return NativeSleepAnalysis.summarize(segments)
  }

  /// Schreibt das Gewicht; dieselbe `syncIdentifier` ersetzt die frühere Probe.
  func writeBodyMass(
    kilograms: Double,
    measuredAt: Date,
    syncIdentifier: String
  ) async throws -> PlatformHealthWriteStatus {
    guard isAvailable(), let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
      throw NativeHealthKitError.unavailable
    }
    guard kilograms.isFinite, kilograms > 0, kilograms < 700,
      measuredAt <= now().addingTimeInterval(300), Self.validCheckInSyncIdentifier(syncIdentifier)
    else { throw NativeHealthKitError.invalidSample }
    guard store.authorizationStatus(for: bodyMass) == .sharingAuthorized else {
      return .notAuthorized
    }
    let version = Int64(now().timeIntervalSince1970 * 1000)
    if try await hasSample(type: bodyMass, syncIdentifier: syncIdentifier, atLeastVersion: version) {
      return .alreadyPresent
    }
    let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
    let sample = HKQuantitySample(
      type: bodyMass,
      quantity: quantity,
      start: measuredAt,
      end: measuredAt,
      metadata: Self.syncMetadata(identifier: syncIdentifier, version: version)
    )
    do {
      try await store.save(sample)
      return .saved
    } catch {
      throw NativeHealthKitError.saveFailed
    }
  }

  /// Schreibt eine Schlafprobe (unspezifisch „Schlaf“); dieselbe `syncIdentifier` ersetzt sie.
  func writeSleep(
    bedtime: Date,
    wake: Date,
    syncIdentifier: String
  ) async throws -> PlatformHealthWriteStatus {
    guard isAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      throw NativeHealthKitError.unavailable
    }
    guard wake > bedtime, wake.timeIntervalSince(bedtime) <= 24 * 60 * 60,
      wake <= now().addingTimeInterval(300), Self.validCheckInSyncIdentifier(syncIdentifier)
    else { throw NativeHealthKitError.invalidSample }
    guard store.authorizationStatus(for: sleepType) == .sharingAuthorized else {
      return .notAuthorized
    }
    let version = Int64(now().timeIntervalSince1970 * 1000)
    if try await hasSample(type: sleepType, syncIdentifier: syncIdentifier, atLeastVersion: version) {
      return .alreadyPresent
    }
    let sample = HKCategorySample(
      type: sleepType,
      value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
      start: bedtime,
      end: wake,
      metadata: Self.syncMetadata(identifier: syncIdentifier, version: version)
    )
    do {
      try await store.save(sample)
      return .saved
    } catch {
      throw NativeHealthKitError.saveFailed
    }
  }

  /// This is a distinct, user-triggered request from the Body Mass read request.
  func requestWorkoutWriteAuthorization() async throws -> PlatformAuthorizationRequestResult {
    guard isAvailable() else { throw NativeHealthKitError.unavailable }
    let workoutType = HKObjectType.workoutType()
    try await store.requestAuthorization(toShare: [workoutType], read: [])
    return .requestCompleted
  }

  /// Exports only the completed-workout projection supplied by the caller.
  /// The repository does not define a specific training category, so `.other`
  /// is used instead of inferring a category from exercise names.
  func exportCompletedWorkout(
    accountId: String,
    workoutId: String,
    syncVersion: Int64,
    startedAt: Date,
    completedAt: Date
  ) async throws -> NativeWorkoutExportResult {
    guard isAvailable(), syncVersion > 0,
      Self.validWorkoutInterval(startedAt: startedAt, completedAt: completedAt, now: now()),
      let syncIdentifier = Self.stableWorkoutSyncIdentifier(accountId: accountId, workoutId: workoutId)
    else { throw NativeHealthKitError.invalidWorkout }

    let workoutType = HKObjectType.workoutType()
    guard store.authorizationStatus(for: workoutType) == .sharingAuthorized else {
      throw NativeHealthKitError.writePermissionNotGranted
    }

    let existing = try await queryWorkouts(syncIdentifier: syncIdentifier)
    let highestVersion = existing.compactMap { sample -> Int64? in
      (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value
    }.max()
    if let highestVersion, highestVersion >= syncVersion {
      return NativeWorkoutExportResult(
        status: "alreadyPresent",
        syncIdentifier: syncIdentifier,
        syncVersion: highestVersion
      )
    }

    let metadata: [String: Any] = [
      HKMetadataKeySyncIdentifier: syncIdentifier,
      HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
    ]
    let workout = HKWorkout(
      activityType: .other,
      start: startedAt,
      end: completedAt,
      duration: completedAt.timeIntervalSince(startedAt),
      totalEnergyBurned: nil,
      totalDistance: nil,
      metadata: metadata
    )
    do {
      try await store.save(workout)
      return NativeWorkoutExportResult(
        status: "saved",
        syncIdentifier: syncIdentifier,
        syncVersion: syncVersion
      )
    } catch {
      // Avoid logging HealthKit payloads or identifiers. A retry uses the same
      // identifier/version and checks the store before attempting another save.
      throw NativeHealthKitError.saveFailed
    }
  }

  /// Eigener Dialog für Cardio: Workout, Puls, Distanz (Rad) und aktive Energie schreiben.
  func requestCardioWriteAuthorization() async throws -> PlatformAuthorizationRequestResult {
    guard isAvailable(),
      let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
      let distance = HKObjectType.quantityType(forIdentifier: .distanceCycling),
      let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
    else { throw NativeHealthKitError.unavailable }
    let share: Set<HKSampleType> = [HKObjectType.workoutType(), heartRate, distance, energy]
    try await store.requestAuthorization(toShare: share, read: [])
    return .requestCompleted
  }

  /// Schreibt eine Rad-Ergometer-Einheit als Indoor-Radtraining mit Pulsproben. Distanz und
  /// Energie fließen nur ein, wenn sie eingetragen sind. Fehlt die Erlaubnis für einen
  /// einzelnen Probentyp, entfallen nur dessen Proben; ohne Workout-Erlaubnis gibt es einen Fehler.
  func exportCardioSession(_ export: NativeCardioExport) async throws -> NativeWorkoutExportResult {
    guard isAvailable(), export.syncVersion > 0, export.activityType == "IndoorCycling",
      (1...60).contains(export.sampleIntervalSeconds),
      export.heartRateBpm.count <= 24 * 60 * 60 / export.sampleIntervalSeconds + 1,
      Self.validWorkoutInterval(startedAt: export.startedAt, completedAt: export.completedAt, now: now()),
      export.distanceKm.map({ $0.isFinite && $0 >= 0 && $0 <= 5_000 }) ?? true,
      export.energyKcal.map({ $0.isFinite && $0 >= 0 && $0 <= 50_000 }) ?? true,
      let syncIdentifier = Self.stableCardioSyncIdentifier(
        accountId: export.accountId, sessionId: export.sessionId)
    else { throw NativeHealthKitError.invalidWorkout }

    let workoutType = HKObjectType.workoutType()
    guard store.authorizationStatus(for: workoutType) == .sharingAuthorized else {
      throw NativeHealthKitError.writePermissionNotGranted
    }

    let existing = try await queryWorkouts(syncIdentifier: syncIdentifier)
    let highestVersion = existing.compactMap { sample -> Int64? in
      (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value
    }.max()
    if let highestVersion, highestVersion >= export.syncVersion {
      return NativeWorkoutExportResult(
        status: "alreadyPresent",
        syncIdentifier: syncIdentifier,
        syncVersion: highestVersion
      )
    }

    var samples: [HKSample] = []
    func canShare(_ type: HKQuantityType) -> Bool {
      store.authorizationStatus(for: type) == .sharingAuthorized
    }
    if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate), canShare(heartRateType) {
      let unit = HKUnit.count().unitDivided(by: .minute())
      for window in Self.heartRateWindows(
        startedAt: export.startedAt,
        completedAt: export.completedAt,
        intervalSeconds: export.sampleIntervalSeconds,
        heartRateBpm: export.heartRateBpm
      ) {
        samples.append(
          HKQuantitySample(
            type: heartRateType,
            quantity: HKQuantity(unit: unit, doubleValue: Double(window.bpm)),
            start: window.start,
            end: window.end
          ))
      }
    }
    if let distanceKm = export.distanceKm, distanceKm > 0,
      let distanceType = HKObjectType.quantityType(forIdentifier: .distanceCycling), canShare(distanceType)
    {
      samples.append(
        HKQuantitySample(
          type: distanceType,
          quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: distanceKm),
          start: export.startedAt,
          end: export.completedAt
        ))
    }
    if let energyKcal = export.energyKcal, energyKcal > 0,
      let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned), canShare(energyType)
    {
      samples.append(
        HKQuantitySample(
          type: energyType,
          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
          start: export.startedAt,
          end: export.completedAt
        ))
    }

    var metadata = Self.syncMetadata(identifier: syncIdentifier, version: export.syncVersion)
    metadata[HKMetadataKeyIndoorWorkout] = NSNumber(value: true)
    let distance = export.distanceKm.flatMap { $0 > 0 ? HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: $0) : nil }
    let energy = export.energyKcal.flatMap { $0 > 0 ? HKQuantity(unit: .kilocalorie(), doubleValue: $0) : nil }
    let workout = HKWorkout(
      activityType: .cycling,
      start: export.startedAt,
      end: export.completedAt,
      duration: export.completedAt.timeIntervalSince(export.startedAt),
      totalEnergyBurned: energy,
      totalDistance: distance,
      metadata: metadata
    )
    do {
      // Proben zuerst, damit das Workout nie ohne seine Pulskurve „fertig“ ist.
      if !samples.isEmpty { try await store.save(samples) }
      var workoutSaved = false
      do {
        try await store.save(workout)
        workoutSaved = true
        if !samples.isEmpty { try await store.add(samples, to: workout) }
      } catch {
        // Nichts Halbes zurücklassen: ein Workout ohne Pulskurve würde später als vorhanden gelten.
        var leftovers: [HKObject] = samples
        if workoutSaved { leftovers.append(workout) }
        if !leftovers.isEmpty { try? await store.delete(leftovers) }
        throw error
      }
      return NativeWorkoutExportResult(
        status: "saved",
        syncIdentifier: syncIdentifier,
        syncVersion: export.syncVersion
      )
    } catch {
      // Keine Nutzdaten loggen. Ein neuer Versuch prüft zuerst den Bestand per Kennung und Version.
      throw NativeHealthKitError.saveFailed
    }
  }

  private func validateRange(from start: Date, to end: Date) throws {
    let duration = end.timeIntervalSince(start)
    guard duration > 0, duration <= 5 * 366 * 24 * 60 * 60,
      end <= now().addingTimeInterval(300)
    else { throw NativeHealthKitError.invalidDateRange }
  }

  private func fetchSamples(type: HKSampleType, predicate: NSPredicate?) async throws -> [HKSample] {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: type,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { _, results, error in
        if error != nil {
          continuation.resume(throwing: NativeHealthKitError.queryFailed)
        } else {
          continuation.resume(returning: results ?? [])
        }
      }
      store.execute(query)
    }
  }

  private func hasSample(
    type: HKSampleType,
    syncIdentifier: String,
    atLeastVersion version: Int64
  ) async throws -> Bool {
    let predicate = HKQuery.predicateForObjects(
      withMetadataKey: HKMetadataKeySyncIdentifier,
      operatorType: .equalTo,
      value: syncIdentifier
    )
    let existing = try await fetchSamples(type: type, predicate: predicate)
    let highest = existing.compactMap { sample -> Int64? in
      (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value
    }.max()
    guard let highest else { return false }
    return highest >= version
  }

  private func queryBodyMass(
    type: HKQuantityType,
    predicate: NSPredicate,
    sort: NSSortDescriptor
  ) async throws -> [HKQuantitySample] {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: type,
        predicate: predicate,
        limit: 1000,
        sortDescriptors: [sort]
      ) { _, results, error in
        if error != nil {
          continuation.resume(throwing: NativeHealthKitError.queryFailed)
        } else {
          continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
        }
      }
      store.execute(query)
    }
  }

  private func queryWorkouts(syncIdentifier: String) async throws -> [HKWorkout] {
    let workoutType = HKObjectType.workoutType()
    let predicate = HKQuery.predicateForObjects(
      withMetadataKey: HKMetadataKeySyncIdentifier,
      operatorType: .equalTo,
      value: syncIdentifier
    )
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: workoutType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { _, results, error in
        if error != nil {
          continuation.resume(throwing: NativeHealthKitError.queryFailed)
        } else {
          continuation.resume(returning: (results as? [HKWorkout]) ?? [])
        }
      }
      store.execute(query)
    }
  }
}
