import UIKit

@MainActor
final class NativeHaptics {
  func perform(intent: String) {
    switch intent {
    case "commit":
      let generator = UIImpactFeedbackGenerator(style: .rigid)
      generator.prepare()
      generator.impactOccurred()
    case "timerComplete", "success":
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(.success)
    default:
      // An unknown intent must never interrupt the underlying user action.
      return
    }
  }
}
