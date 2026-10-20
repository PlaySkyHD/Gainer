import AuthenticationServices
import Foundation
import UIKit

/// Erstellt und nutzt Passkeys über das System-Sheet mit Face ID. Die Domain muss in den
/// Associated Domains (`webcredentials:`) der App stehen und die App per
/// apple-app-site-association bestätigen.
@MainActor
final class NativePasskeys {
  private var pending: PasskeyRequest?

  /// Nil, wenn der Nutzer abbricht.
  func create(
    relyingPartyId: String,
    challenge: Data,
    userId: Data,
    userName: String
  ) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration? {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyId)
    let request = provider.createCredentialRegistrationRequest(
      challenge: challenge,
      name: userName,
      userID: userId
    )
    request.userVerificationPreference = .required
    return try await perform(request) as? ASAuthorizationPlatformPublicKeyCredentialRegistration
  }

  /// Nil, wenn der Nutzer abbricht oder kein Passkey der Domain vorhanden ist.
  func assert(
    relyingPartyId: String,
    challenge: Data
  ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion? {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyId)
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    request.userVerificationPreference = .required
    return try await perform(request) as? ASAuthorizationPlatformPublicKeyCredentialAssertion
  }

  private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential? {
    guard pending == nil else {
      throw PigeonError(code: "passkey_busy", message: "A passkey request is already running.", details: nil)
    }
    return try await withCheckedThrowingContinuation { continuation in
      let controller = ASAuthorizationController(authorizationRequests: [request])
      let passkeyRequest = PasskeyRequest(controller: controller) { [weak self] result in
        self?.pending = nil
        continuation.resume(with: result)
      }
      pending = passkeyRequest
      controller.delegate = passkeyRequest
      controller.presentationContextProvider = passkeyRequest
      controller.performRequests()
    }
  }
}

/// Hält Controller und Rückruf, bis das System-Sheet fertig ist. Die Rückrufe von
/// `ASAuthorizationController` kommen auf dem Main Thread.
private final class PasskeyRequest: NSObject,
  ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private let controller: ASAuthorizationController
  private var completion: ((Result<ASAuthorizationCredential?, Error>) -> Void)?

  init(
    controller: ASAuthorizationController,
    completion: @escaping (Result<ASAuthorizationCredential?, Error>) -> Void
  ) {
    self.controller = controller
    self.completion = completion
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    finish(.success(authorization.credential))
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    if let authorizationError = error as? ASAuthorizationError,
       authorizationError.code == .canceled {
      finish(.success(nil))
      return
    }
    finish(.failure(PigeonError(
      code: "passkey_failed",
      message: error.localizedDescription,
      details: nil
    )))
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
  }

  private func finish(_ result: Result<ASAuthorizationCredential?, Error>) {
    let completion = self.completion
    self.completion = nil
    completion?(result)
  }
}
