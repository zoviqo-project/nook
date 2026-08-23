import Foundation
import CoreLocation

enum Gender: String, Codable, CaseIterable, Identifiable {
  case woman = "WOMAN"
  case man = "MAN"
  case nonBinary = "NON_BINARY"
  case other = "OTHER"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .woman: "Mujer"
    case .man: "Hombre"
    case .nonBinary: "No binario"
    case .other: "Otro"
    }
  }
}
enum LookingFor: String, Codable, CaseIterable, Identifiable {
  case casualCoffee = "CASUAL_COFFEE"
  case somethingMore = "SOMETHING_MORE"
  case project = "PROJECT"
  case friendship = "FRIENDSHIP"
  case support = "SUPPORT"
  case openEnded = "OPEN_ENDED"
  // Legacy API values remain decodable while existing accounts are migrated.
  case meetPeople = "MEET_PEOPLE"
  case seeWhatHappens = "SEE_WHAT_HAPPENS"
  var id: String { rawValue }
  static let registrationChoices: [LookingFor] = [.casualCoffee, .somethingMore, .project, .friendship, .support, .openEnded]
  var title: String {
    switch self {
    case .casualCoffee: "Tomar un café y pasar el rato"
    case .somethingMore: "Quedar para algo más"
    case .project: "Comentar un proyecto"
    case .friendship: "Hacer nuevos amigos"
    case .support: "Hablar con alguien"
    case .openEnded: "Quedar para…"
    case .meetPeople: "Tomar un café y pasar el rato"
    case .seeWhatHappens: "Quedar para…"
    }
  }
  var profileTitle: String {
    switch self {
    case .casualCoffee: "Un café sin prisas"
    case .somethingMore: "Algo más, si surge"
    case .project: "Compartir un proyecto"
    case .friendship: "Conocer nuevos amigos"
    case .support: "Una conversación que acompañe"
    case .openEnded: "Dejar que el café decida"
    case .meetPeople: "Un café sin prisas"
    case .seeWhatHappens: "Dejar que el café decida"
    }
  }
  var detail: String {
    switch self {
    case .casualCoffee: "Pasarlo bien, conversar y disfrutar del momento."
    case .somethingMore: "Conocer a alguien con intención de descubrir si hay conexión."
    case .project: "Intercambiar ideas, crear y dar forma a algo interesante."
    case .friendship: "Ampliar su círculo y encontrar gente con quien compartir planes."
    case .support: "Ahora mismo le vendría bien conversar y sentirse acompañado/a."
    case .openEnded: "Sin etiquetas ni expectativas cerradas. Empezar por un café."
    case .meetPeople: "Pasarlo bien, conversar y disfrutar del momento."
    case .seeWhatHappens: "Sin etiquetas ni expectativas cerradas. Empezar por un café."
    }
  }
  var icon: String {
    switch self {
    case .casualCoffee: "cup.and.saucer.fill"
    case .somethingMore: "sparkles"
    case .project: "lightbulb.fill"
    case .friendship: "person.2.fill"
    case .support: "heart.text.square.fill"
    case .openEnded: "ellipsis"
    case .meetPeople: "cup.and.saucer.fill"
    case .seeWhatHappens: "ellipsis"
    }
  }
}
enum PaymentPreference: String, Codable, CaseIterable, Identifiable {
  case iInvite = "I_INVITE"
  case theyInvite = "THEY_INVITE"
  case split = "SPLIT"
  case decideThere = "DECIDE_THERE"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .iInvite: "🎁 Invito yo"
    case .theyInvite: "🙋 Me invita"
    case .split: "⚖️ Cada uno el suyo"
    case .decideThere: "🎲 Lo decidimos allí"
    }
  }
}
enum CoffeeDateStatus: String, Codable {
  case pending = "PENDING"
  case accepted = "ACCEPTED"
  case declined = "DECLINED"
  case counterProposed = "COUNTER_PROPOSED"
  case cancelled = "CANCELLED"
  case completed = "COMPLETED"
  case expired = "EXPIRED"
}
struct Photo: Codable, Identifiable, Hashable {
  let id: UUID
  let url: String
  let position: Int
  var isPrimary: Bool? = nil
}
struct Me: Codable {
  let id: UUID
  let email, name: String
  let age: Int?
  let birthDate: String?
  let gender: Gender?
  let bio: String
  let city: String?
  let lookingFor: LookingFor?
  let coffeePersonality: String?
  let preferredPlan: String?
  let preferredVibe: String?
  let coffeesPerDay: Int?
  let favoriteCoffeeMoment: String?
  let minAge, maxAge, maxDistanceKm: Int
  let visible, hidden, onboardingComplete: Bool
  let coffeePreferences: [String]
  let photos: [Photo]
  var desiredGenders: [String]? = nil
  var discoveryIntentions: [String]? = nil
  var discoveryVibes: [String]? = nil
  var discoveryMoments: [String]? = nil
  var discoveryMeetingStyles: [String]? = nil
}
struct DiscoverProfile: Codable, Identifiable, Hashable {
  let id: UUID
  let name: String
  let age: Int
  let bio: String
  let city: String?
  let distanceKm: Double
  let coffeePersonality: String?
  let preferredPlan: String?
  let preferredVibe: String?
  let coffeesPerDay: Int?
  let favoriteCoffeeMoment: String?
  let lookingFor: LookingFor
  let coffeePreferences: [String]
  let photos: [Photo]
}
struct Match: Codable, Identifiable {
  let id: UUID
  let person: DiscoverProfile
  let matchedAt: String
  let conversationId: UUID
}
struct LikeResult: Codable {
  let matched: Bool
  let match: Match?
}
struct CoffeeShop: Codable, Identifiable, Hashable {
  let id: UUID
  let name, address: String
  let neighborhood: String?
  let distanceKm: Double
  var photoUrl: String?
  let openingHours: String?
  let rating: Double?
  let description: String?
  let vibes: [String]
  var latitude: Double? = nil
  var longitude: Double? = nil
  var placeId: String? = nil
  var reviewCount: Int? = nil
  var openNow: Bool? = nil
  var priceLevel: String? = nil
  var website: String? = nil
  var phone: String? = nil
  var mapsUrl: String? = nil
  var types: [String] = []
  var photoUrls: [String]? = nil
  var category: String? = nil
  var vibeLabel: String {
    switch vibes.first {
    case "CALM": "😌 Tranquilo"
    case "LIVELY": "🎵 Animado"
    case "SOCIAL": "🙂 Con ambiente"
    default: "Vibe todavía sin valorar"
    }
  }

