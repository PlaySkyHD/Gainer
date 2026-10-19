import AVFoundation
import Foundation

/// Sprechtexte der Ansagen, rein und ohne AVFoundation (Design D4).
enum CardioVoiceText {
  static func text(for event: CardioZoneEvent) -> String {
    switch event {
    case .tooHigh(let bpm):
      return "Puls \(bpm), über dem Ziel. Etwas langsamer."
    case .tooLow(let bpm):
      return "Puls \(bpm), unter dem Ziel. Etwas schneller."
    case .backInZone:
      return "Wieder im Zielbereich."
    case .signalLost:
      return "Kein Pulssignal."
    case .phaseStarted(let index, let count, let name, let durationSeconds, let low, let high):
      var text = "Phase \(index + 1) von \(count), \(name), \(durationText(seconds: durationSeconds))"
      if let low, let high { text += ", Ziel \(low) bis \(high)" }
      return text + "."
    case .templateFinished:
      return "Vorlage beendet."
    }
  }

  /// „12 Minuten, Puls 134.“; ohne aktuellen Puls nur „12 Minuten.“
  static func intervalText(minutes: Int, bpm: Int?) -> String {
    let duration = minutes == 1 ? "1 Minute" : "\(minutes) Minuten"
    if let bpm { return "\(duration), Puls \(bpm)." }
    return duration + "."
  }

  /// Unter einer Minute in Sekunden („45 Sekunden“), sonst in Minuten („4 Minuten“,
  /// „1 Minute 30“).
  static func durationText(seconds: Int) -> String {
    let total = max(seconds, 0)
    if total < 60 { return total == 1 ? "1 Sekunde" : "\(total) Sekunden" }
    let minutes = total / 60
    let rest = total % 60
    let minuteText = minutes == 1 ? "1 Minute" : "\(minutes) Minuten"
    return rest == 0 ? minuteText : "\(minuteText) \(rest)"
  }
}

/// Wann die nächste Intervallansage fällig ist. Rein; die Zeit kommt von außen.
struct CardioVoiceSchedule: Equatable {
  private var intervalSeconds: TimeInterval?
  private var nextAtSeconds: TimeInterval = 0
  private var startedAt: Date

  /// Ohne Intervall (nil oder 0) gibt es keine Ansagen. Vergangene Zeitpunkte werden
  /// nicht nachgeholt, die nächste Ansage ist das nächste volle Vielfache.
  init(intervalMinutes: Int?, startedAt: Date, now: Date) {
    self.startedAt = startedAt
    guard let minutes = intervalMinutes, minutes > 0 else {
      intervalSeconds = nil
      return
    }
    let step = TimeInterval(minutes * 60)
    let elapsed = max(now.timeIntervalSince(startedAt), 0)
    intervalSeconds = step
    nextAtSeconds = (elapsed / step).rounded(.down) * step + step
  }

  /// Gibt die verstrichenen Minuten zurück, wenn eine Ansage fällig ist.
  mutating func due(now: Date) -> Int? {
    guard let step = intervalSeconds else { return nil }
    let elapsed = now.timeIntervalSince(startedAt)
    guard elapsed >= nextAtSeconds else { return nil }
    let multiple = (elapsed / step).rounded(.down)
    nextAtSeconds = (multiple + 1) * step
    return Int(multiple * step / 60)
  }
}

/// Meldet das Ende einer Ansage an den Main Actor. Die Rückrufe von AVFoundation
/// können auf jedem Thread kommen.
private final class CardioSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
  weak var owner: NativeCardioVoice?

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    notifyEnded()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    notifyEnded()
  }

  private func notifyEnded() {
    let owner = self.owner
    Task { @MainActor in
      owner?.utteranceEnded()
    }
  }
}

/// Sprachansagen mit `AVSpeechSynthesizer` und deutscher Stimme. Andere Wiedergabe wird
/// währenddessen leiser gestellt. Wirft nie: Ist Sprache nicht verfügbar, bleibt der
/// Aufruf wirkungslos.
@MainActor
final class NativeCardioVoice {
  private let delegate = CardioSpeechDelegate()
  private var synthesizer: AVSpeechSynthesizer?
  private var pending = 0

  init() {
    delegate.owner = self
  }

  func speak(_ text: String) {
    guard !text.isEmpty else { return }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
      try session.setActive(true)
    } catch {
      // Ohne Audiosession keine Ansage; die Benachrichtigung bleibt.
      return
    }
    let synthesizer = self.synthesizer ?? makeSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    if let voice = AVSpeechSynthesisVoice(language: "de-DE") {
      utterance.voice = voice
    }
    pending += 1
    synthesizer.speak(utterance)
  }

  /// Bricht laufende Ansagen ab und gibt die Audiosession frei.
  func stop() {
    // Ohne Synthesizer wurde nie gesprochen und die Session nie aktiviert.
    guard let synthesizer else { return }
    pending = 0
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    deactivateSession()
  }

  fileprivate func utteranceEnded() {
    guard pending > 0 else { return }
    pending -= 1
    if pending == 0 { deactivateSession() }
  }

  private func makeSynthesizer() -> AVSpeechSynthesizer {
    let created = AVSpeechSynthesizer()
    created.delegate = delegate
    synthesizer = created
    return created
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
