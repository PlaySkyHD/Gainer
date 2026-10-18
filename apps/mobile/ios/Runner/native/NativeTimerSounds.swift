import AVFoundation
import AudioToolbox
import Flutter
import Foundation
import UserNotifications

/// Timertöne: Wiedergabe in der App und Ton der Benachrichtigung „Pause vorbei“.
/// Die WAV-Dateien liegen als Flutter-Assets im App-Bundle und werden bei Bedarf
/// nach `Library/Sounds/` kopiert, wo `UNNotificationSound(named:)` sie findet.
@MainActor
final class NativeTimerSounds {
  nonisolated static let defaultSoundId = "digital_alarm"
  nonisolated static let systemSoundId = "system"
  nonisolated static let knownSoundIds: Set<String> = [
    "digital_alarm", "boxing_bell", "radar", "bike_bell", "gong", "chime", "pulse",
  ]

  /// Id des iOS-Standardtons für `AudioServicesPlaySystemSound`.
  private static let systemSoundServiceId: SystemSoundID = 1005

  private let fileManager: FileManager
  private var player: AVAudioPlayer?

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  /// Gültige Sound-Id; unbekannte Werte fallen auf den Standardton zurück.
  nonisolated static func resolvedSoundId(_ soundId: String) -> String {
    if soundId == systemSoundId || knownSoundIds.contains(soundId) { return soundId }
    return defaultSoundId
  }

  /// Dateiname der WAV-Datei zur Sound-Id; nil für den iOS-Standardton.
  /// Unbekannte Ids ergeben die Datei des Standardtons.
  nonisolated static func fileName(forSoundId soundId: String) -> String? {
    let resolved = resolvedSoundId(soundId)
    return resolved == systemSoundId ? nil : "\(resolved).wav"
  }

  /// Ton der Benachrichtigung. Fehlt die Datei, bleibt es beim Systemton.
  func notificationSound(forSoundId soundId: String) -> UNNotificationSound {
    guard let fileName = Self.fileName(forSoundId: soundId),
      installForNotifications(fileName: fileName)
    else {
      return .default
    }
    return UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
  }

  func play(soundId: String) throws {
    guard let fileName = Self.fileName(forSoundId: soundId) else {
      AudioServicesPlaySystemSound(Self.systemSoundServiceId)
      return
    }
    guard let path = bundledPath(fileName: fileName) else {
      throw PigeonError(code: "timer_sound_unavailable", message: "The timer sound file is missing.", details: nil)
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
      let next = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player?.stop()
      // Die Referenz bleibt bis zum nächsten Ton, sonst endet die Wiedergabe sofort.
      player = next
      next.prepareToPlay()
      next.play()
    } catch {
      throw PigeonError(code: "timer_sound_failed", message: "The timer sound could not be played.", details: "\(error)")
    }
  }

  private func bundledPath(fileName: String) -> String? {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/\(fileName)")
    return Bundle.main.path(forResource: key, ofType: nil)
  }

  /// Kopiert die Datei einmalig nach `Library/Sounds/`. False, wenn das nicht gelingt.
  private func installForNotifications(fileName: String) -> Bool {
    guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return false }
    let directory = library.appendingPathComponent("Sounds", isDirectory: true)
    let target = directory.appendingPathComponent(fileName)
    if fileManager.fileExists(atPath: target.path) { return true }
    guard let source = bundledPath(fileName: fileName) else { return false }
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try fileManager.copyItem(atPath: source, toPath: target.path)
      return true
    } catch {
      return false
    }
  }
}
