import CoreLocation
import Foundation
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
  @Published var location: CLLocation?
  @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published private(set) var locationError: String?
  @Published private(set) var locating = false
  private let manager = CLLocationManager()
  private var retryCount = 0
  private var bestCandidate: CLLocation?
  private var settlingTask: Task<Void, Never>?
  private let targetAccuracy: CLLocationAccuracy = 50
  private let maximumAcceptedAccuracy: CLLocationAccuracy = 150
  var denied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
  var servicesDisabled: Bool { !CLLocationManager.locationServicesEnabled() }
  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = kCLDistanceFilterNone
    manager.activityType = .otherNavigation
    manager.pausesLocationUpdatesAutomatically = false
    authorizationStatus = manager.authorizationStatus
  }
  func request() {
    guard CLLocationManager.locationServicesEnabled() else {
      locationError = "Los servicios de ubicación están desactivados."
      return
    }
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      bestCandidate = nil
      settlingTask?.cancel()
      locating = true
      manager.startUpdatingLocation()
    case .denied, .restricted: break
    @unknown default: break
    }
  }
  func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationStatus = manager.authorizationStatus
    if manager.authorizationStatus == .authorizedWhenInUse
      || manager.authorizationStatus == .authorizedAlways
    {
      locating = true
      manager.startUpdatingLocation()
    }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    let candidates = locations
      .filter { isValid($0, maximumAge: 10) }
      .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
    guard let candidate = candidates else {
      locationError = "Todavía no tenemos una ubicación suficientemente precisa."
      return
    }
    if bestCandidate == nil || candidate.horizontalAccuracy < bestCandidate!.horizontalAccuracy {
      bestCandidate = candidate
    }
    if candidate.horizontalAccuracy <= targetAccuracy {
      finish(with: candidate)
      return
    }
    locationError = "Afinando tu ubicación…"
    if settlingTask == nil {
      settlingTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled, let self else { return }
        if let best = self.bestCandidate,
          best.horizontalAccuracy <= self.maximumAcceptedAccuracy,
          self.isValid(best, maximumAge: 10)
        {
          self.finish(with: best)
        } else {
          self.locationError = "Necesitamos una señal GPS más precisa. Inténtalo de nuevo al aire libre."
        }
      }
    }
  }
  private func finish(with valid: CLLocation) {
    settlingTask?.cancel()
    settlingTask = nil
    manager.stopUpdatingLocation()
    locating = false
    retryCount = 0
    bestCandidate = nil
    location = valid
    locationError = nil
    #if DEBUG
      print("[NOOK LOCATION] Origin: CURRENT_LOCATION latitude=\(valid.coordinate.latitude) longitude=\(valid.coordinate.longitude) accuracy=\(Int(valid.horizontalAccuracy))m age=\(Int(abs(Date().timeIntervalSince(valid.timestamp))))s")
    #endif
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    locating = false
    if (error as? CLError)?.code == .locationUnknown {
      locationError = "Buscando una señal GPS válida…"
      if retryCount < 2 {
        retryCount += 1
        locating = true
        manager.startUpdatingLocation()
      }
    } else {
      locationError = error.localizedDescription
    }
  }
  private func isValid(_ value: CLLocation, maximumAge: TimeInterval) -> Bool {
    let age = abs(Date().timeIntervalSince(value.timestamp))
    return age <= maximumAge && value.horizontalAccuracy >= 0
      && value.horizontalAccuracy <= maximumAcceptedAccuracy
      && CLLocationCoordinate2DIsValid(value.coordinate)
      && !(value.coordinate.latitude == 0 && value.coordinate.longitude == 0)
  }
}

