import UIKit
import AuthenticationServices
import CryptoKit
import Security

enum Haptics {
  static func coffee() { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.65) }
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

enum GoogleSignInError: LocalizedError {
  case notConfigured, invalidCallback, invalidResponse, stateMismatch
  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "Google Login necesita configurar GoogleClientID y GoogleReversedClientID."
    case .invalidCallback, .invalidResponse:
      "Google no ha devuelto una credencial válida."
    case .stateMismatch:
      "No se ha podido verificar la respuesta de Google."
    }
  }
}

@MainActor
final class GoogleSignInCoordinator: NSObject, ObservableObject,
  ASWebAuthenticationPresentationContextProviding
{
  private var session: ASWebAuthenticationSession?

  func signIn() async throws -> String {
    guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
      !clientID.isEmpty,
      let callbackScheme = Bundle.main.object(forInfoDictionaryKey: "GoogleReversedClientID") as? String,
      !callbackScheme.isEmpty
    else { throw GoogleSignInError.notConfigured }

    let verifier = Self.randomURLSafe(bytes: 48)
    let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    let state = Self.randomURLSafe(bytes: 24)
    // Google installed-app clients expect the standard native callback path.
    let redirectURI = "\(callbackScheme):/oauthredirect"
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
      .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
      .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
      .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
      .init(name: "state", value: state), .init(name: "prompt", value: "select_account")
    ]
    let callbackURL = try await authenticate(url: components.url!, scheme: callbackScheme)
    guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      callback.queryItems?.first(where: { $0.name == "state" })?.value == state
    else { throw GoogleSignInError.stateMismatch }
    guard let code = callback.queryItems?.first(where: { $0.name == "code" })?.value else {
      throw GoogleSignInError.invalidCallback
    }
    return try await exchange(code: code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
  }

  private func authenticate(url: URL, scheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] url, error in
        self?.session = nil
        if let error { continuation.resume(throwing: error) }
        else if let url { continuation.resume(returning: url) }
        else { continuation.resume(throwing: GoogleSignInError.invalidCallback) }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      session.start()
    }
  }

  private func exchange(code: String, verifier: String, clientID: String, redirectURI: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.form([
      "code": code, "client_id": clientID, "redirect_uri": redirectURI,
      "grant_type": "authorization_code", "code_verifier": verifier
    ]).data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data).idToken
    else { throw GoogleSignInError.invalidResponse }
    return token
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow
      ?? ASPresentationAnchor()
  }
  private static func randomURLSafe(bytes: Int) -> String {
    var data = Data(count: bytes)
    _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
    return base64URL(data)
  }
  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
  private static func form(_ values: [String: String]) -> String {
    values.sorted(by: { $0.key < $1.key }).map { key, value in
      "\(key.formEncoded)=\(value.formEncoded)"
    }.joined(separator: "&")
  }
}

private struct GoogleTokenResponse: Decodable {
  let idToken: String?
  enum CodingKeys: String, CodingKey { case idToken = "id_token" }
}

private extension String {
  var formEncoded: String {
    addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "-._~"))) ?? self
  }
}
