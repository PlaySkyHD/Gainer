import CryptoKit
import Flutter
import HealthKit
import UIKit
import XCTest
import UserNotifications
@testable import Runner

class RunnerTests: XCTestCase {

  func testExtensionSnapshotAllowsOnlyKnownNeutralRoutes() throws {
    let snapshot = try XCTUnwrap(
      GainerNeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: 2,
        updatedAtUtcEpochMilliseconds: 1_800_000_000_000,
        availableRoutes: ["training", "checkIn", "training"]
      )
    )
    XCTAssertEqual(snapshot.availableRoutes, ["checkIn", "training"])
    XCTAssertNil(
      GainerNeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: 3,
        updatedAtUtcEpochMilliseconds: 1_800_000_000_000,
        availableRoutes: ["account", "nutrition"]
      )
    )
  }

  func testExtensionRouteParserRejectsUnknownRoutesAndExtraParameters() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(
      GainerPendingRoute.parse(
        url: try XCTUnwrap(URL(string: "gainer://route/training?source=widget")),
        source: "shortcut",
        now: now
      )?.source,
      "widget"
    )
    XCTAssertNil(
      GainerPendingRoute.parse(
        url: try XCTUnwrap(URL(string: "gainer://route/account?source=widget")),
        source: "widget",
        now: now
      )
    )
    XCTAssertNil(
      GainerPendingRoute.parse(
        url: try XCTUnwrap(URL(string: "gainer://route/training?source=widget&token=secret")),
        source: "widget",
        now: now
      )
    )
  }

  func testExtensionSnapshotStoreRejectsStaleGenerationAndExpiresRoutes() throws {
    let suiteName = "NativeExtensionSnapshotStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var reloadCount = 0
    let store = NativeExtensionSnapshotStore(
      defaultsProvider: { _ in defaults },
      reloadTimelines: { reloadCount += 1 }
    )
    let first = try XCTUnwrap(
      GainerNeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: 5,
        updatedAtUtcEpochMilliseconds: 1_800_000_000_000,
        availableRoutes: ["training"]
      )
    )
    try store.publish(first)
    XCTAssertThrowsError(
      try store.publish(
        XCTUnwrap(
          GainerNeutralExtensionSnapshot(
            schemaVersion: 1,
            generation: 4,
            updatedAtUtcEpochMilliseconds: 1_800_000_000_001,
            availableRoutes: ["checkIn"]
          )
        )
      )
    )
    XCTAssertEqual(reloadCount, 1)

    try store.clear(minimumGeneration: 6)
    XCTAssertEqual(
      defaults.integer(forKey: GainerNeutralExtensionSnapshot.snapshotMinimumGenerationDefaultsKey),
      6
    )
    XCTAssertThrowsError(try store.publish(first), "A delayed publish from the logged-out session must be rejected")
    let nextSession = try XCTUnwrap(
      GainerNeutralExtensionSnapshot(
        schemaVersion: 1,
        generation: 7,
        updatedAtUtcEpochMilliseconds: 1_800_000_000_002,
        availableRoutes: ["checkIn"]
      )
    )
    try store.publish(nextSession)
    XCTAssertEqual(reloadCount, 3)

    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let route = try XCTUnwrap(
      GainerPendingRoute(
        destination: "training",
        source: "widget",
        createdAtUtcEpochMilliseconds: Int64(createdAt.timeIntervalSince1970 * 1000)
      )
    )
    try store.recordRoute(route)
    XCTAssertEqual(try store.readPendingRoute(now: createdAt.addingTimeInterval(60)), route)
    XCTAssertEqual(try store.consumePendingRoute(now: createdAt.addingTimeInterval(60)), route)
    XCTAssertNil(try store.readPendingRoute(now: createdAt.addingTimeInterval(60)))
    try store.recordRoute(route)
    XCTAssertNil(try store.readPendingRoute(now: createdAt.addingTimeInterval(601)))
    try store.clearPendingRoute()
  }

  @MainActor
  func testNewRouteArrivingDuringDispatchIsRetainedAndDispatched() async throws {
    let suiteName = "NativeRouteDispatcherTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = NativeExtensionSnapshotStore(defaultsProvider: { _ in defaults })
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let firstRoute = try XCTUnwrap(
      GainerPendingRoute(
        destination: "training",
        source: "widget",
        createdAtUtcEpochMilliseconds: now - 1
      )
    )
    let replacementRoute = try XCTUnwrap(
      GainerPendingRoute(
        destination: "checkIn",
        source: "shortcut",
        createdAtUtcEpochMilliseconds: now
      )
    )
    try store.recordRoute(firstRoute)
    let flutterApi = BlockingMobileRouteFlutterApi()
    let dispatcher = NativeRouteDispatcher(snapshotStore: store, flutterApi: flutterApi)
    let firstDispatch = Task { await dispatcher.dispatchPendingRoute() }
    await fulfillment(of: [flutterApi.firstDispatchStarted], timeout: 2)

    try store.recordRoute(replacementRoute)
    await dispatcher.dispatchPendingRoute()
    flutterApi.resumeFirstDispatch()
    await firstDispatch.value
    await fulfillment(of: [flutterApi.secondDispatchStarted], timeout: 2)

    XCTAssertEqual(flutterApi.routes.map(\.destination), ["training", "checkIn"])
    XCTAssertNil(try store.readPendingRoute())
  }

  func testHealthExportIdentifierIsStableOpaqueAndAccountScoped() throws {
    let accountId = "a1111111-1111-4111-8111-111111111111"
    let workoutId = "b2222222-2222-4222-8222-222222222222"
    let first = try XCTUnwrap(
      NativeHealthKit.stableWorkoutSyncIdentifier(accountId: accountId, workoutId: workoutId)
    )
    XCTAssertEqual(
      first,
      NativeHealthKit.stableWorkoutSyncIdentifier(
        accountId: accountId.uppercased(),
        workoutId: workoutId.uppercased()
      )
    )
    XCTAssertNotEqual(
      first,
      NativeHealthKit.stableWorkoutSyncIdentifier(
        accountId: "c3333333-3333-4333-8333-333333333333",
        workoutId: workoutId
      )
    )
    XCTAssertFalse(first.contains(accountId))
    XCTAssertFalse(first.contains(workoutId))
    XCTAssertNil(NativeHealthKit.stableWorkoutSyncIdentifier(accountId: "account", workoutId: workoutId))
  }

  func testHealthExportRequiresACompletedBoundedInterval() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertTrue(
      NativeHealthKit.validWorkoutInterval(
        startedAt: now.addingTimeInterval(-3600),
        completedAt: now,
        now: now
      )
    )
    XCTAssertFalse(
      NativeHealthKit.validWorkoutInterval(
        startedAt: now.addingTimeInterval(60),
        completedAt: now,
        now: now
      )
    )
    XCTAssertFalse(
      NativeHealthKit.validWorkoutInterval(
        startedAt: now.addingTimeInterval(-25 * 3600),
        completedAt: now,
        now: now
      )
    )
  }

  func testSleepAnalysisCountsOnlyAsleepPhasesAndUsesEarliestStartAndLatestEnd() throws {
    let night = Date(timeIntervalSince1970: 1_800_000_000)
    func segment(_ value: HKCategoryValueSleepAnalysis, _ from: TimeInterval, _ to: TimeInterval)
      -> NativeSleepSegment
    {
      NativeSleepSegment(
        start: night.addingTimeInterval(from * 60),
        end: night.addingTimeInterval(to * 60),
        rawValue: value.rawValue,
        sourceName: "Watch",
        fromGainer: false
      )
    }
    let window = try XCTUnwrap(
      NativeSleepAnalysis.summarize([
        segment(.inBed, -30, 480),
        segment(.asleepCore, 0, 120),
        segment(.asleepDeep, 120, 180),
        segment(.awake, 180, 195),
        segment(.asleepREM, 195, 255),
        segment(.asleepUnspecified, 255, 300),
      ])
    )
    XCTAssertEqual(window.bedtimeUtcEpochMilliseconds, Int64(night.timeIntervalSince1970 * 1000))
    XCTAssertEqual(
      window.wakeUtcEpochMilliseconds,
      Int64(night.addingTimeInterval(300 * 60).timeIntervalSince1970 * 1000)
    )
    XCTAssertEqual(window.asleepMinutes, 285)
    XCTAssertFalse(window.fromGainer)
    XCTAssertNil(NativeSleepAnalysis.summarize([segment(.inBed, 0, 480), segment(.awake, 0, 30)]))
  }

  func testSleepAnalysisCountsOverlappingSourcesOnceAndPrefersForeignSamples() throws {
    let night = Date(timeIntervalSince1970: 1_800_000_000)
    func segment(_ from: TimeInterval, _ to: TimeInterval, gainer: Bool) -> NativeSleepSegment {
      NativeSleepSegment(
        start: night.addingTimeInterval(from * 60),
        end: night.addingTimeInterval(to * 60),
        rawValue: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        sourceName: gainer ? "Gainer" : "iPhone",
        fromGainer: gainer
      )
    }
    let mixed = try XCTUnwrap(
      NativeSleepAnalysis.summarize([
        segment(0, 120, gainer: false),
        segment(60, 180, gainer: false),
        segment(-60, 600, gainer: true),
      ])
    )
    XCTAssertEqual(mixed.asleepMinutes, 180)
    XCTAssertEqual(mixed.sourceName, "iPhone")
    XCTAssertFalse(mixed.fromGainer)

    let own = try XCTUnwrap(NativeSleepAnalysis.summarize([segment(0, 450, gainer: true)]))
    XCTAssertEqual(own.asleepMinutes, 450)
    XCTAssertTrue(own.fromGainer)
  }

  func testCheckInSyncIdentifierMustBeGainerScoped() {
    XCTAssertTrue(NativeHealthKit.validCheckInSyncIdentifier("gainer-checkin-a1-2026-10-18-weight"))
    XCTAssertFalse(NativeHealthKit.validCheckInSyncIdentifier("other-2026-10-18"))
  }

  func testFreshInstallClearsCheckpointsRetainedByTheKeychain() throws {
    let keychain = FakeSessionKeychainStore()
    keychain.values["com.gainer.mobile.secure-session.v1|checkpoint.old"] = Data([1, 2, 3])
    let marker = FakeInstallMarkerStore()
    let session = SecureSessionKeychain(store: keychain, installMarkerStore: marker)

    XCTAssertNil(try session.readCheckpoint(apiOrigin: "https://api.example.test"))
    XCTAssertEqual(
      Set(keychain.deletedServices),
      Set(["com.gainer.mobile.secure-session.v1", "com.gainer.mobile.pending-handover.v1"])
    )
    XCTAssertTrue(marker.hasSeenCurrentInstall)
  }

  func testCheckpointIsBoundToCanonicalAPIOriginAndDeviceOnlyAccessibility() throws {
    let keychain = FakeSessionKeychainStore()
    let marker = FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    let session = SecureSessionKeychain(store: keychain, installMarkerStore: marker)
    let checkpoint = Data([0, 1, 127, 128, 255])

    try session.writeCheckpoint(checkpoint, apiOrigin: "https://api.example.test")

    XCTAssertEqual(
      try session.readCheckpoint(apiOrigin: "https://API.EXAMPLE.TEST:443"),
      checkpoint
    )
    try session.writeCheckpoint(Data([7]), apiOrigin: "https://[2001:db8::1]")
    XCTAssertEqual(
      try session.readCheckpoint(apiOrigin: "https://[2001:db8::1]:443"),
      Data([7])
    )
    XCTAssertNil(try session.readCheckpoint(apiOrigin: "https://other.example.test"))
    XCTAssertEqual(keychain.lastAccessibility, .whenUnlockedThisDeviceOnly)
    XCTAssertEqual(keychain.lastAccount?.hasPrefix("checkpoint."), true)

    try session.writeCheckpoint(Data([9]), apiOrigin: "http://[::1]:8080")
    XCTAssertEqual(try session.readCheckpoint(apiOrigin: "http://[::1]:8080"), Data([9]))
  }

  func testCheckpointRejectsInsecureOrNonOriginURLs() {
    let session = SecureSessionKeychain(
      store: FakeSessionKeychainStore(),
      installMarkerStore: FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    )

    XCTAssertThrowsError(try session.readCheckpoint(apiOrigin: "http://api.example.test"))
    XCTAssertThrowsError(try session.readCheckpoint(apiOrigin: "http://[2001:db8::1]"))
    XCTAssertThrowsError(try session.readCheckpoint(apiOrigin: "https://api.example.test/path"))
    XCTAssertThrowsError(try session.readCheckpoint(apiOrigin: "https://user:pass@example.test"))
  }

  func testClearRemovesOnlyTheSelectedOriginCheckpoint() throws {
    let keychain = FakeSessionKeychainStore()
    let session = SecureSessionKeychain(
      store: keychain,
      installMarkerStore: FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    )
    try session.writeCheckpoint(Data([1]), apiOrigin: "https://one.example.test")
    try session.writeCheckpoint(Data([2]), apiOrigin: "https://two.example.test")

    try session.clearCheckpoint(apiOrigin: "https://one.example.test")

    XCTAssertNil(try session.readCheckpoint(apiOrigin: "https://one.example.test"))
    XCTAssertEqual(try session.readCheckpoint(apiOrigin: "https://two.example.test"), Data([2]))
  }

  func testWriteFailureKeepsThePreviouslyStoredCheckpoint() throws {
    let keychain = FakeSessionKeychainStore()
    let session = SecureSessionKeychain(
      store: keychain,
      installMarkerStore: FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    )
    try session.writeCheckpoint(Data([1, 2]), apiOrigin: "https://api.example.test")
    keychain.writeError = TestFailure.writeRejected

    XCTAssertThrowsError(
      try session.writeCheckpoint(Data([3, 4]), apiOrigin: "https://api.example.test")
    )
    XCTAssertEqual(
      try session.readCheckpoint(apiOrigin: "https://api.example.test"),
      Data([1, 2])
    )
  }

  func testPendingHandoverIsSeparateAndBoundToOriginAndAccount() throws {
    let accountA = "a1111111-1111-4111-8111-111111111111"
    let accountB = "b2222222-2222-4222-8222-222222222222"
    let keychain = FakeSessionKeychainStore()
    let session = SecureSessionKeychain(
      store: keychain,
      installMarkerStore: FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    )
    let record = Data("opaque pending handover".utf8)
    try session.writeCheckpoint(Data([7, 8, 9]), apiOrigin: "https://api.example.test")

    try session.writePendingHandover(
      record,
      apiOrigin: "https://api.example.test",
      accountId: accountA
    )

    XCTAssertEqual(
      try session.readPendingHandover(apiOrigin: "https://api.example.test", accountId: accountA.uppercased()),
      record
    )
    XCTAssertNil(try session.readPendingHandover(apiOrigin: "https://api.example.test", accountId: accountB))
    XCTAssertNil(try session.readPendingHandover(apiOrigin: "https://other.example.test", accountId: accountA))
    XCTAssertEqual(keychain.lastService, "com.gainer.mobile.pending-handover.v1")
    XCTAssertEqual(keychain.lastAccessibility, .whenUnlockedThisDeviceOnly)
    XCTAssertEqual(try session.readCheckpoint(apiOrigin: "https://api.example.test"), Data([7, 8, 9]))

    try session.clearPendingHandover(apiOrigin: "https://api.example.test", accountId: accountA)
    XCTAssertNil(try session.readPendingHandover(apiOrigin: "https://api.example.test", accountId: accountA))
  }

  func testPendingHandoverRejectsEmptyOrOversizedRecordsAndBlankAccountIds() {
    let session = SecureSessionKeychain(
      store: FakeSessionKeychainStore(),
      installMarkerStore: FakeInstallMarkerStore(hasSeenCurrentInstall: true)
    )

    XCTAssertThrowsError(try session.writePendingHandover(Data(), apiOrigin: "https://api.example.test", accountId: "a1111111-1111-4111-8111-111111111111"))
    XCTAssertThrowsError(try session.writePendingHandover(Data(repeating: 0, count: 64 * 1024 + 1), apiOrigin: "https://api.example.test", accountId: "a1111111-1111-4111-8111-111111111111"))
    XCTAssertThrowsError(try session.readPendingHandover(apiOrigin: "https://api.example.test", accountId: "  "))
    XCTAssertThrowsError(try session.readPendingHandover(apiOrigin: "https://api.example.test", accountId: "account-a"))
  }

  @MainActor
  func testTimerNotificationReplacesOlderGenerationAndCancelRemovesIt() async throws {
    let suiteName = "NativeTimerNotificationsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let center = FakeLocalNotificationCenter()
    let notifications = NativeTimerNotifications(notificationCenter: center, defaults: defaults)
    let target = Int64(Date().addingTimeInterval(120).timeIntervalSince1970 * 1000)

    try await notifications.schedule(workoutId: "workout-a", generation: 4, targetAtUtcEpochMilliseconds: target)
    try await notifications.schedule(workoutId: "workout-a", generation: 5, targetAtUtcEpochMilliseconds: target + 60_000)
    try await notifications.schedule(workoutId: "workout-a", generation: 3, targetAtUtcEpochMilliseconds: target + 30_000)

    XCTAssertEqual(center.pending.count, 1)
    XCTAssertTrue(center.pending.keys.first?.hasSuffix(".5") == true)
    XCTAssertEqual(defaults.object(forKey: "com.gainer.mobile.pause.generation.\(notificationKey(for: "workout-a"))") as? Int64, 5)

    await notifications.cancel(workoutId: "workout-a")
    XCTAssertTrue(center.pending.isEmpty)
    XCTAssertTrue(center.removedDelivered.contains { $0.hasPrefix("com.gainer.mobile.pause.") })
    try await notifications.schedule(workoutId: "workout-a", generation: 5, targetAtUtcEpochMilliseconds: target + 90_000)
    XCTAssertTrue(center.pending.isEmpty, "A late schedule from the canceled timer generation must stay canceled.")
  }

  func testTimerNotificationShowsBannerWithSoundWhileAppIsOpen() {
    XCTAssertEqual(
      TimerNotificationDelegate.presentationOptions(forIdentifier: "com.gainer.mobile.pause.\(notificationKey(for: "workout-a")).4"),
      [.banner, .sound, .list]
    )
    XCTAssertNil(TimerNotificationDelegate.presentationOptions(forIdentifier: "com.gainer.mobile.other.4"))
    XCTAssertNil(TimerNotificationDelegate.presentationOptions(forIdentifier: "reminder.weekly"))
  }

  @MainActor
  func testTimerNotificationTextIsNeutralAndUsesTheAgreedWording() async throws {
    let suiteName = "NativeTimerNotificationsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let center = FakeLocalNotificationCenter()
    let notifications = NativeTimerNotifications(notificationCenter: center, defaults: defaults)
    let target = Int64(Date().addingTimeInterval(120).timeIntervalSince1970 * 1000)

    try await notifications.schedule(workoutId: "workout-a", generation: 1, targetAtUtcEpochMilliseconds: target)

    let request = try XCTUnwrap(center.pending.values.first)
    XCTAssertEqual(request.content.title, "Pause vorbei")
    XCTAssertEqual(request.content.body, "Weiter mit dem nächsten Satz.")
  }

  @MainActor
  func testTimerNotificationAcceptsSoundIdAndKeepsSystemSoundWithoutBundledFile() async throws {
    let suiteName = "NativeTimerNotificationsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let center = FakeLocalNotificationCenter()
    let notifications = NativeTimerNotifications(notificationCenter: center, defaults: defaults)
    let target = Int64(Date().addingTimeInterval(120).timeIntervalSince1970 * 1000)

    try await notifications.schedule(workoutId: "workout-a", generation: 1, targetAtUtcEpochMilliseconds: target, soundId: "gong")

    let request = try XCTUnwrap(center.pending.values.first)
    XCTAssertNotNil(request.content.sound)
  }

  func testTimerSoundIdMapsToFileNameAndFallsBackToDefault() {
    XCTAssertEqual(NativeTimerSounds.fileName(forSoundId: "gong"), "gong.wav")
    XCTAssertEqual(NativeTimerSounds.fileName(forSoundId: "digital_alarm"), "digital_alarm.wav")
    XCTAssertNil(NativeTimerSounds.fileName(forSoundId: "system"))
    XCTAssertEqual(NativeTimerSounds.fileName(forSoundId: "unknown"), "digital_alarm.wav")
    XCTAssertEqual(NativeTimerSounds.fileName(forSoundId: "../gong"), "digital_alarm.wav")
    XCTAssertEqual(NativeTimerSounds.resolvedSoundId(""), "digital_alarm")
  }

  private func notificationKey(for value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

@MainActor
private final class BlockingMobileRouteFlutterApi: MobileRouteFlutterApiProtocol {
  let firstDispatchStarted = XCTestExpectation(description: "first native route dispatched")
  let secondDispatchStarted = XCTestExpectation(description: "replacement native route dispatched")
  private(set) var routes: [PlatformRoute] = []
  private var firstDispatchContinuation: CheckedContinuation<Void, Never>?

  func dispatchRoute(route routeArg: PlatformRoute) async throws {
    routes.append(routeArg)
    if routes.count == 1 {
      firstDispatchStarted.fulfill()
      await withCheckedContinuation { continuation in
        firstDispatchContinuation = continuation
      }
    } else if routes.count == 2 {
      secondDispatchStarted.fulfill()
    }
  }

  func resumeFirstDispatch() {
    firstDispatchContinuation?.resume()
    firstDispatchContinuation = nil
  }
}

private final class FakeSessionKeychainStore: SessionKeychainStore {
  var values: [String: Data] = [:]
  var deletedServices: [String] = []
  var lastAccessibility: SessionKeychainAccessibility?
  var lastAccount: String?
  var lastService: String?
  var writeError: Error?

  func read(service: String, account: String) throws -> Data? {
    values["\(service)|\(account)"]
  }

  func write(
    _ data: Data,
    service: String,
    account: String,
    accessibility: SessionKeychainAccessibility
  ) throws {
    if let writeError { throw writeError }
    values["\(service)|\(account)"] = data
    lastAccessibility = accessibility
    lastAccount = account
    lastService = service
  }

  func delete(service: String, account: String) throws {
    values.removeValue(forKey: "\(service)|\(account)")
  }

  func deleteAll(service: String) throws {
    deletedServices.append(service)
    values = values.filter { !$0.key.hasPrefix("\(service)|") }
  }
}

private enum TestFailure: Error {
  case writeRejected
}

private final class FakeInstallMarkerStore: InstallMarkerStore {
  private(set) var hasSeenCurrentInstall: Bool

  init(hasSeenCurrentInstall: Bool = false) {
    self.hasSeenCurrentInstall = hasSeenCurrentInstall
  }

  func markCurrentInstall() {
    hasSeenCurrentInstall = true
  }
}

private final class FakeLocalNotificationCenter: LocalNotificationCenter {
  var pending: [String: UNNotificationRequest] = [:]
  var removedDelivered: [String] = []
  var deliveredIdentifiers: [String] = []

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

  func notificationSettings() async -> UNNotificationSettings {
    await UNUserNotificationCenter.current().notificationSettings()
  }

  func add(_ request: UNNotificationRequest) async throws {
    pending[request.identifier] = request
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    identifiers.forEach { pending.removeValue(forKey: $0) }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    removedDelivered.append(contentsOf: identifiers)
  }

  func pendingNotificationRequests() async -> [UNNotificationRequest] {
    Array(pending.values)
  }

  func deliveredNotificationIdentifiers() async -> [String] {
    deliveredIdentifiers
  }

  func testPauseNotificationTriggerUsesExactTargetWithoutRounding() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let target = Int64(now.timeIntervalSince1970 * 1000) + 90_250
    let interval = try XCTUnwrap(
      NativeTimerNotifications.triggerInterval(targetAtUtcEpochMilliseconds: target, now: now)
    )
    XCTAssertEqual(interval, 90.25, accuracy: 0.0001)

    let subSecond = Int64(now.timeIntervalSince1970 * 1000) + 300
    XCTAssertEqual(
      try XCTUnwrap(NativeTimerNotifications.triggerInterval(targetAtUtcEpochMilliseconds: subSecond, now: now)),
      0.3,
      accuracy: 0.0001
    )
  }

  func testPauseNotificationTriggerRejectsElapsedTarget() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let elapsed = Int64(now.timeIntervalSince1970 * 1000)
    XCTAssertNil(NativeTimerNotifications.triggerInterval(targetAtUtcEpochMilliseconds: elapsed, now: now))
    XCTAssertNil(NativeTimerNotifications.triggerInterval(targetAtUtcEpochMilliseconds: elapsed - 5_000, now: now))
  }
}
