import AuthenticationServices
import Foundation
import UIKit

/// Öffnet eine Anmeldeseite im System-Sheet (`ASWebAuthenticationSession`) und liefert die
/// Rückleitung auf das eigene URL-Schema, z. B. für die Strava-Verbindung.
@MainActor
final class NativeWebAuthentication {
  private var pending: WebAuthenticationRequest?

  /// Nil, wenn der Nutzer das Sheet schließt.
  func authenticate(url: URL, callbackScheme: String) async throws -> URL? {
    guard pending == nil else {
      throw PigeonError(code: "web_authentication_busy", message: "A sign-in sheet is already open.", details: nil)
    }
    return try await withCheckedThrowingContinuation { continuation in
      let request = WebAuthenticationRequest()
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackUrl, error in
        // Der Rückruf kommt nicht garantiert auf dem Main Thread.
        Task { @MainActor in
          self?.pending = nil
          if let callbackUrl {
            continuation.resume(returning: callbackUrl)
            return
          }
          if let authenticationError = error as? ASWebAuthenticationSessionError,
             authenticationError.code == .canceledLogin {
            continuation.resume(returning: nil)
            return
          }
          continuation.resume(throwing: PigeonError(
            code: "web_authentication_failed",
            message: error?.localizedDescription ?? "The sign-in sheet failed.",
            details: nil
          ))
        }
      }
      session.presentationContextProvider = request
      session.prefersEphemeralWebBrowserSession = false
      request.session = session
      pending = request
      if !session.start() {
        pending = nil
        continuation.resume(throwing: PigeonError(
          code: "web_authentication_failed",
          message: "The sign-in sheet could not be opened.",
          details: nil
        ))
      }
    }
  }
}

/// Hält die Session bis zum Abschluss und liefert das Fenster für das Sheet.
private final class WebAuthenticationRequest: NSObject, ASWebAuthenticationPresentationContextProviding {
  var session: ASWebAuthenticationSession?

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
  }
}
