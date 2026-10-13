import AppIntents
import Foundation

private func queueRoute(_ destination: GainerRoute) throws {
  let createdAt = Int64(Date().timeIntervalSince1970 * 1000)
  guard let route = GainerPendingRoute(
    destination: destination.rawValue,
    source: "shortcut",
    createdAtUtcEpochMilliseconds: createdAt
  ) else { throw NativeExtensionSnapshotError.invalidRoute }
  try NativeExtensionSnapshotStore().recordRoute(route)
}

struct GainerOpenTrainingIntent: AppIntent {
  static let title: LocalizedStringResource = "Training öffnen"
  static let description = IntentDescription("Öffnet Gainer beim Training.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try queueRoute(.training)
    return .result()
  }
}

struct GainerOpenCheckInIntent: AppIntent {
  static let title: LocalizedStringResource = "Check-in öffnen"
  static let description = IntentDescription("Öffnet Gainer beim Körper-Check-in.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try queueRoute(.checkIn)
    return .result()
  }
}

struct GainerOpenNutritionIntent: AppIntent {
  static let title: LocalizedStringResource = "Ernährung öffnen"
  static let description = IntentDescription("Öffnet Gainer bei der Ernährung.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try queueRoute(.nutrition)
    return .result()
  }
}

struct GainerAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: GainerOpenTrainingIntent(),
      phrases: ["Training in \(.applicationName) öffnen"],
      shortTitle: "Training",
      systemImageName: "figure.strengthtraining.traditional"
    )
    AppShortcut(
      intent: GainerOpenCheckInIntent(),
      phrases: ["Check-in in \(.applicationName) öffnen"],
      shortTitle: "Check-in",
      systemImageName: "scalemass"
    )
    AppShortcut(
      intent: GainerOpenNutritionIntent(),
      phrases: ["Ernährung in \(.applicationName) öffnen"],
      shortTitle: "Ernährung",
      systemImageName: "fork.knife"
    )
  }
}
