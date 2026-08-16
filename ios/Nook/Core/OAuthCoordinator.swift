import UIKit
import AuthenticationServices

enum Haptics {
  static func coffee() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1) }
  static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
  static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

@MainActor
final class AppleSignInCoordinator: NSObject, ObservableObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private var continuation: CheckedContinuation<(identityToken: String, displayName: String?), Error>?

  func signIn() async throws -> (identityToken: String, displayName: String?) {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.requestedScopes = [.fullName, .email]
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let tokenData = credential.identityToken,
      let token = String(data: tokenData, encoding: .utf8)
    else {
      continuation?.resume(throwing: AuthenticationError.invalidCredentials)
      continuation = nil
      return
    }
    let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? .init())
    continuation?.resume(returning: (token, name.isEmpty ? nil : name))
    continuation = nil
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow ?? ASPresentationAnchor()
  }
}
