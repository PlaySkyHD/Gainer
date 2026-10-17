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
  nonisolated static let timerIdentifierPrefix = "com.gainer.mobile.pause."

  private let notificationCenter: LocalNotificationCenter
  private let defaults: UserDefaults
  private let identifierPrefix = NativeTimerNotifications.timerIdentifierPrefix

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
    guard let delay = Self.triggerInterval(targetAtUtcEpochMilliseconds: targetAtUtcEpochMilliseconds) else {
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
    content.title = "Pause vorbei"
    content.body = "Weiter mit dem nächsten Satz."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
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

  /// Sekunden bis zum Pausenende, exakt aus dem absoluten Zielzeitpunkt. Ohne
  /// Aufrunden, damit die Benachrichtigung zum selben Zeitpunkt wie die Live
  /// Activity erscheint. Nil, wenn der Zeitpunkt schon vergangen ist.
  nonisolated static func triggerInterval(targetAtUtcEpochMilliseconds: Int64, now: Date = Date()) -> TimeInterval? {
    let target = Date(timeIntervalSince1970: TimeInterval(targetAtUtcEpochMilliseconds) / 1000)
    let interval = target.timeIntervalSince(now)
    return interval > 0 ? interval : nil
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

/// Zeigt Pausen-Benachrichtigungen auch bei geöffneter App als Banner mit Ton.
/// Alle anderen Benachrichtigungen gehen an den zuvor gesetzten Delegate.
final class TimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let previousDelegate: UNUserNotificationCenterDelegate?

  init(previousDelegate: UNUserNotificationCenterDelegate?) {
    self.previousDelegate = previousDelegate
  }

  static func presentationOptions(forIdentifier identifier: String) -> UNNotificationPresentationOptions? {
    identifier.hasPrefix(NativeTimerNotifications.timerIdentifierPrefix) ? [.banner, .sound, .list] : nil
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if let options = Self.presentationOptions(forIdentifier: notification.request.identifier) {
      completionHandler(options)
      return
    }
    guard let previousDelegate,
      previousDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)))
    else {
      completionHandler([])
      return
    }
    previousDelegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let previousDelegate,
      previousDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)))
    else {
      completionHandler()
      return
    }
    previousDelegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
