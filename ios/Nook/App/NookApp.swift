import SwiftUI
import UIKit
import UserNotifications

enum AppEnvironment: String, Sendable {
  case production, development, demo

  static var current: AppEnvironment {
    if ProcessInfo.processInfo.environment["NOOK_OFFLINE_DEMO"] == "1" { return .demo }
    #if DEBUG
      return .development
    #else
      return .production
    #endif
  }
}

final class NookAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token=deviceToken.map { String(format:"%02x",$0) }.joined()
    NotificationCenter.default.post(name:.nookDeviceToken,object:token)
  }
}
extension Notification.Name { static let nookDeviceToken=Notification.Name("NookDeviceToken") }

@main struct NookApp: App {
  @UIApplicationDelegateAdaptor(NookAppDelegate.self) private var delegate
  @StateObject private var app: AppSession

  init() {
    _app = StateObject(wrappedValue: AppSession(environment: .current))
  }
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(app).tint(.nookCoral).preferredColorScheme(.dark).task {
        #if DEBUG
          if ProcessInfo.processInfo.environment["NOOK_PREVIEW_ONBOARDING"] == "1" {
            await app.enterOfflineDemo()
            app.stage = .onboarding
          } else if ProcessInfo.processInfo.environment["NOOK_OFFLINE_DEMO"] == "1" {
            await app.enterOfflineDemo()
          } else {
            await app.restore()
          }
        #else
          await app.restore()
        #endif
      }.onReceive(NotificationCenter.default.publisher(for:.nookDeviceToken)) { notification in
        guard let token=notification.object as? String else{return}
        app.captureDeviceToken(token)
      }
    }
  }
}
enum AppConfiguration {
  static let apiURL = URL(
    string: ProcessInfo.processInfo.environment["NOOK_API_URL"]
      ?? Bundle.main.object(forInfoDictionaryKey: "NookAPIURL") as? String
      ?? "http://127.0.0.1:8080/api/v1/")!
}
struct MyCafesSnapshot {
  let items: [MyCafeItem]
  let loadedAt: Date
}
struct DiscoverSnapshot {
  let people: [DiscoverProfile]
  let loadedAt: Date
}
@MainActor final class AppSession: ObservableObject {
  private struct StartupTimeout: LocalizedError {
    var errorDescription: String? { "El servidor está tardando demasiado en responder." }
  }
  enum Stage: Equatable { case loading, welcome, registration, onboarding, login, app, startupError(String) }
  @Published var stage: Stage = .loading
  @Published var me: Me?
  @Published var selectedTab = 0
  @Published var selectedCoffeeMatch: UUID?
  @Published var placesReloadID = UUID()
  @Published private(set) var coffeeDataRevision = 0
  @Published private(set) var recentlyPersistedCoffeeDates: [CoffeeDate] = []
  @Published private(set) var discoveryRevision = 0
  private(set) var myCafesCache: MyCafesSnapshot?
  private(set) var discoverCache: DiscoverSnapshot?
  @Published var tabBarHidden = false
  private var deviceToken: String?
  let environment: AppEnvironment
  var repository: any NookRepository
  init(environment: AppEnvironment = .current, repository: (any NookRepository)? = nil) {
    self.environment = environment
    #if DEBUG
      self.repository = repository ?? (environment == .demo
        ? OfflineDemoRepository() : APIRepository(baseURL: AppConfiguration.apiURL))
    #else
      self.repository = repository ?? APIRepository(baseURL: AppConfiguration.apiURL)
    #endif
  }
  func restore() async {
    let minimumIntro = Task { try? await Task.sleep(for: .seconds(1.8)) }
    do {
      let restored = try await withThrowingTaskGroup(of: Me?.self) { group in
        let repository = self.repository
        group.addTask { try await repository.restore() }
        group.addTask {
          try await Task.sleep(for: .seconds(18))
          throw StartupTimeout()
        }
        guard let first = try await group.next() else { throw StartupTimeout() }
        group.cancelAll()
        return first
      }
      await minimumIntro.value
      if let m = restored {
        me = m
        enterAuthenticated(m)
      } else {
        stage = .login
      }
    } catch is CancellationError {
      return
    } catch {
      await minimumIntro.value
      stage = .startupError(
        "Nook está tardando en despertar. Tu sesión sigue guardada; comprueba la conexión y vuelve a intentarlo.")
    }
  }
  func login(_ email: String, _ password: String) async throws {
    enterAuthenticated(try await repository.login(email: email, password: password))
  }
  func federatedLogin(provider: String, identityToken: String, displayName: String?) async throws {
    let authenticatedUser = try await repository.federatedLogin(
      provider: provider, identityToken: identityToken, displayName: displayName)
    enterAuthenticated(authenticatedUser)
  }
  func requestPhoneOtp(_ phone: String) async throws -> PhoneOtpChallenge { try await repository.requestPhoneOtp(phone) }
  func verifyPhoneOtp(challengeId: UUID, code: String) async throws {
    enterAuthenticated(try await repository.verifyPhoneOtp(challengeId: challengeId, code: code))
  }
  func register(
    email: String, password: String, name: String, birth: Date, gender: Gender, looking: LookingFor
  ) async throws {
    me = try await repository.register(
      email: email, password: password, name: name, birthDate: birth, gender: gender,
      lookingFor: looking)
    stage = .onboarding
  }
  func finish(_ p: ProfileUpdate) async throws {
    me = try await repository.updateProfile(p)
    stage = .app
  }
  func logout() async {
    if let deviceToken { try? await repository.removeDeviceToken(deviceToken) }
    await repository.logout()
    me = nil
    resetNavigation()
    stage = .welcome
  }
  private func enterAuthenticated(_ user: Me) {
    me = user
    resetNavigation()
    stage = user.onboardingComplete ? .app : .onboarding
  }
  private func resetNavigation() {
    selectedTab = 0
    selectedCoffeeMatch = nil
    placesReloadID = UUID()
    tabBarHidden = false
    recentlyPersistedCoffeeDates = []
    myCafesCache = nil
    discoverCache = nil
  }
  func captureDeviceToken(_ token: String) {
    deviceToken=token
    guard stage == .app else { return }
    Task { try? await repository.registerDeviceToken(token) }
  }
  func registerCapturedDeviceIfNeeded() async {
    guard let deviceToken,stage == .app else { return }
    try? await repository.registerDeviceToken(deviceToken)
  }
  func requestPushAuthorization() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let granted: Bool
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      granted = true
    case .notDetermined:
      granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true
    case .denied:
      granted = false
    @unknown default:
      granted = false
    }
    if granted {
      UIApplication.shared.registerForRemoteNotifications()
      await registerCapturedDeviceIfNeeded()
    }
    return granted
  }
  func coffeeProposalPersisted(_ date: CoffeeDate? = nil) {
    if let date {
      recentlyPersistedCoffeeDates.removeAll { $0.id == date.id }
      recentlyPersistedCoffeeDates.insert(date, at: 0)
    }
    coffeeDataRevision += 1
  }
  func cacheMyCafes(_ items: [MyCafeItem]) {
    myCafesCache = MyCafesSnapshot(items: items, loadedAt: Date())
  }
  func cacheDiscover(_ people: [DiscoverProfile]) {
    discoverCache = DiscoverSnapshot(people: people, loadedAt: Date())
  }
  func upsertCachedCoffeeDate(_ date: CoffeeDate) {
    guard let cache = myCafesCache else { return }
    var items = cache.items
    if let index = items.firstIndex(where: { $0.matchId == date.matchId }) {
      items[index].proposal = date
    }
    cacheMyCafes(items)
  }
  func discoveryPreferencesPersisted() { discoveryRevision += 1 }
  #if DEBUG
    func enterOfflineDemo() async {
      repository = OfflineDemoRepository()
      me = try? await repository.restore()
      selectedTab = Int(ProcessInfo.processInfo.environment["NOOK_START_TAB"] ?? "0") ?? 0
      stage = .app
    }

    func enterOfflineOnboarding() async {
      repository = OfflineDemoRepository()
      me = try? await repository.restore()
      stage = .registration
    }
  #endif
}
