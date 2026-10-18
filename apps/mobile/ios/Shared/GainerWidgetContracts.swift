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
    /// Nur bei ausdrücklicher Detailfreigabe. Erfasste Ist-Werte gehören nie hierher;
    /// `targetText` ist nur der Zielwert des nächsten Satzes aus dem Vorwert.
    struct Detail: Codable, Hashable {
      let title: String
      let exerciseName: String
      let setIndex: Int
      let setCount: Int
      /// Optional, damit ältere Zustände ohne diese Felder weiter decodierbar bleiben.
      let exerciseIndex: Int?
      let exerciseCount: Int?
      let targetText: String?
    }

    let startedAt: Date
    /// One of `ready`, `running`, `paused`, `expired`.
    let timerPhase: String
    /// Only while a rest runs; the system renders the countdown from it.
    let timerTargetAt: Date?
    let pausedRemainingSeconds: Int?
    /// Dauer der aktuellen Pause; Grundlage des Fortschrittsbalkens. Optional wie oben.
    let restDurationSeconds: Int?
    let expired: Bool
    let detail: Detail?
  }

  /// Workout identifier (UUID), one activity per training. It contains no account data.
  let sessionId: String
}

/// Live Activity einer Cardio-Einheit mit Pulsgurt. Sie enthält nur Puls und Zielbereich,
/// keine Konto- oder Verlaufsdaten.
@available(iOS 17.0, *)
struct GainerCardioActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// Letzter Puls; nil, solange noch kein Messwert vorliegt.
    let bpm: Int?
    let zoneLowBpm: Int?
    let zoneHighBpm: Int?
    /// One of `inZone`, `above`, `below`, `noSignal`, `none`.
    let zoneState: String
    let updatedAt: Date
  }

  /// Cardio-Session (UUID), eine Activity je Einheit.
  let sessionId: String
  /// Anzeigename der Sportart, z. B. „Rad-Ergometer“.
  let title: String
  let startedAt: Date
}
#endif
