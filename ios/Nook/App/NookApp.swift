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
      }.onChange(of: app.stage) { _,stage in
        guard stage == .app else{return}
        Task {
          let granted=(try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound])) == true
          if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            await app.registerCapturedDeviceIfNeeded()
          }
        }
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
@MainActor final class AppSession: ObservableObject {
  enum Stage: Equatable { case loading, welcome, registration, onboarding, login, app, startupError(String) }
  @Published var stage: Stage = .loading
  @Published var me: Me?
  @Published var selectedTab = 0
  @Published var selectedCoffeeMatch: UUID?
  @Published var placesReloadID = UUID()
  @Published private(set) var coffeeDataRevision = 0
  @Published private(set) var discoveryRevision = 0
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
    do {
      if let m = try await repository.restore() {
        me = m
        stage = m.onboardingComplete ? .app : .onboarding
      } else {
        stage = .welcome
      }
    } catch {
      stage = .startupError(
        "No hemos podido conectar con Nook. Tu sesión sigue guardada; vuelve a intentarlo.")
    }
  }
  func login(_ email: String, _ password: String) async throws {
    me = try await repository.login(email: email, password: password)
    stage = me?.onboardingComplete == true ? .app : .onboarding
  }
  func federatedLogin(provider: String, identityToken: String, displayName: String?) async throws {
    me = try await repository.federatedLogin(provider: provider, identityToken: identityToken, displayName: displayName)
    stage = me?.onboardingComplete == true ? .app : .onboarding
  }
  func requestPhoneOtp(_ phone: String) async throws -> PhoneOtpChallenge { try await repository.requestPhoneOtp(phone) }
  func verifyPhoneOtp(challengeId: UUID, code: String) async throws {
    me = try await repository.verifyPhoneOtp(challengeId: challengeId, code: code)
    stage = me?.onboardingComplete == true ? .app : .onboarding
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
    stage = .welcome
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
  func coffeeProposalPersisted() { coffeeDataRevision += 1 }
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
