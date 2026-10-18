import Flutter
import Foundation
import UIKit

@MainActor
final class GainerMobilePlatform: MobilePlatformApi {
  private let sessionKeychain: SecureSessionKeychain
  private let capture = NativeCapture()
  private let haptics = NativeHaptics()
  private let timerSounds: NativeTimerSounds
  private let timerNotifications: NativeTimerNotifications
  private let health = NativeHealthKit()
  private let extensionSnapshots = NativeExtensionSnapshotStore()
  private let routeStore = NativeExtensionSnapshotStore()
  @available(iOS 17.0, *)
  private let liveActivities = NativeLiveActivities()

  init(sessionKeychain: SecureSessionKeychain = SecureSessionKeychain()) {
    self.sessionKeychain = sessionKeychain
    let sounds = NativeTimerSounds()
    self.timerSounds = sounds
    self.timerNotifications = NativeTimerNotifications(sounds: sounds)
  }

  func getPlatformHealth() async throws -> PlatformHealthCheck {
    PlatformHealthCheck(available: true)
  }

  func readSessionCheckpoint(apiOrigin: String) async throws -> FlutterStandardTypedData? {
    guard let checkpoint = try sessionKeychain.readCheckpoint(apiOrigin: apiOrigin) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: checkpoint)
  }

  func writeSessionCheckpoint(
    apiOrigin: String,
    checkpoint: FlutterStandardTypedData
  ) async throws {
    try sessionKeychain.writeCheckpoint(checkpoint.data, apiOrigin: apiOrigin)
  }

  func clearSessionCheckpoint(apiOrigin: String) async throws {
    try sessionKeychain.clearCheckpoint(apiOrigin: apiOrigin)
  }

  func readPendingHandover(apiOrigin: String, accountId: String) async throws -> FlutterStandardTypedData? {
    guard let record = try sessionKeychain.readPendingHandover(
      apiOrigin: apiOrigin,
      accountId: accountId
    ) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: record)
  }

  func writePendingHandover(
    apiOrigin: String,
    accountId: String,
    record: FlutterStandardTypedData
  ) async throws {
    try sessionKeychain.writePendingHandover(
      record.data,
      apiOrigin: apiOrigin,
      accountId: accountId
    )
  }

  func clearPendingHandover(apiOrigin: String, accountId: String) async throws {
    try sessionKeychain.clearPendingHandover(
      apiOrigin: apiOrigin,
      accountId: accountId
    )
  }

  func scanBarcode() async throws -> String? {
    try await capture.scanBarcode()
  }

  func capturePhoto() async throws -> PlatformCapturedImage? {
    try await capture.capturePhoto()
  }

  func chooseImage() async throws -> PlatformCapturedImage? {
    try await capture.chooseImage()
  }

  func performHaptic(intent: String) async throws {
    await haptics.perform(intent: intent)
  }

  func requestNotificationPermission() async throws -> Bool {
    try await timerNotifications.requestPermission()
  }

  func schedulePauseNotification(
    workoutId: String,
    generation: Int64,
    targetAtUtcEpochMilliseconds: Int64,
    soundId: String
  ) async throws {
    try await timerNotifications.schedule(
      workoutId: workoutId,
      generation: generation,
      targetAtUtcEpochMilliseconds: targetAtUtcEpochMilliseconds,
      soundId: soundId
    )
  }

  func playTimerSound(soundId: String) async throws {
    try timerSounds.play(soundId: soundId)
  }

  func cancelPauseNotifications(workoutId: String) async throws {
    await timerNotifications.cancel(workoutId: workoutId)
  }

  func isHealthDataAvailable() async throws -> Bool {
    health.isAvailable()
  }

  func requestBodyMassReadAuthorization() async throws -> PlatformAuthorizationRequestResult {
    try await handleHealthKitErrors { try await health.requestBodyMassReadAuthorization() }
  }

  func readBodyMassSamples(
    fromUtcEpochMilliseconds: Int64,
    toUtcEpochMilliseconds: Int64
  ) async throws -> [PlatformBodyMassSample] {
    let samples = try await handleHealthKitErrors {
      try await health.readBodyMassSamples(
        from: Date(timeIntervalSince1970: Double(fromUtcEpochMilliseconds) / 1000),
        to: Date(timeIntervalSince1970: Double(toUtcEpochMilliseconds) / 1000)
      )
    }
    return samples.map {
      PlatformBodyMassSample(
        uuid: $0.uuid,
        measuredAtUtcEpochMilliseconds: $0.measuredAtUtcEpochMilliseconds,
        weightKilograms: $0.weightKilograms,
        sourceName: $0.sourceName,
        syncIdentifier: $0.syncIdentifier
      )
    }
  }

  func requestCheckInAuthorization() async throws -> PlatformAuthorizationRequestResult {
    try await handleHealthKitErrors { try await health.requestCheckInAuthorization() }
  }

  func readStepCount(
    fromUtcEpochMilliseconds: Int64,
    toUtcEpochMilliseconds: Int64
  ) async throws -> Int64? {
    try await handleHealthKitErrors {
      try await health.readStepCount(
        from: Date(timeIntervalSince1970: Double(fromUtcEpochMilliseconds) / 1000),
        to: Date(timeIntervalSince1970: Double(toUtcEpochMilliseconds) / 1000)
      )
    }
  }

  func readSleep(
    fromUtcEpochMilliseconds: Int64,
    toUtcEpochMilliseconds: Int64
  ) async throws -> PlatformSleepWindow? {
    let window = try await handleHealthKitErrors {
      try await health.readSleep(
        from: Date(timeIntervalSince1970: Double(fromUtcEpochMilliseconds) / 1000),
        to: Date(timeIntervalSince1970: Double(toUtcEpochMilliseconds) / 1000)
      )
    }
    guard let window else { return nil }
    return PlatformSleepWindow(
      bedtimeUtcEpochMilliseconds: window.bedtimeUtcEpochMilliseconds,
      wakeUtcEpochMilliseconds: window.wakeUtcEpochMilliseconds,
      asleepMinutes: window.asleepMinutes,
      sourceName: window.sourceName,
      fromGainer: window.fromGainer
    )
  }

  func writeBodyMass(
    kilograms: Double,
    measuredAtUtcEpochMilliseconds: Int64,
    syncIdentifier: String
  ) async throws -> PlatformHealthWriteStatus {
    try await handleHealthKitErrors {
      try await health.writeBodyMass(
        kilograms: kilograms,
        measuredAt: Date(timeIntervalSince1970: Double(measuredAtUtcEpochMilliseconds) / 1000),
        syncIdentifier: syncIdentifier
      )
    }
  }

  func writeSleep(
    bedtimeUtcEpochMilliseconds: Int64,
    wakeUtcEpochMilliseconds: Int64,
    syncIdentifier: String
  ) async throws -> PlatformHealthWriteStatus {
    try await handleHealthKitErrors {
      try await health.writeSleep(
        bedtime: Date(timeIntervalSince1970: Double(bedtimeUtcEpochMilliseconds) / 1000),
        wake: Date(timeIntervalSince1970: Double(wakeUtcEpochMilliseconds) / 1000),
        syncIdentifier: syncIdentifier
      )
    }
  }

  func requestWorkoutWriteAuthorization() async throws -> PlatformAuthorizationRequestResult {
    try await handleHealthKitErrors { try await health.requestWorkoutWriteAuthorization() }
  }

  func exportCompletedWorkout(
    accountId: String,
    workoutId: String,
    syncVersion: Int64,
    startedAtUtcEpochMilliseconds: Int64,
    completedAtUtcEpochMilliseconds: Int64
  ) async throws -> PlatformWorkoutExportResult {
    let result = try await handleHealthKitErrors {
      try await health.exportCompletedWorkout(
        accountId: accountId,
        workoutId: workoutId,
        syncVersion: syncVersion,
        startedAt: Date(timeIntervalSince1970: Double(startedAtUtcEpochMilliseconds) / 1000),
        completedAt: Date(timeIntervalSince1970: Double(completedAtUtcEpochMilliseconds) / 1000)
      )
    }
    return PlatformWorkoutExportResult(
      status: result.status,
      syncIdentifier: result.syncIdentifier,
      syncVersion: result.syncVersion
    )
  }

  func publishNeutralExtensionSnapshot(
    schemaVersion: Int64,
    generation: Int64,
    updatedAtUtcEpochMilliseconds: Int64,
    availableRoutes: [String]
  ) async throws {
    guard schemaVersion <= Int64(Int.max), generation <= Int64(Int.max),
      let snapshot = GainerNeutralExtensionSnapshot(
        schemaVersion: Int(schemaVersion),
        generation: Int(generation),
        updatedAtUtcEpochMilliseconds: updatedAtUtcEpochMilliseconds,
        availableRoutes: availableRoutes
      )
    else { throw NativeExtensionSnapshotError.invalidSnapshot }
    try extensionSnapshots.publish(snapshot)
  }

  func clearExtensionSnapshot(minimumGeneration: Int64) async throws {
    guard minimumGeneration <= Int64(Int.max), minimumGeneration >= 0 else {
      throw NativeExtensionSnapshotError.invalidSnapshot
    }
    try extensionSnapshots.clear(minimumGeneration: Int(minimumGeneration))
  }

  func startLiveActivity(state: PlatformLiveActivityState) async throws -> Bool {
    guard #available(iOS 17.0, *) else { return false }
    return try await liveActivities.start(state)
  }

  func updateLiveActivity(state: PlatformLiveActivityState) async throws -> Bool {
    guard #available(iOS 17.0, *) else { return false }
    return try await liveActivities.update(state)
  }

  func endLiveActivity(sessionId: String) async throws {
    guard #available(iOS 17.0, *) else { return }
    await liveActivities.end(sessionId: sessionId)
  }

  func endAllLiveActivities() async throws {
    guard #available(iOS 17.0, *) else { return }
    await liveActivities.endAll()
  }

  func areLiveActivitiesEnabled() async throws -> Bool {
    guard #available(iOS 17.0, *) else { return false }
    return liveActivities.isEnabled
  }

  func openAppSettings() async throws {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    _ = await UIApplication.shared.open(url)
  }

  func readPendingRoute() async throws -> PlatformRoute? {
    guard let route = try routeStore.readPendingRoute() else { return nil }
    return PlatformRoute(
      destination: route.destination,
      source: route.source,
      createdAtUtcEpochMilliseconds: route.createdAtUtcEpochMilliseconds
    )
  }

  func clearPendingRoute() async throws {
    try routeStore.clearPendingRoute()
  }

  func retryPendingRoute() async throws {
    await NativeRouteDispatcher.shared.dispatchPendingRoute()
  }

  private func handleHealthKitErrors<T>(
    _ operation: () async throws -> T
  ) async throws -> T {
    do {
      return try await operation()
    } catch let error as NativeHealthKitError {
      throw PigeonError(code: error.flutterCode, message: error.safeMessage, details: nil)
    }
  }
}