  /// Nil means the provider did not return a schedule we can safely interpret.
  /// An empty array means the café is known to be closed on that date.
  func availableTimes(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> [Date]? {
    guard let openingHours, !openingHours.isEmpty else { return nil }
    return CoffeeOpeningSchedule.slots(from: openingHours, on: date, calendar: calendar)
  }
}

enum CoffeeOpeningSchedule {
  private static let days: [String: Int] = [
    "sunday": 1, "domingo": 1, "monday": 2, "lunes": 2, "tuesday": 3, "martes": 3,
    "wednesday": 4, "miércoles": 4, "miercoles": 4, "thursday": 5, "jueves": 5,
    "friday": 6, "viernes": 6, "saturday": 7, "sábado": 7, "sabado": 7
  ]

  static func slots(from descriptions: String, on date: Date, calendar: Calendar) -> [Date]? {
    let weekday = calendar.component(.weekday, from: date)
    guard let entry = descriptions.components(separatedBy: " · ").first(where: { raw in
      guard let separator = raw.firstIndex(of: ":") else { return false }
      return days[normalized(String(raw[..<separator]))] == weekday
    }), let separator = entry.firstIndex(of: ":") else { return nil }
    let hours = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
    let lower = normalized(hours)
    if lower.contains("closed") || lower.contains("cerrado") { return [] }
    if lower.contains("open 24 hours") || lower.contains("abierto 24 horas") {
      return stride(from: 0, through: 23 * 60 + 30, by: 30).compactMap { time($0, on: date, calendar: calendar) }
    }
    var result: [Date] = []
    var parsed = false
    for range in hours.components(separatedBy: ",") {
      let ends = range.components(separatedBy: CharacterSet(charactersIn: "–—-")).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard ends.count == 2, let start = minutes(ends[0]), let end = minutes(ends[1]) else { continue }
      parsed = true
      if end > start {
        result += stride(from: start, through: max(start, end - 30), by: 30)
          .compactMap { time($0, on: date, calendar: calendar) }
      }
    }
    return parsed ? result.filter { $0.timeIntervalSinceNow > 15 * 60 } : nil
  }

