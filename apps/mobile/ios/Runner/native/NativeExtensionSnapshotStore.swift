import Foundation
import WidgetKit

final class NativeExtensionSnapshotStore {
  private let defaultsProvider: (String) -> UserDefaults?
  private let reloadTimelines: () -> Void

  init(
    defaultsProvider: @escaping (String) -> UserDefaults? = UserDefaults.init(suiteName:),
    reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
  ) {
    self.defaultsProvider = defaultsProvider
    self.reloadTimelines = reloadTimelines
  }

  static var appGroupIdentifier: String {
    guard let value = Bundle.main.object(
      forInfoDictionaryKey: GainerNeutralExtensionSnapshot.appGroupInfoKey
    ) as? String,
      value.hasPrefix("group."), !value.contains("$(")
    else { return GainerNeutralExtensionSnapshot.appGroupFallback }
    return value
  }

  func publish(_ snapshot: GainerNeutralExtensionSnapshot) throws {
    guard let defaults = defaultsProvider(Self.appGroupIdentifier) else {
      throw NativeExtensionSnapshotError.appGroupUnavailable
    }

    let minimumGeneration = defaults.object(
      forKey: GainerNeutralExtensionSnapshot.snapshotMinimumGenerationDefaultsKey
    ) as? Int ?? 0
    guard snapshot.generation > minimumGeneration else {
      throw NativeExtensionSnapshotError.staleGeneration
    }

    if let existingData = defaults.data(
      forKey: GainerNeutralExtensionSnapshot.snapshotDefaultsKey
    ),
      let existing = try? JSONDecoder().decode(
        GainerNeutralExtensionSnapshot.self,
        from: existingData
      ),
      snapshot.generation < existing.generation
    {
      throw NativeExtensionSnapshotError.staleGeneration
    }

    defaults.set(try JSONEncoder().encode(snapshot), forKey: GainerNeutralExtensionSnapshot.snapshotDefaultsKey)
    reloadTimelines()
  }

  func clear(minimumGeneration: Int) throws {
    guard let defaults = defaultsProvider(Self.appGroupIdentifier) else {
      throw NativeExtensionSnapshotError.appGroupUnavailable
    }
    let currentMinimum = defaults.object(
      forKey: GainerNeutralExtensionSnapshot.snapshotMinimumGenerationDefaultsKey
    ) as? Int ?? 0
    let currentSnapshotGeneration = defaults.data(
      forKey: GainerNeutralExtensionSnapshot.snapshotDefaultsKey
    ).flatMap { try? JSONDecoder().decode(GainerNeutralExtensionSnapshot.self, from: $0) }
      .map(\.generation) ?? 0
    guard minimumGeneration > max(currentMinimum, currentSnapshotGeneration) else {
      throw NativeExtensionSnapshotError.staleGeneration
    }

    // Persist the tombstone before deleting the snapshot. Late Flutter calls
    // from the logged-out account can no longer republish their generation.
    defaults.set(
      minimumGeneration,
      forKey: GainerNeutralExtensionSnapshot.snapshotMinimumGenerationDefaultsKey
    )
    defaults.removeObject(forKey: GainerNeutralExtensionSnapshot.snapshotDefaultsKey)
    defaults.removeObject(forKey: GainerNeutralExtensionSnapshot.pendingRouteDefaultsKey)
    reloadTimelines()
  }

  func recordRoute(_ route: GainerPendingRoute) throws {
    guard let defaults = defaultsProvider(Self.appGroupIdentifier) else {
      throw NativeExtensionSnapshotError.appGroupUnavailable
    }
    defaults.set(try JSONEncoder().encode(route), forKey: GainerNeutralExtensionSnapshot.pendingRouteDefaultsKey)
  }

  func consumePendingRoute(now: Date = Date()) throws -> GainerPendingRoute? {
    defer { try? clearPendingRoute() }
    return try readPendingRoute(now: now)
  }

  func readPendingRoute(now: Date = Date()) throws -> GainerPendingRoute? {
    guard let defaults = defaultsProvider(Self.appGroupIdentifier) else {
      throw NativeExtensionSnapshotError.appGroupUnavailable
    }
    guard let data = defaults.data(forKey: GainerNeutralExtensionSnapshot.pendingRouteDefaultsKey),
      let route = try? JSONDecoder().decode(GainerPendingRoute.self, from: data)
    else { return nil }
    let ageMs = Int64(now.timeIntervalSince1970 * 1000) - route.createdAtUtcEpochMilliseconds
    guard ageMs >= 0, ageMs <= 10 * 60 * 1000 else { return nil }
    return route
  }

  func clearPendingRoute() throws {
    guard let defaults = defaultsProvider(Self.appGroupIdentifier) else {
      throw NativeExtensionSnapshotError.appGroupUnavailable
    }
    defaults.removeObject(forKey: GainerNeutralExtensionSnapshot.pendingRouteDefaultsKey)
  }
}

enum NativeExtensionSnapshotError: Error, Equatable {
  case appGroupUnavailable
  case staleGeneration
  case invalidSnapshot
  case invalidRoute
}
