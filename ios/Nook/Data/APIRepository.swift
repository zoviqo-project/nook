import Foundation

actor APIRepository: NookRepository {
  private let baseURL: URL
  private let session: URLSession
  private let tokens: TokenStore
  private let decoder: JSONDecoder
  init(baseURL: URL, session: URLSession? = nil, tokens: TokenStore = KeychainTokenStore()) {
    self.baseURL = baseURL
    if let session { self.session = session }
    else {
      let configuration = URLSessionConfiguration.default
      configuration.timeoutIntervalForRequest = 10
      configuration.timeoutIntervalForResource = 15
      configuration.requestCachePolicy = .useProtocolCachePolicy
      configuration.urlCache = URLCache(memoryCapacity: 24_000_000, diskCapacity: 80_000_000)
      self.session = URLSession(configuration: configuration)
    }
    self.tokens = tokens
    decoder = JSONDecoder()
  }
  func register(
    email: String, password: String, name: String, birthDate: Date, gender: Gender,
    lookingFor: LookingFor
  ) async throws -> Me {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let body = RegisterBody(
      email: email, password: password, name: name, birthDate: f.string(from: birthDate),
      gender: gender, lookingFor: lookingFor)
    let t: TokenResponse = try await call("auth/register", method: "POST", body: body, auth: false)
    try tokens.save(
      .init(
        accessToken: t.accessToken, refreshToken: t.refreshToken,
        expiresAt: Date().addingTimeInterval(Double(t.expiresIn))))
    return t.user
  }
  func login(email: String, password: String) async throws -> Me {
    let t: TokenResponse = try await call(
      "auth/login", method: "POST", body: LoginBody(email: email, password: password), auth: false)
    try tokens.save(
      .init(
        accessToken: t.accessToken, refreshToken: t.refreshToken,
        expiresAt: Date().addingTimeInterval(Double(t.expiresIn))))
    return t.user
  }
  func federatedLogin(provider: String, identityToken: String, displayName: String?) async throws -> Me {
    let response: TokenResponse = try await call(
      "auth/\(provider.lowercased())", method: "POST",
      body: FederatedBody(identityToken: identityToken, displayName: displayName), auth: false)
    try save(response)
    return response.user
  }
  func requestPhoneOtp(_ phone: String) async throws -> PhoneOtpChallenge {
    try await call("auth/phone/request-code", method: "POST", body: PhoneRequestBody(phone: phone), auth: false)
  }
  func verifyPhoneOtp(challengeId: UUID, code: String) async throws -> Me {
    let response: TokenResponse = try await call(
      "auth/phone/verify-code", method: "POST",
      body: PhoneVerifyBody(challengeId: challengeId, code: code), auth: false)
    try save(response)
    return response.user
  }
  func restore() async throws -> Me? {
    guard (try? tokens.load()) != nil else { return nil }
    do { return try await me() } catch {
      try? tokens.clear()
      return nil
    }
  }
  func logout() async {
    if let t = try? tokens.load() {
      let _: Empty? = try? await call(
        "auth/logout", method: "POST", body: RefreshBody(refreshToken: t.refreshToken))
    }
    try? tokens.clear()
  }
  func me() async throws -> Me { try await call("users/me") }
  func updateProfile(_ p: ProfileUpdate) async throws -> Me {
    try await call("users/me", method: "PATCH", body: p)
  }
  func settings() async throws -> UserSettings { try await call("users/me/settings") }
  func updateSettings(_ payload: UserSettingsUpdate) async throws -> UserSettings {
    try await call("users/me/settings", method: "PUT", body: payload)
  }
  func updateLocation(latitude: Double, longitude: Double, accuracy: Double, capturedAt: Date) async throws {
    let _: Empty = try await call("users/me/location", method: "PUT", body: UserLocationBody(
      latitude: latitude, longitude: longitude, accuracyMeters: accuracy,
      capturedAt: ISO8601DateFormatter().string(from: capturedAt)))
  }
  func uploadPhoto(data: Data, mimeType: String) async throws -> Photo {
    try await performPhotoUpload(data: data, mimeType: mimeType, mayRefresh: true)
  }
  private func performPhotoUpload(data: Data, mimeType: String, mayRefresh: Bool) async throws -> Photo {
    if mayRefresh, let current = try tokens.load(), current.expiresAt.timeIntervalSinceNow < 30 {
      try await refreshSession(using: current.refreshToken)
    }
    let boundary = "Nook-\(UUID().uuidString)"
    guard let uploadURL = URL(string: "users/me/photos", relativeTo: baseURL) else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let token = try tokens.load() { request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization") }
    var body = Data()
    guard let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"profile.jpg\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8),
      let suffix = "\r\n--\(boundary)--\r\n".data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
    body.append(prefix)
    body.append(data)
    body.append(suffix)
    request.httpBody = body
    let (responseData, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401, mayRefresh, let current = try tokens.load() {
      try await refreshSession(using: current.refreshToken)
      return try await performPhotoUpload(data: data, mimeType: mimeType, mayRefresh: false)
    }
    guard (200..<300).contains(http.statusCode) else {
      if let apiError = try? decoder.decode(APIErrorBody.self, from: responseData) {
        throw NSError(domain: "Nook", code: http.statusCode,
          userInfo: [NSLocalizedDescriptionKey: apiError.message])
      }
      throw URLError(.badServerResponse)
    }
    return try decoder.decode(Photo.self, from: responseData)
  }
  func deletePhoto(_ id: UUID) async throws {
    let _: Empty = try await call("users/me/photos/\(id)", method: "DELETE")
  }
  func reorderPhotos(_ ids: [UUID]) async throws -> [Photo] {
    try await call("users/me/photos/reorder", method: "PATCH", body: PhotoOrderBody(photoIds: ids))
  }
  func makePrimaryPhoto(_ id: UUID) async throws -> Photo {
    try await call("users/me/photos/\(id)/primary", method: "PATCH", body: Optional<String>.none)
  }
  func discover() async throws -> [DiscoverProfile] {
    let p: PageResponse<DiscoverProfile> = try await call("discover")
    return p.content
  }
  func like(_ id: UUID) async throws -> LikeResult {
    try await call("coffee-likes/\(id)", method: "POST", body: Optional<String>.none)
  }
  func pass(_ id: UUID) async throws {
    let _: Empty = try await call("coffee-likes/\(id)", method: "DELETE")
  }
  func matches() async throws -> [Match] { try await call("matches") }
  func meetingPoint(matchID: UUID) async throws -> GeoPoint {
    try await call("matches/\(matchID)/meeting-point")
  }
  func shops(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [CoffeeShop] {
    var result: [CoffeeShop] = try await call(
      "cafes/nearby?latitude=\(latitude)&longitude=\(longitude)&radius=\(GeographicMath.meters(fromKilometers: radiusKm))")
    for index in result.indices {
      if let value = result[index].photoUrl, value.hasPrefix("/") {
        result[index].photoUrl = URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString
      }
      result[index].photoUrls = result[index].photoUrls?.map { value in
        value.hasPrefix("/") ? (URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString ?? value) : value
      }
    }
    return result
  }
  func conversations() async throws -> [Conversation] { try await call("conversations") }
  func messages(_ id: UUID) async throws -> [ChatMessage] {
    let p: PageResponse<ChatMessage> = try await call("conversations/\(id)/messages")
    return p.content.reversed()
  }
  func send(_ text: String, to id: UUID) async throws -> ChatMessage {
    try await call("conversations/\(id)/messages", method: "POST", body: MessageBody(body: text, clientMessageId: UUID()))
  }
  func dates() async throws -> [CoffeeDate] { try await call("coffee-dates") }
  func propose(match: UUID, shop: UUID, date: Date, payment: PaymentPreference, nookChoice: Bool, idempotencyKey: UUID) async throws
    -> CoffeeDate
  {
    try await call(
      "coffee-dates", method: "POST",
      body: DateBody(
        matchId: match, coffeeShopId: shop, proposedAt: ISO8601DateFormatter().string(from: date),
        paymentPreference: payment, nookChoice: nookChoice, idempotencyKey: idempotencyKey))
  }
  func updateDate(_ id: UUID, status: CoffeeDateStatus) async throws -> CoffeeDate {
    try await call("coffee-dates/\(id)", method: "PATCH", body: StatusBody(status: status))
  }
  func notifications() async throws -> [NookNotification] {
    let page: PageResponse<NookNotification> = try await call("notifications")
    return page.content
  }
  func markNotificationRead(_ id: UUID) async throws {
    let _: Empty = try await call("notifications/\(id)/read", method: "POST")
  }
  func registerDeviceToken(_ token: String) async throws {
    let _: Empty = try await call("notifications/devices", method: "POST", body: DeviceTokenBody(token: token))
  }
  func removeDeviceToken(_ token: String) async throws {
    let _: Empty = try await call("notifications/devices", method: "DELETE", body: DeviceTokenBody(token: token))
  }
  func block(_ userID: UUID) async throws {
    let _: Empty = try await call("users/\(userID)/block", method: "POST")
  }
  func report(_ userID: UUID, reason: String, details: String?) async throws {
    let _: Empty = try await call("users/\(userID)/report", method: "POST", body: ReportBody(reason: reason, details: details))
  }
  private func call<R: Decodable>(_ path: String, method: String = "GET", auth: Bool = true)
    async throws -> R
  { try await call(path, method: method, body: Optional<String>.none, auth: auth) }
  private func call<R: Decodable, B: Encodable>(
    _ path: String, method: String = "GET", body: B?, auth: Bool = true
  ) async throws -> R {
    try await perform(path, method: method, body: body, auth: auth, mayRefresh: true)
  }
  private func perform<R: Decodable, B: Encodable>(
    _ path: String, method: String, body: B?, auth: Bool, mayRefresh: Bool
  ) async throws -> R {
    if auth, mayRefresh, let current = try tokens.load(),
      current.expiresAt.timeIntervalSinceNow < 30
    {
      try await refreshSession(using: current.refreshToken)
    }
    guard let endpoint = URL(string: path, relativeTo: baseURL) else { throw URLError(.badURL) }
    var req = URLRequest(url: endpoint)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body { req.httpBody = try JSONEncoder().encode(body) }
    if auth, let t = try tokens.load() {
      req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    if http.statusCode == 401, auth, mayRefresh, let current = try tokens.load() {
      try await refreshSession(using: current.refreshToken)
      return try await perform(path, method: method, body: body, auth: auth, mayRefresh: false)
    }
    guard (200..<300).contains(http.statusCode) else {
      if let e = try? decoder.decode(APIErrorBody.self, from: data) {
        throw NSError(
          domain: "Nook", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
          userInfo: [NSLocalizedDescriptionKey: e.message])
      }
      throw URLError(.badServerResponse)
    }
    if R.self == Empty.self { return Empty() as! R }
    return try decoder.decode(R.self, from: data)
  }
  private func refreshSession(using refreshToken: String) async throws {
    do {
      let response: TokenResponse = try await perform(
        "auth/refresh", method: "POST", body: RefreshBody(refreshToken: refreshToken),
        auth: false, mayRefresh: false)
      try tokens.save(
        .init(
          accessToken: response.accessToken, refreshToken: response.refreshToken,
          expiresAt: Date().addingTimeInterval(Double(response.expiresIn))))
    } catch {
      try? tokens.clear()
      throw AuthenticationError.invalidCredentials
    }
  }
  private func save(_ response: TokenResponse) throws {
    try tokens.save(
      .init(accessToken: response.accessToken, refreshToken: response.refreshToken,
        expiresAt: Date().addingTimeInterval(Double(response.expiresIn))))
  }
}
private struct TokenResponse: Codable {
  let accessToken, refreshToken: String
  let expiresIn: Int
  let user: Me
}
private struct RegisterBody: Codable {
  let email, password, name, birthDate: String
  let gender: Gender
  let lookingFor: LookingFor
}
private struct LoginBody: Codable { let email, password: String }
private struct FederatedBody: Codable { let identityToken: String; let displayName: String? }
private struct PhoneRequestBody: Codable { let phone: String }
private struct PhoneVerifyBody: Codable { let challengeId: UUID; let code: String }
private struct RefreshBody: Codable { let refreshToken: String }
private struct MessageBody: Codable { let body: String; let clientMessageId: UUID }
private struct DateBody: Codable {
  let matchId, coffeeShopId: UUID
  let proposedAt: String
  let paymentPreference: PaymentPreference
  let nookChoice: Bool
  let idempotencyKey: UUID
}
private struct StatusBody: Codable { let status: CoffeeDateStatus }
private struct DeviceTokenBody: Codable { let token: String }
private struct ReportBody: Codable { let reason: String; let details: String? }
private struct PhotoOrderBody: Codable { let photoIds: [UUID] }
private struct UserLocationBody: Codable { let latitude, longitude, accuracyMeters: Double; let capturedAt: String }
private struct Empty: Codable {}
