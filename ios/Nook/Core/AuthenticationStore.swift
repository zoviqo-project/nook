import Foundation
import Security

struct AuthenticationTokens: Codable, Sendable {
  let accessToken, refreshToken: String
  let expiresAt: Date
}
protocol TokenStore: Sendable {
  func load() throws -> AuthenticationTokens?
  func save(_ tokens: AuthenticationTokens) throws
  func clear() throws
}
enum AuthenticationError: Error {
  case invalidCredentials, missingToken
  case keychain(OSStatus)
}

struct KeychainTokenStore: TokenStore {
  private let service = "com.nook.app.authentication", account = "session"
  func load() throws -> AuthenticationTokens? {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw AuthenticationError.keychain(status)
    }
    return try JSONDecoder().decode(AuthenticationTokens.self, from: data)
  }
  func save(_ tokens: AuthenticationTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    SecItemDelete(base as CFDictionary)
    var query = base
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw AuthenticationError.keychain(status) }
  }
  func clear() throws {
    let status = SecItemDelete(base as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AuthenticationError.keychain(status)
    }
  }
  private var base: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
