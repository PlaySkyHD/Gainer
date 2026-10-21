import AVFoundation
import Foundation
import Speech

/// Diktat für die Mahlzeiten-Schätzung. Die Erkennung läuft nur auf dem Gerät,
/// kein Audio verlässt das iPhone. Flutter fragt den Stand per [state] ab.
@MainActor
final class NativeDictation {
  nonisolated static let statusIdle = "idle"
  nonisolated static let statusListening = "listening"
  nonisolated static let statusFinished = "finished"
  nonisolated static let statusDenied = "denied"
  nonisolated static let statusUnavailable = "unavailable"
  nonisolated static let statusFailed = "failed"

  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var status = NativeDictation.statusIdle
  private var transcript = ""
  private var generation = 0

  var state: PlatformDictationState {
    PlatformDictationState(status: status, transcript: transcript)
  }

  func start(localeId: String) async -> PlatformDictationState {
    teardown()
    generation += 1
    let current = generation
    transcript = ""
    status = Self.statusIdle
    guard await Self.requestSpeechAuthorization(), await AVAudioApplication.requestRecordPermission() else {
      status = Self.statusDenied
      return state
    }
    // Ein zweiter Start oder Abbruch während der Rechteabfrage gewinnt.
    guard current == generation else { return state }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
      recognizer.isAvailable,
      recognizer.supportsOnDeviceRecognition
    else {
      status = Self.statusUnavailable
      return state
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    request.addsPunctuation = true
    let engine = AVAudioEngine()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      // Ohne Mikrofon ist das Format leer; installTap würde dann abstürzen.
      guard Self.installTap(on: engine.inputNode, request: request) else {
        deactivateSession()
        status = Self.statusUnavailable
        return state
      }
      engine.prepare()
      try engine.start()
    } catch {
      engine.inputNode.removeTap(onBus: 0)
      deactivateSession()
      status = Self.statusFailed
      return state
    }
    audioEngine = engine
    self.request = request
    status = Self.statusListening
    task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
      self?.handle(generation: current, text: text, isFinal: isFinal, failed: failed)
    })
    return state
  }

  /// Beendet die Aufnahme; das letzte Ergebnis kommt danach noch über [state].
  func stop() {
    guard status == Self.statusListening else { return }
    stopAudio()
    request?.endAudio()
  }

  func cancel() {
    generation += 1
    teardown()
    status = Self.statusIdle
  }

  private func handle(generation: Int, text: String?, isFinal: Bool, failed: Bool) {
    guard generation == self.generation else { return }
    if let text { transcript = text }
    guard isFinal || failed else { return }
    teardown()
    // Ein Fehler nach erkanntem Text (z. B. Stille am Ende) ist ein normales Ende.
    status = failed && transcript.isEmpty ? Self.statusFailed : Self.statusFinished
  }

  private func teardown() {
    stopAudio()
    task?.cancel()
    task = nil
    request = nil
  }

  private func stopAudio() {
    guard let engine = audioEngine else { return }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    audioEngine = nil
    deactivateSession()
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // Der Tap läuft auf dem Audio-Thread und darf nicht an den Main Actor gebunden sein.
  private nonisolated static func installTap(
    on input: AVAudioInputNode,
    request: SFSpeechAudioBufferRecognitionRequest
  ) -> Bool {
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0, format.sampleRate > 0 else { return false }
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    return true
  }

  private nonisolated static func resultHandler(
    _ deliver: @escaping @MainActor (String?, Bool, Bool) -> Void
  ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
    { result, error in
      let text = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal ?? false
      let failed = error != nil
      Task { @MainActor in deliver(text, isFinal, failed) }
    }
  }

  private nonisolated static func requestSpeechAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }
}