  private static func minutes(_ raw: String) -> Int? {
    let clean = raw.uppercased().replacingOccurrences(of: "A. M.", with: "AM")
      .replacingOccurrences(of: "P. M.", with: "PM")
      .replacingOccurrences(of: "\u{202F}", with: " ")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["H:mm", "h:mm a"] {
      formatter.dateFormat = format
      if let value = formatter.date(from: clean) {
        let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: value)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
      }
    }
    return nil
  }

  private static func time(_ minutes: Int, on date: Date, calendar: Calendar) -> Date? {
    calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

struct GeoPoint: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
  init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
  init(_ coordinate: CLLocationCoordinate2D) {
    self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }
}

enum CafeSearchOrigin: Equatable, Sendable {
  case currentLocation(GeoPoint)
  case midpoint(GeoPoint)
  case selectedLocation(GeoPoint, name: String)
  var point: GeoPoint {
    switch self {
    case .currentLocation(let point), .midpoint(let point), .selectedLocation(let point, _): point
    }
  }
  var logName: String {
    switch self {
    case .currentLocation: "CURRENT_LOCATION"
    case .midpoint: "MIDPOINT"
    case .selectedLocation: "SELECTED_LOCATION"
    }
  }
}

enum GeographicMath {
  static func midpoint(_ a: GeoPoint, _ b: GeoPoint) -> GeoPoint {
    let lat1 = a.latitude * .pi / 180
    let lon1 = a.longitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let deltaLon = (b.longitude - a.longitude) * .pi / 180
    let bx = cos(lat2) * cos(deltaLon)
    let by = cos(lat2) * sin(deltaLon)
    let lat3 = atan2(sin(lat1) + sin(lat2), sqrt((cos(lat1) + bx) * (cos(lat1) + bx) + by * by))
    let lon3 = lon1 + atan2(by, cos(lat1) + bx)
    return GeoPoint(latitude: lat3 * 180 / .pi, longitude: ((lon3 * 180 / .pi + 540).truncatingRemainder(dividingBy: 360)) - 180)
  }
  static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
      .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
  }
  static func meters(fromKilometers value: Double) -> Int { Int((value * 1_000).rounded()) }
}
struct Conversation: Codable, Identifiable {
  let id, matchId: UUID
  let person: DiscoverProfile
  let lastMessage: String
  let updatedAt: String
}
struct ChatMessage: Codable, Identifiable {
  let id: UUID
  let senderId: UUID?
  let body, type, createdAt: String
}
struct CoffeeDate: Codable, Identifiable {
  let id, matchId, senderId, receiverId: UUID
  var coffeeShop: CoffeeShop
  let proposedAt: String
  let paymentPreference: PaymentPreference
  let status: CoffeeDateStatus
  let createdAt: String
  let nookChoice: Bool?
  var timeZoneId: String? = nil

