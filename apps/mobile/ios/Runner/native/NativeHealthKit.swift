import CryptoKit
import Foundation
import HealthKit

struct NativeBodyMassSample {
  let uuid: String
  let measuredAtUtcEpochMilliseconds: Int64
  let weightKilograms: Double
  let sourceName: String
}

struct NativeWorkoutExportResult {
  let status: String
  let syncIdentifier: String
  let syncVersion: Int64
}

enum NativeHealthKitError: Error, Equatable {
  case unavailable
  case invalidDateRange
  case invalidWorkout
  case writePermissionNotGranted
  case queryFailed
  case saveFailed

  var flutterCode: String {
    switch self {
    case .unavailable: "health_unavailable"
    case .invalidDateRange: "health_invalid_range"
    case .invalidWorkout: "health_invalid_workout"
    case .writePermissionNotGranted: "health_write_permission_not_granted"
    case .queryFailed: "health_query_failed"
    case .saveFailed: "health_save_failed"
    }
  }

  var safeMessage: String {
    switch self {
    case .unavailable: "Apple Health data is unavailable on this device."
    case .invalidDateRange: "The requested HealthKit date range is invalid or too large."
    case .invalidWorkout: "The completed workout is invalid or outside the supported export range."
    case .writePermissionNotGranted: "Apple Health workout write access is not enabled."
    case .queryFailed: "Apple Health could not complete the requested query."
    case .saveFailed: "Apple Health could not save the completed workout."
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

  static func validWorkoutInterval(startedAt: Date, completedAt: Date, now: Date) -> Bool {
    startedAt.timeIntervalSince1970 > 0
      && completedAt > startedAt
      && completedAt <= now.addingTimeInterval(300)
      && completedAt.timeIntervalSince(startedAt) <= 24 * 60 * 60
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
    let duration = end.timeIntervalSince(start)
    guard duration > 0, duration <= 5 * 366 * 24 * 60 * 60,
      end <= now().addingTimeInterval(300)
    else { throw NativeHealthKitError.invalidDateRange }

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
        sourceName: sample.sourceRevision.source.name
      )
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
