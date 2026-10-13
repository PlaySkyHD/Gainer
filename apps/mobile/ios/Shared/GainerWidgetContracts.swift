import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum GainerRoute: String, CaseIterable, Codable {
  case training
  case checkIn
  case nutrition
}

struct GainerNeutralExtensionSnapshot: Codable, Equatable {
  static let currentSchemaVersion = 1
  static let appGroupInfoKey = "GainerAppGroupIdentifier"
  static let appGroupFallback = "group.com.example.gainerMobile"
  static let snapshotDefaultsKey = "gainer.extension.snapshot.v1"
  static let snapshotMinimumGenerationDefaultsKey = "gainer.extension.snapshot.minimumGeneration.v1"
  static let pendingRouteDefaultsKey = "gainer.extension.pendingRoute.v1"

  let schemaVersion: Int
  let generation: Int
  let updatedAtUtcEpochMilliseconds: Int64
  let availableRoutes: [String]

  init?(
    schemaVersion: Int,
    generation: Int,
    updatedAtUtcEpochMilliseconds: Int64,
    availableRoutes: [String]
  ) {
    guard schemaVersion == Self.currentSchemaVersion, generation >= 0,
      updatedAtUtcEpochMilliseconds > 0,
      Set(availableRoutes).isSubset(of: Set(GainerRoute.allCases.map(\.rawValue)))
    else { return nil }

    self.schemaVersion = schemaVersion
    self.generation = generation
    self.updatedAtUtcEpochMilliseconds = updatedAtUtcEpochMilliseconds
    self.availableRoutes = Array(Set(availableRoutes)).sorted()
  }
}

struct GainerPendingRoute: Codable, Equatable {
  let destination: String
  let source: String
  let createdAtUtcEpochMilliseconds: Int64

  init?(destination: String, source: String, createdAtUtcEpochMilliseconds: Int64) {
    guard GainerRoute(rawValue: destination) != nil,
      ["widget", "liveActivity", "shortcut"].contains(source),
      createdAtUtcEpochMilliseconds > 0
    else { return nil }
    self.destination = destination
    self.source = source
    self.createdAtUtcEpochMilliseconds = createdAtUtcEpochMilliseconds
  }

  static func parse(url: URL, source: String, now: Date = Date()) -> GainerPendingRoute? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "gainer", components.host == "route",
      components.fragment == nil
    else { return nil }

    let queryItems = components.queryItems ?? []
    guard queryItems.isEmpty
      || (queryItems.count == 1 && queryItems[0].name == "source")
    else { return nil }
    let querySource = queryItems.first?.value
    let normalizedSource = querySource ?? source
    let path = String(components.path.dropFirst())
    return GainerPendingRoute(
      destination: path,
      source: normalizedSource,
      createdAtUtcEpochMilliseconds: Int64(now.timeIntervalSince1970 * 1000)
    )
  }
}

#if canImport(ActivityKit)
@available(iOS 17.0, *)
struct GainerWorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let status: String
    let startedAt: Date
    let restEndsAt: Date?
  }

  /// A random per-activity identifier; it contains no account or workout data.
  let sessionId: String
}
#endif
