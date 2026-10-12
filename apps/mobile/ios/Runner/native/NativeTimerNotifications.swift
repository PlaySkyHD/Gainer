import CryptoKit
import Flutter
import Foundation
import UserNotifications

protocol LocalNotificationCenter {
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func notificationSettings() async -> UNNotificationSettings
  func add(_ request: UNNotificationRequest) async throws
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
  func pendingNotificationRequests() async -> [UNNotificationRequest]
  func deliveredNotificationIdentifiers() async -> [String]
}

extension UNUserNotificationCenter: LocalNotificationCenter {
  func deliveredNotificationIdentifiers() async -> [String] {
    let notifications = await deliveredNotifications()
    return notifications.map { $0.request.identifier }
  }
}

@MainActor
final class NativeTimerNotifications {
  private let notificationCenter: LocalNotificationCenter
  private let defaults: UserDefaults
  private let identifierPrefix = "com.gainer.mobile.pause."

  init(
    notificationCenter: LocalNotificationCenter = UNUserNotificationCenter.current(),
    defaults: UserDefaults = .standard
  ) {
    self.notificationCenter = notificationCenter
    self.defaults = defaults
  }

  func requestPermission() async throws -> Bool {
    let settings = await notificationCenter.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .denied:
      return false
    case .notDetermined:
      return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
    @unknown default:
      return false
    }
  }

  func schedule(workoutId: String, generation: Int64, targetAtUtcEpochMilliseconds: Int64) async throws {
    guard !workoutId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, generation >= 0 else {
      throw PigeonError(code: "invalid_timer_notification", message: "The pause timer notification has invalid identity or generation.", details: nil)
    }
    let workoutKey = key(for: workoutId)
    let generationKey = "\(identifierPrefix)generation.\(workoutKey)"
    let cancelledKey = "\(identifierPrefix)cancelled.\(workoutKey)"
    let previousGeneration = defaults.object(forKey: generationKey) as? Int64
    if let previousGeneration, generation < previousGeneration { return }
    let cancelledGeneration = defaults.object(forKey: cancelledKey) as? Int64
    if let cancelledGeneration, generation <= cancelledGeneration { return }

    let identifier = "\(identifierPrefix)\(workoutKey).\(generation)"
    defaults.set(generation, forKey: generationKey)
    let target = Date(timeIntervalSince1970: TimeInterval(targetAtUtcEpochMilliseconds) / 1000)
    let delay = target.timeIntervalSinceNow
    guard delay > 0 else {
      let pending = await notificationCenter.pendingNotificationRequests()
      let pendingIdentifiers = pending.map(\.identifier)
      let deliveredIdentifiers = await notificationCenter.deliveredNotificationIdentifiers()
      let staleIdentifiers = (pendingIdentifiers + deliveredIdentifiers).filter { $0.hasPrefix("\(identifierPrefix)\(workoutKey).") }
      notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
      notificationCenter.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
      defaults.set(generation, forKey: cancelledKey)
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "Pause beendet"
    content.body = "Dein Training wartet auf dich."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
    try await notificationCenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    let latestGeneration = defaults.object(forKey: generationKey) as? Int64 ?? generation
    let latestCancelledGeneration = defaults.object(forKey: cancelledKey) as? Int64
    if latestGeneration > generation || (latestCancelledGeneration.map { $0 >= generation } ?? false) {
      notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
      notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
      return
    }
    let pending = await notificationCenter.pendingNotificationRequests()
    let delivered = await notificationCenter.deliveredNotificationIdentifiers()
    let staleIdentifiers = (pending.map(\.identifier) + delivered).filter {
      $0.hasPrefix("\(identifierPrefix)\(workoutKey).") && $0 != identifier
    }
    notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
    notificationCenter.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
  }

  func cancel(workoutId: String) async {
    let workoutKey = key(for: workoutId)
    let generationKey = "\(identifierPrefix)generation.\(workoutKey)"
    let cancelledKey = "\(identifierPrefix)cancelled.\(workoutKey)"
    if let generation = defaults.object(forKey: generationKey) as? Int64 {
      defaults.set(generation, forKey: cancelledKey)
    }
    let pending = await notificationCenter.pendingNotificationRequests()
    let delivered = await notificationCenter.deliveredNotificationIdentifiers()
    let identifiers = (pending.map(\.identifier) + delivered).filter { $0.hasPrefix("\(identifierPrefix)\(workoutKey).") }
    notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    // Keep the generation fence so an in-flight stale schedule cannot revive a canceled timer.
  }

  private func key(for workoutId: String) -> String {
    let digest = SHA256.hash(data: Data(workoutId.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