  func formattedProposedAt(dateStyle: DateFormatter.Style = .medium) -> String {
    guard let value = ISO8601DateFormatter.nook.date(from: proposedAt) else { return proposedAt }
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateStyle = dateStyle
    formatter.timeStyle = .short
    formatter.timeZone = timeZoneId.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    return formatter.string(from: value)
  }
}
struct MyCafeItem: Codable, Identifiable {
  var id: UUID { matchId }
  let matchId: UUID
  let person: DiscoverProfile
  let matchedAt: String
  let conversationId: UUID
  var proposal: CoffeeDate?
  var availableActions: [String]
}
struct PageResponse<T: Codable>: Codable {
  let content: [T]
  let page, size: Int
  let hasMore: Bool
}
struct APIErrorBody: Codable { let code, message: String }
struct NookNotification: Codable, Identifiable, Sendable {
  let id: UUID
  let type, title, body: String
  let resourceId: UUID?
  let createdAt: String
  let read: Bool
}
struct PhoneOtpChallenge: Codable, Sendable {
  let challengeId: UUID
  let expiresIn: Int
  let developmentCode: String?
}
struct UserSettings: Codable, Sendable {
  let coffeeSoundsEnabled: Bool
  let pushEnabled: Bool
  let locale: String
}
struct UserSettingsUpdate: Codable, Sendable {
  var coffeeSoundsEnabled: Bool?
  var pushEnabled: Bool?
  var locale: String?
}
protocol UserRepository: Sendable {
  func register(
    email: String, password: String, name: String, birthDate: Date, gender: Gender,
    lookingFor: LookingFor
  ) async throws -> Me
  func login(email: String, password: String) async throws -> Me
  func federatedLogin(provider: String, identityToken: String, displayName: String?) async throws -> Me
  func requestPhoneOtp(_ phone: String) async throws -> PhoneOtpChallenge
  func verifyPhoneOtp(challengeId: UUID, code: String) async throws -> Me
  func restore() async throws -> Me?
  func logout() async
  func me() async throws -> Me
  func updateProfile(_ payload: ProfileUpdate) async throws -> Me
  func uploadPhoto(data: Data, mimeType: String) async throws -> Photo
  func deletePhoto(_ id: UUID) async throws
  func reorderPhotos(_ ids: [UUID]) async throws -> [Photo]
  func makePrimaryPhoto(_ id: UUID) async throws -> Photo
  func settings() async throws -> UserSettings
  func updateSettings(_ payload: UserSettingsUpdate) async throws -> UserSettings
  func updateLocation(latitude: Double, longitude: Double, accuracy: Double, capturedAt: Date) async throws
}
protocol DiscoveryRepository: Sendable {
  func discover() async throws -> [DiscoverProfile]
  func like(_ id: UUID) async throws -> LikeResult
  func pass(_ id: UUID) async throws
}
protocol MatchRepository: Sendable {
  func matches() async throws -> [Match]
  func meetingPoint(matchID: UUID) async throws -> GeoPoint
}
extension MatchRepository {
  func meetingPoint(matchID: UUID) async throws -> GeoPoint { throw URLError(.resourceUnavailable) }
}
protocol CoffeeShopRepository: Sendable {
  func shops(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [CoffeeShop]
}
extension CoffeeShopRepository {
  func shops(latitude: Double, longitude: Double) async throws -> [CoffeeShop] {
    try await shops(latitude: latitude, longitude: longitude, radiusKm: 30)
  }
}
protocol ConversationRepository: Sendable {
  func conversations() async throws -> [Conversation]
  func messages(_ id: UUID) async throws -> [ChatMessage]
  func send(_ text: String, to id: UUID, clientMessageID: UUID) async throws -> ChatMessage
}
protocol CoffeeDateRepository: Sendable {
  func myCafes() async throws -> [MyCafeItem]
  func dates() async throws -> [CoffeeDate]
  func propose(match: UUID, shop: UUID, date: Date, payment: PaymentPreference, nookChoice: Bool, idempotencyKey: UUID) async throws
    -> CoffeeDate
  func updateDate(_ id: UUID, status: CoffeeDateStatus) async throws -> CoffeeDate
}
protocol NotificationRepository: Sendable {
  func notifications() async throws -> [NookNotification]
  func markNotificationRead(_ id: UUID) async throws
  func registerDeviceToken(_ token: String) async throws
  func removeDeviceToken(_ token: String) async throws
}
protocol ModerationRepository: Sendable {
  func block(_ userID: UUID) async throws
  func report(_ userID: UUID, reason: String, details: String?) async throws
}

/// Convenience composition used at the application boundary. Features can depend on the
/// narrower contracts above without knowing whether data comes from the API or local mode.
protocol NookRepository: UserRepository, DiscoveryRepository, MatchRepository,
  CoffeeShopRepository, CoffeeDateRepository, ConversationRepository, NotificationRepository,
  ModerationRepository {}
struct ProfileUpdate: Codable {
  var bio: String?
  var city: String?
  var latitude: Double?
  var longitude: Double?
  var lookingFor: LookingFor?
  var coffeePersonality: String?
  var preferredPlan: String?
  var preferredVibe: String?
  var coffeesPerDay: Int?
  var favoriteCoffeeMoment: String?
  var minAge: Int?
  var maxAge: Int?
  var maxDistanceKm: Int?
  var visible: Bool?
  var hidden: Bool?
  var coffeePreferences: [String]?
  var onboardingComplete: Bool?
  var desiredGenders: [String]?
  var discoveryIntentions: [String]?
  var discoveryVibes: [String]?
  var discoveryMoments: [String]?
  var discoveryMeetingStyles: [String]?
}