#if DEBUG
  actor OfflineDemoRepository: NookRepository {
    private let current = Me(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, email: "albert@nook.demo",
      name: "Albert", age: 31, birthDate: "1995-03-12", gender: .man,
      bio: "Producto, música y cafés con calma.", city: "Barcelona", lookingFor: .meetPeople,
      coffeePersonality: "Solo ☕", preferredPlan: "LONG_TALKS", preferredVibe: "CALM",
      coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK", minAge: 22, maxAge: 40,
      maxDistanceKm: 30, visible: true, hidden: false, onboardingComplete: true,
      coffeePreferences: ["ESPRESSO", "LATTE"],
      photos: [
        Photo(
          id: UUID(),
          url:
            "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1000&q=85",
          position: 0)
      ])
    private var people: [DiscoverProfile] = [
      DiscoverProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Laura", age: 29,
        bio: "Arquitecta, conciertos y cafeterías pequeñas.", city: "Barcelona", distanceKm: 1.4,
        coffeePersonality: "Café con leche 🥛", preferredPlan: "LONG_TALKS",
        preferredVibe: "CALM", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK",
        lookingFor: .seeWhatHappens, coffeePreferences: ["LATTE", "MATCHA"],
        photos: [
          Photo(
            id: UUID(),
            url:
              "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1000&q=85",
            position: 0)
        ]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Clara", age: 28, bio: "Diseño, vinilos y sobremesas largas.", city: "Barcelona", distanceKm: 1.8, coffeePersonality: "Cortado 🥛", preferredPlan: "LONG_TALKS", preferredVibe: "SOCIAL", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK", lookingFor: .seeWhatHappens, coffeePreferences: ["CORTADO"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Elena", age: 32, bio: "Cine, cocina y rincones tranquilos.", city: "Barcelona", distanceKm: 2.4, coffeePersonality: "Solo ☕", preferredPlan: "QUICK", preferredVibe: "CALM", coffeesPerDay: 1, favoriteCoffeeMoment: "MORNING", lookingFor: .friendship, coffeePreferences: ["ESPRESSO"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "Nora", age: 26, bio: "Ilustración, montaña y probar sitios nuevos.", city: "Barcelona", distanceKm: 3.0, coffeePersonality: "Matcha 🍵", preferredPlan: "WALK", preferredVibe: "LIVELY", coffeesPerDay: 1, favoriteCoffeeMoment: "EVENING", lookingFor: .meetPeople, coffeePreferences: ["MATCHA"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, name: "Julia", age: 30, bio: "Editorial, teatro y escapadas de domingo.", city: "Barcelona", distanceKm: 3.7, coffeePersonality: "Café con leche 🥛", preferredPlan: "IMPROVISE", preferredVibe: "SOCIAL", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK", lookingFor: .somethingMore, coffeePreferences: ["LATTE"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "Aina", age: 27, bio: "Arquitectura, fotografía y pasear sin mapa.", city: "Barcelona", distanceKm: 4.1, coffeePersonality: "Café frío 🧊", preferredPlan: "WALK", preferredVibe: "CALM", coffeesPerDay: 2, favoriteCoffeeMoment: "EVENING", lookingFor: .seeWhatHappens, coffeePreferences: ["ICED_COFFEE"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, name: "Irene", age: 31, bio: "Música en directo, libros y conversaciones honestas.", city: "Barcelona", distanceKm: 4.6, coffeePersonality: "Té 🫖", preferredPlan: "LONG_TALKS", preferredVibe: "CALM", coffeesPerDay: 0, favoriteCoffeeMoment: "AFTERWORK", lookingFor: .friendship, coffeePreferences: ["TEA"], photos: [Photo(id: UUID(), url: "https://images.unsplash.com/photo-1524250502761-1ac6f2e30d43?auto=format&fit=crop&w=1000&q=85", position: 0)]),
      DiscoverProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Marta", age: 27,
        bio: "Cerámica, libros y paseos sin prisa.", city: "Barcelona", distanceKm: 2.1,
        coffeePersonality: "Matcha 🍵", preferredPlan: "WALK", preferredVibe: "CALM",
        coffeesPerDay: 1, favoriteCoffeeMoment: "EVENING", lookingFor: .friendship,
        coffeePreferences: ["MATCHA", "TEA"],
        photos: [
          Photo(
            id: UUID(),
            url:
              "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1000&q=85",
            position: 0)
        ]),
      DiscoverProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Sofía", age: 30,
        bio: "Fotografía, viajes y café por la mañana.", city: "Barcelona", distanceKm: 3.6,
        coffeePersonality: "Café frío 🧊", preferredPlan: "QUICK", preferredVibe: "SOCIAL",
        coffeesPerDay: 3, favoriteCoffeeMoment: "MORNING", lookingFor: .somethingMore,
        coffeePreferences: ["ICED_COFFEE"],
        photos: [
          Photo(
            id: UUID(),
            url:
              "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1000&q=85",
            position: 0)
        ]),
    ]
    private let demoShops: [CoffeeShop] = [
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Nomad Coffee",
        address: "El Born, Barcelona", neighborhood: "El Born", distanceKm: 0.25, photoUrl: "https://images.unsplash.com/photo-1445116572660-236099ec97a0?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Perfecto para hablar",
        vibes: ["CALM"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "Satan's Coffee Corner",
        address: "Barri Gòtic, Barcelona", neighborhood: "Barri Gòtic", distanceKm: 0.8, photoUrl: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Más energía y movimiento",
        vibes: ["LIVELY"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Three Marks Coffee",
        address: "Fort Pienc, Barcelona", neighborhood: "Fort Pienc", distanceKm: 1.2, photoUrl: "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Movimiento, pero se puede conversar",
        vibes: ["SOCIAL"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, name: "Hidden Coffee Roasters",
        address: "Les Corts, Barcelona", neighborhood: "Les Corts", distanceKm: 1.7, photoUrl: "https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Perfecto para hablar", vibes: ["CALM"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, name: "Syra Coffee",
        address: "Poble-sec, Barcelona", neighborhood: "Poble-sec", distanceKm: 2.0, photoUrl: "https://images.unsplash.com/photo-1559925393-8be0ec4767c8?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Movimiento, pero se puede conversar", vibes: ["SOCIAL"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, name: "SlowMov",
        address: "Gràcia, Barcelona", neighborhood: "Gràcia", distanceKm: 2.4, photoUrl: "https://images.unsplash.com/photo-1445116572660-236099ec97a0?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Perfecto para hablar", vibes: ["CALM"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!, name: "News & Coffee",
        address: "Sant Antoni, Barcelona", neighborhood: "Sant Antoni", distanceKm: 2.8, photoUrl: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Más energía y movimiento", vibes: ["LIVELY"]),
      CoffeeShop(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!, name: "Federal Café",
        address: "Sant Antoni, Barcelona", neighborhood: "Sant Antoni", distanceKm: 3.1, photoUrl: "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=1200&q=85",
        openingHours: "Lun–Dom · 08:00–20:00", rating: nil, description: "Movimiento, pero se puede conversar", vibes: ["SOCIAL"]),
    ]
    private var demoMatches: [Match] = []
    private var demoConversations: [Conversation] = []
    private var demoMessages: [UUID: [ChatMessage]] = [:]
    private var demoDates: [CoffeeDate] = []
    init() {
      let moreNames = ["Emma", "Valeria", "Carlota", "Lia", "Marina", "Berta", "Olivia", "Alba", "Vega"]
      for (index, name) in moreNames.enumerated() {
        people.append(DiscoverProfile(
          id: UUID(), name: name, age: 25 + index % 8,
          bio: ["Viajes, cocina y descubrir barrios.", "Arte, perros y charlas sin prisa.", "Música, naturaleza y buenos libros."][index % 3],
          city: "Barcelona", distanceKm: 1.1 + Double(index) * 0.55,
          coffeePersonality: ["Solo ☕", "Café con leche 🥛", "Matcha 🍵"][index % 3],
          preferredPlan: ["QUICK", "LONG_TALKS", "WALK"][index % 3],
          preferredVibe: ["CALM", "SOCIAL", "LIVELY"][index % 3], coffeesPerDay: index % 4,
          favoriteCoffeeMoment: ["MORNING", "AFTERWORK", "EVENING"][index % 3],
          lookingFor: [.meetPeople, .friendship, .seeWhatHappens][index % 3],
          coffeePreferences: [["ESPRESSO"], ["LATTE"], ["MATCHA"]][index % 3],
          photos: [Photo(id: UUID(), url: [
            "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1000&q=85",
            "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=1000&q=85",
            "https://images.unsplash.com/photo-1524250502761-1ac6f2e30d43?auto=format&fit=crop&w=1000&q=85",
          ][index % 3], position: 0)]))
      }
      let now = Date()
      for (index, person) in people.prefix(3).enumerated() {
        let match = Match(id: UUID(), person: person, matchedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(-index) * 86_400)), conversationId: UUID())
        demoMatches.append(match)
        demoConversations.append(Conversation(id: match.conversationId, matchId: match.id, person: person, lastMessage: index == 0 ? "¿Te va bien el viernes?" : "¡Nos vemos allí! ☕", updatedAt: ISO8601DateFormatter().string(from: now)))
        demoMessages[match.conversationId] = [ChatMessage(id: UUID(), senderId: person.id, body: index == 0 ? "¡Hola! Me encanta esa cafetería." : "Qué ganas de ese café ☕", type: "TEXT", createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-3_600)))]
        let statuses: [CoffeeDateStatus] = [.pending, .accepted, .completed]
        let offsets: [TimeInterval] = [172_800, 259_200, -604_800]
        demoDates.append(CoffeeDate(id: UUID(), matchId: match.id, senderId: index == 0 ? current.id : person.id, receiverId: index == 0 ? person.id : current.id, coffeeShop: demoShops[index], proposedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(offsets[index])), paymentPreference: index == 0 ? .iInvite : .split, status: statuses[index], createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-86_400)), nookChoice: index == 0))
      }
      people.removeFirst(3)
    }
    func register(
      email: String, password: String, name: String, birthDate: Date, gender: Gender,
      lookingFor: LookingFor
    ) async throws -> Me { current }
    func login(email: String, password: String) async throws -> Me { current }
    func federatedLogin(provider: String, identityToken: String, displayName: String?) async throws -> Me { current }
    func requestPhoneOtp(_ phone: String) async throws -> PhoneOtpChallenge { .init(challengeId: UUID(), expiresIn: 300, developmentCode: "123456") }
    func verifyPhoneOtp(challengeId: UUID, code: String) async throws -> Me { current }
    func restore() async throws -> Me? { current }
    func logout() async {}
    func me() async throws -> Me { current }
    func updateProfile(_ payload: ProfileUpdate) async throws -> Me { current }
    func uploadPhoto(data: Data, mimeType: String) async throws -> Photo { current.photos[0] }
    func deletePhoto(_ id: UUID) async throws {}
    func reorderPhotos(_ ids: [UUID]) async throws -> [Photo] { current.photos }
    func makePrimaryPhoto(_ id: UUID) async throws -> Photo { current.photos.first { $0.id == id } ?? current.photos[0] }
    func settings() async throws -> UserSettings {
      UserSettings(coffeeSoundsEnabled: true, pushEnabled: true, locale: "es")
    }
    func updateSettings(_ payload: UserSettingsUpdate) async throws -> UserSettings {
      UserSettings(
        coffeeSoundsEnabled: payload.coffeeSoundsEnabled ?? true,
        pushEnabled: payload.pushEnabled ?? true,
        locale: payload.locale ?? "es")
    }
    func updateLocation(latitude: Double, longitude: Double, accuracy: Double, capturedAt: Date) async throws {}
    func discover() async throws -> [DiscoverProfile] { people }
    func like(_ id: UUID) async throws -> LikeResult {
      guard let person = people.first(where: { $0.id == id }) else {
        return LikeResult(matched: false, match: nil)
      }
      people.removeAll { $0.id == id }
      let match = Match(
        id: UUID(), person: person, matchedAt: ISO8601DateFormatter().string(from: Date()),
        conversationId: UUID())
      demoMatches.append(match)
      demoConversations.append(
        Conversation(
          id: match.conversationId, matchId: match.id, person: person,
          lastMessage: "¡Tenemos café! ☕", updatedAt: ISO8601DateFormatter().string(from: Date())))
      demoMessages[match.conversationId] = []
      return LikeResult(matched: true, match: match)
    }
    func pass(_ id: UUID) async throws { people.removeAll { $0.id == id } }
    func matches() async throws -> [Match] { demoMatches }
    private var liveShops: [CoffeeShop] = []
    func shops(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [CoffeeShop] {
      let path = "cafes/nearby?latitude=\(latitude)&longitude=\(longitude)&radius=\(GeographicMath.meters(fromKilometers: radiusKm))"
      guard let url = URL(string: path, relativeTo: AppConfiguration.apiURL) else { throw URLError(.badURL) }
      var request = URLRequest(url: url)
      request.timeoutInterval = 10
      request.cachePolicy = .useProtocolCachePolicy
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
      }
      var places = try JSONDecoder().decode([CoffeeShop].self, from: data)
      for index in places.indices {
        if let photo = places[index].photoUrl, photo.hasPrefix("/") {
          places[index].photoUrl = URL(string: photo, relativeTo: AppConfiguration.apiURL)?.absoluteURL.absoluteString
        }
        places[index].photoUrls = places[index].photoUrls?.map { photo in
          photo.hasPrefix("/") ? (URL(string: photo, relativeTo: AppConfiguration.apiURL)?.absoluteURL.absoluteString ?? photo) : photo
        }
      }
      liveShops = places
      return places
    }
    func conversations() async throws -> [Conversation] { demoConversations }
    func messages(_ id: UUID) async throws -> [ChatMessage] { demoMessages[id] ?? [] }
    func send(_ text: String, to id: UUID) async throws -> ChatMessage {
      let message = ChatMessage(
        id: UUID(), senderId: current.id, body: text, type: "TEXT",
        createdAt: ISO8601DateFormatter().string(from: Date()))
      demoMessages[id, default: []].append(message)
      return message
    }
    func dates() async throws -> [CoffeeDate] {
      let formatter = ISO8601DateFormatter.nook
      let now = Date()
      demoDates = demoDates.map { value in
        guard value.status == .accepted, let start = formatter.date(from: value.proposedAt),
          now >= start.addingTimeInterval(86_400) else { return value }
        return CoffeeDate(
          id: value.id, matchId: value.matchId, senderId: value.senderId,
          receiverId: value.receiverId, coffeeShop: value.coffeeShop,
          proposedAt: value.proposedAt, paymentPreference: value.paymentPreference,
          status: .completed, createdAt: value.createdAt, nookChoice: value.nookChoice)
      }
      return demoDates
    }
    func propose(match: UUID, shop: UUID, date: Date, payment: PaymentPreference, nookChoice: Bool) async throws
      -> CoffeeDate
    {
      let receiver =
        demoMatches.first(where: { $0.id == match })?.person.id ?? people.first?.id ?? current.id
      let value = CoffeeDate(
        id: UUID(), matchId: match, senderId: current.id, receiverId: receiver,
        coffeeShop: liveShops.first(where: { $0.id == shop })
          ?? demoShops.first(where: { $0.id == shop }) ?? demoShops[0],
        proposedAt: ISO8601DateFormatter().string(from: date), paymentPreference: payment,
        status: .pending, createdAt: ISO8601DateFormatter().string(from: Date()), nookChoice: nookChoice)
      demoDates.append(value)
      return value
    }
    func updateDate(_ id: UUID, status: CoffeeDateStatus) async throws -> CoffeeDate {
      guard let index = demoDates.firstIndex(where: { $0.id == id }) else {
        throw URLError(.fileDoesNotExist)
      }
      let old = demoDates[index]
      let value = CoffeeDate(
        id: old.id, matchId: old.matchId, senderId: old.senderId, receiverId: old.receiverId,
        coffeeShop: old.coffeeShop, proposedAt: old.proposedAt,
        paymentPreference: old.paymentPreference, status: status, createdAt: old.createdAt, nookChoice: old.nookChoice)
      demoDates[index] = value
      return value
    }
    func notifications() async throws -> [NookNotification] { [] }
    func markNotificationRead(_ id: UUID) async throws {}
    func registerDeviceToken(_ token: String) async throws {}
    func removeDeviceToken(_ token: String) async throws {}
    func block(_ userID: UUID) async throws { people.removeAll { $0.id == userID } }
    func report(_ userID: UUID, reason: String, details: String?) async throws {}
  }
#endif
