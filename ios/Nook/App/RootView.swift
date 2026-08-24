import PhotosUI
import SwiftUI
import CoreLocation
import AuthenticationServices

struct RootView: View {
  @EnvironmentObject var app: AppSession
  var body: some View {
    ZStack {
      NookBackground()
      if app.stage == .loading {
        NookIntroView()
          .transition(.asymmetric(
            insertion: .opacity,
            removal: .scale(scale: 2.8).combined(with: .opacity)))
      } else {
        content.transition(.opacity)
      }
    }.animation(.easeInOut(duration: 0.62), value: app.stage)
  }
  @ViewBuilder private var content: some View {
    #if DEBUG
      if app.stage == .app, let route = ProcessInfo.processInfo.environment["NOOK_PREVIEW_SCREEN"] {
        ReviewRouteView(route: route)
      } else {
        stageContent
      }
    #else
      stageContent
    #endif
  }
  @ViewBuilder private var stageContent: some View {
    switch app.stage {
    case .loading: EmptyView()
    case .welcome: WelcomeView()
    case .registration: RegistrationFlow()
    case .login: LoginView()
    case .onboarding: OnboardingView()
    case .app: MainTabView()
    case .startupError(let message):
      NookErrorView(message: message) {
        app.stage = .loading
        Task { await app.restore() }
      }.padding(.horizontal, 20)
    }
  }
}

#if DEBUG
struct ReviewRouteView: View {
  @EnvironmentObject var app: AppSession
  let route: String
  @State private var matches: [Match] = []
  @State private var shops: [CoffeeShop] = []
  @State private var chats: [Conversation] = []
  @Namespace private var namespace
  var body: some View {
    NavigationStack {
      Group {
        if route == "person", let person = matches.first?.person { PersonProfileView(person: person) }
        else if route == "shop", let shop = shops.first { CoffeeShopDetail(shop: shop, matches: matches, namespace: namespace) }
        else if route == "proposal", let shop = shops.first { ProposalSheet(shop: shop, matches: matches) }
        else if route == "chat", let chat = chats.first { ChatDetail(conversation: chat) }
        else if route == "settings" { SettingsView() }
        else { NookLoadingView() }
      }
    }.task {
      async let m = try? app.repository.matches()
      async let s = try? app.repository.shops(latitude: 41.3874, longitude: 2.1686)
      async let c = try? app.repository.conversations()
      matches = await m ?? []; shops = await s ?? []; chats = await c ?? []
    }
  }
}
#endif

struct NookIntroView: View {
  var compact = false
  @State private var appeared = false
  @State private var haloExpanded = false
  @State private var orbiting = false
  @State private var pulsing = false
  var body: some View {
    ZStack {
      NookColors.warmBlack.ignoresSafeArea()
      VStack(spacing: 18) {
        ZStack {
          Circle()
            .stroke(.white.opacity(0.28), lineWidth: 1)
            .frame(width: 190, height: 190)
            .scaleEffect(haloExpanded ? 1.18 : 0.62)
            .opacity(haloExpanded ? 0 : 0.78)
          Circle()
            .trim(from: 0.08, to: 0.7)
            .stroke(.white.opacity(0.58), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 148, height: 148)
            .rotationEffect(.degrees(orbiting ? 360 : -35))
          Circle().fill(.white).frame(width: 126, height: 126)
          NookCoffeeLogo(size: 112, animated: false).clipShape(Circle())
        }
        .frame(width: 190, height: 190)
        .scaleEffect(pulsing ? 1.035 : 1)
        .shadow(color: .white.opacity(0.16), radius: 34)
        .shadow(color: NookColors.mocha.opacity(0.3), radius: 24, y: 12)
      }
      .scaleEffect(appeared ? 1 : 0.76)
      .opacity(appeared ? 1 : 0)
    }
    .onAppear {
      withAnimation(.spring(response: compact ? 0.48 : 0.72, dampingFraction: 0.8)) {
        appeared = true
      }
      withAnimation(.easeOut(duration: compact ? 0.65 : 1.15).delay(0.12)) {
        haloExpanded = true
      }
      withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
        pulsing = true
      }
      withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
        orbiting = true
      }
      if !compact { NookSoundManager.shared.play(.intro) }
    }
  }
}

struct TopDownCoffeeCup: View {
  let foamProgress: CGFloat
  var body: some View {
    ZStack {
      Circle().fill(NookColors.oat.opacity(0.52)).frame(width: 206, height: 206)
        .shadow(color: NookColors.warmBlack.opacity(0.16), radius: 22, y: 12)
      Circle().fill(NookColors.offWhite).frame(width: 170, height: 170)
        .overlay { Circle().stroke(NookColors.oat.opacity(0.55), lineWidth: 2) }
      Circle().fill(
        RadialGradient(colors: [NookColors.mocha, NookColors.warmBlack], center: .topLeading, startRadius: 4, endRadius: 85)
      ).frame(width: 144, height: 144)
      Circle().trim(from: 0.04, to: 0.32).stroke(NookColors.offWhite, lineWidth: 16)
        .frame(width: 52, height: 52).offset(x: 94).rotationEffect(.degrees(-18))
        .shadow(color: NookColors.warmBlack.opacity(0.1), radius: 4, y: 2)
      CoffeeFoamSpiral(progress: foamProgress)
        .stroke(NookColors.cream.opacity(0.94), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .frame(width: 105, height: 105).rotationEffect(.degrees(foamProgress * 245))
      Circle().fill(NookColors.cream.opacity(0.9)).frame(width: 11, height: 11)
        .scaleEffect(foamProgress).opacity(foamProgress)
    }
  }
}

struct CoffeeFoamSpiral: Shape {
  var progress: CGFloat
  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let turns: CGFloat = 2.7
    let steps = 180
    for index in 0...steps {
      let fraction = CGFloat(index) / CGFloat(steps)
      guard fraction <= progress else { break }
      let angle = fraction * turns * .pi * 2
      let radius = 7 + fraction * min(rect.width, rect.height) * 0.44
      let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
  }
}

struct NookLoadingView: View {
  @State private var floating = false
  @State private var turning = false
  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle().stroke(NookColors.oat.opacity(0.22), lineWidth: 4).frame(width: 82, height: 82)
        Circle().trim(from: 0.08, to: 0.72).stroke(
          NookColors.mocha, style: StrokeStyle(lineWidth: 4, lineCap: .round)
        ).frame(width: 82, height: 82).rotationEffect(.degrees(turning ? 360 : 0))
        NookCoffeeLogo(size: 54).offset(y: floating ? -2 : 2)
      }
      VStack(spacing: 5) {
        Text("Preparando el café…").font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(NookColors.espresso)
        Text("Un momento, ya casi está").font(.caption.weight(.medium))
          .foregroundStyle(NookColors.warmGray)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        withAnimation(.easeInOut(duration: 1.05).repeatForever()) { floating = true }
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { turning = true }
      }
  }
}

struct WelcomeView: View {
  @EnvironmentObject var app: AppSession
  @State private var phase = 0
  @State private var quickAccess = false
  @State private var quickAccessLogin = false
  var body: some View {
    ZStack(alignment: .bottom) {
      NookWelcomeGallery(active: phase >= 1)
      LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.18), NookColors.warmBlack.opacity(0.96)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          NookCoffeeLogo(size: 46, animated: false)
          Text("NOOK").font(.system(size: 24, weight: .black, design: .rounded)).tracking(2)
        }.opacity(phase >= 2 ? 1 : 0)
        VStack(alignment: .leading, spacing: 8) {
          Text("Todo empieza\npor un café.").font(NookTypography.display(51))
            .tracking(-1.7).lineSpacing(-3)
          Text("Conoce a alguien. Elige un sitio. Tomad un café.")
            .font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.76))
        }.offset(y: phase >= 4 ? 0 : 18).opacity(phase >= 4 ? 1 : 0)
        NookButton(title: "EMPEZAR", icon: "arrow.right") {
          quickAccessLogin = false
          quickAccess = true
        }
          .opacity(phase >= 5 ? 1 : 0)
          .offset(y: phase >= 5 ? 0 : 42)
          .scaleEffect(phase >= 5 ? 1 : 0.96)
          .blur(radius: phase >= 5 ? 0 : 5)
        Button("Ya tengo cuenta") {
          quickAccessLogin = true
          quickAccess = true
        }
          .frame(maxWidth: .infinity)
          .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
          .opacity(phase >= 5 ? 1 : 0)
        Text("Solo para mayores de 18 años").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.48))
      }.foregroundStyle(.white).padding(.horizontal, 22).padding(.bottom, 16)
        .opacity(quickAccess ? 0 : 1).offset(y: quickAccess ? 32 : 0)
      if quickAccess {
        QuickAccessView(isPresented: $quickAccess, startWithLogin: quickAccessLogin)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }.animation(NookMotion.spring, value: quickAccess)
      .onAppear {
      phase = 0
      withAnimation(.easeOut(duration: 0.35)) { phase = 1 }
      withAnimation(NookMotion.spring.delay(0.25)) { phase = 2 }
      withAnimation(.easeOut(duration: 0.45).delay(0.75)) { phase = 4 }
      withAnimation(.spring(response: 0.62, dampingFraction: 0.78).delay(1.12)) { phase = 5 }
    }
  }
}

private struct QuickAccessView: View {
  @EnvironmentObject var app: AppSession
  @Binding var isPresented: Bool
  @State private var busy = false
  @State private var busyAction: Int?
  @State private var error: String?
  @State private var emailLogin: Bool
  @State private var createAccount = false
  @State private var email = ""
  @State private var password = ""
  @StateObject private var apple = AppleSignInCoordinator()
  @StateObject private var google = GoogleSignInCoordinator()
  @State private var revealed = false
  @State private var brewed = false
  init(isPresented: Binding<Bool>, startWithLogin: Bool = false) {
    _isPresented = isPresented
    _emailLogin = State(initialValue: startWithLogin)
  }
  var body: some View {
    ZStack(alignment: .bottom) {
      LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.78), NookColors.warmBlack.opacity(0.98)], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea().onTapGesture { isPresented = false }
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Button {
            withAnimation(NookMotion.spring) {
              if emailLogin { emailLogin = false; createAccount = false; error = nil }
              else { isPresented = false }
            }
          } label: {
            Image(systemName: emailLogin ? "chevron.left" : "xmark")
              .font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
              .background(.white.opacity(0.14), in: Circle())
          }
          Spacer()
          NookCoffeeLogo(size: 34, animated: false).opacity(0.94)
        }
        if emailLogin {
          VStack(alignment: .leading, spacing: 7) {
            Text(createAccount ? "Tu primer café" : "Qué alegría verte")
              .font(NookTypography.display(36)).tracking(-0.8)
            Text(createAccount ? "Crea tu acceso. El perfil viene después." : "Entra y retomamos ese café.")
              .font(.body).foregroundStyle(.white.opacity(0.66))
          }
          VStack(spacing: 12) {
            CinematicLoginField(
              label: "Email", icon: "envelope.fill", text: $email, keyboard: .emailAddress)
            CinematicLoginField(label: "Contraseña", icon: "lock.fill", text: $password, secure: true)
            if let error {
              Text(error).font(.caption.weight(.semibold)).foregroundStyle(Color.nookCoral)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            accessButton(
              busy ? (createAccount ? "Creando…" : "Entrando…") : (createAccount ? "Crear cuenta" : "Entrar"),
              icon: "arrow.right", primary: true, index: 2
            ) {
              Task { await signInWithEmail() }
            }.disabled(email.isEmpty || password.count < 8)
              .opacity(email.isEmpty || password.count < 8 ? 0.45 : 1)
          }
          HStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
            Text("O CONTINÚA CON").font(.system(size: 9, weight: .bold, design: .rounded))
              .tracking(1.3).foregroundStyle(.white.opacity(0.5)).fixedSize()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
          }
          Button(createAccount ? "Ya tengo cuenta" : "Soy nuevo · Crear cuenta con email") {
            withAnimation(NookMotion.fast) { createAccount.toggle(); error = nil }
          }.font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.74)).frame(maxWidth: .infinity)
          providerButtons
        } else {
          VStack(alignment: .leading, spacing: 7) {
            Text("Entra en Nook").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
            Text("Elige cómo quieres empezar.").font(.body).foregroundStyle(.white.opacity(0.66))
          }
          VStack(spacing: 11) {
            providerButtons
            accessButton("Entrar con email", icon: "envelope.fill", index: 2) {
              withAnimation(NookMotion.spring) { emailLogin = true }
            }
          }
          if let error {
            Text(error).font(.caption.weight(.semibold)).foregroundStyle(Color.nookCoral)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Button("Crear una cuenta con email") {
            createAccount = true
            withAnimation(NookMotion.spring) { emailLogin = true }
          }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.86))
            .frame(maxWidth: .infinity).padding(.top, 2)
        }
        Text("Al continuar aceptas las condiciones y la política de privacidad de Nook.")
          .font(.caption).foregroundStyle(.white.opacity(0.48)).multilineTextAlignment(.center)
      }.foregroundStyle(.white).padding(.horizontal, 22).padding(.bottom, 18)
      CoffeeAccessReveal(active: brewed).allowsHitTesting(false)
    }.onAppear {
      withAnimation(.easeOut(duration: 0.42)) { brewed = true }
      withAnimation(NookMotion.spring.delay(0.18)) { revealed = true }
    }
  }
  private var providerButtons: some View {
    VStack(spacing: 10) {
      NookAuthProviderButton(
        provider: .google, isLoading: busy && busyAction == 1, disabled: busy
      ) { Task { await signInWithGoogle() } }
      NookAuthProviderButton(provider: .apple, disabled: busy) {
        error = "Apple necesita activar Sign in with Apple en una cuenta Developer de pago."
      }
      NookAuthProviderButton(provider: .facebook, disabled: busy) {
        error = "Facebook necesita configurar su App ID y secreto para continuar."
      }
    }
  }
  private func accessButton(_ title: String, icon: String, primary: Bool = false, index: Int, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 13) {
        Image(systemName: icon).font(.system(size: 18, weight: .medium)).frame(width: 24)
        Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
        Spacer()
        if busy && busyAction == index {
          ProgressView().controlSize(.small).tint(primary ? NookColors.inverseText : NookColors.espresso)
        } else {
          Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
        }
      }.foregroundStyle(primary ? NookColors.inverseText : NookColors.espresso)
        .padding(.horizontal, 18).frame(height: 56)
        .background(primary ? NookColors.espresso : NookColors.offWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(NookColors.espresso.opacity(primary ? 0 : 0.12), lineWidth: 0.75) }
    }.buttonStyle(.plain).disabled(busy)
      .opacity(revealed ? 1 : 0)
      .offset(y: revealed ? 0 : CGFloat(24 + index * 8))
      .scaleEffect(revealed ? 1 : 0.96)
      .animation(NookMotion.spring.delay(Double(index) * 0.075), value: revealed)
  }
  private func signInWithApple() async {
    guard !busy else { return }
    busy = true; busyAction = 0; defer { busy = false; busyAction = nil }
    do { let credential = try await apple.signIn(); try await app.federatedLogin(provider: "apple", identityToken: credential.identityToken, displayName: credential.displayName); isPresented = false }
    catch let value as ASAuthorizationError where value.code == .canceled { return }
    catch { self.error = authMessage(error) }
  }
  private func signInWithGoogle() async {
    guard !busy else { return }
    busy = true; busyAction = 1; error = nil; defer { busy = false; busyAction = nil }
    do {
      let token = try await google.signIn()
      try await app.federatedLogin(provider: "google", identityToken: token, displayName: nil)
      isPresented = false
    } catch let value as ASWebAuthenticationSessionError where value.code == .canceledLogin {
      return
    } catch { self.error = authMessage(error) }
  }
  private func signInWithEmail() async {
    guard !busy, !email.isEmpty, password.count >= 8 else { return }
    busy = true; busyAction = 2; error = nil
    defer { busy = false; busyAction = nil }
    do {
      if createAccount { try await app.register(email: email, password: password) }
      else { try await app.login(email, password) }
      Haptics.success()
      isPresented = false
    } catch { self.error = authMessage(error) }
  }
  private func authMessage(_ error: Error) -> String {
    if let urlError = error as? URLError {
      return urlError.code == .notConnectedToInternet
        ? "No tienes conexión. Compruébala y vuelve a intentarlo."
        : "No podemos conectar con Nook ahora mismo. Inténtalo de nuevo en unos segundos."
    }
    let message = error.localizedDescription
    return message.isEmpty ? "No hemos podido completar el acceso." : message
  }
}

private struct CoffeeAccessReveal: View {
  let active: Bool
  var body: some View {
    ZStack {
      ForEach(0..<6, id: \.self) { index in
        Capsule().fill(NookColors.mocha.opacity(0.2)).frame(width: 9, height: 15)
          .overlay { Capsule().stroke(NookColors.latte.opacity(0.35), lineWidth: 0.7).frame(width: 2, height: 9) }
          .rotationEffect(.degrees(Double(index * 53) + (active ? 80 : 0)))
          .offset(
            x: active ? CGFloat([-138, -86, 112, 145, -118, 126][index]) : 0,
            y: active ? CGFloat([-210, 170, -155, 92, -24, 232][index]) : 40
          ).opacity(active ? 0 : 0.65)
          .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.04), value: active)
      }
      VStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Capsule().stroke(NookColors.mocha.opacity(0.17), lineWidth: 2)
            .frame(width: 18, height: 34).offset(x: CGFloat(index - 1) * 10, y: active ? -54 : 28)
            .opacity(active ? 0 : 0.6)
            .animation(.easeOut(duration: 0.8).delay(Double(index) * 0.08), value: active)
        }
      }.offset(y: 210)
    }
  }
}

private struct NookWelcomeGallery: View {
  let active: Bool
  private let heroURL = URL(string: "https://images.unsplash.com/photo-1511081692775-05d0f180a065?auto=format&fit=crop&w=1200&q=85")
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Image("NookIntroCoffee").resizable().scaledToFill()
          .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        NookRemoteImage(url: heroURL) { Color.clear }
          .frame(width: proxy.size.width, height: proxy.size.height).clipped()
          .opacity(active ? 1 : 0)
          .scaleEffect(active ? 1.045 : 1.02)
          .animation(.easeInOut(duration: 1.15), value: active)
        LinearGradient(
          colors: [NookColors.warmBlack.opacity(0.14), .clear], startPoint: .top,
          endPoint: .bottom)
          .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }.ignoresSafeArea()
  }
}

struct LoginView: View {
  private enum LoginPhase: Equatable { case idle, loading, success, error(String) }
  @EnvironmentObject var app: AppSession
  @State private var email = ""
  @State private var password = ""
  @State private var state: LoginPhase = .idle
  @State private var waitingForServer = false
  @State private var providerLoading: String?
  @State private var appeared = false
  @StateObject private var apple = AppleSignInCoordinator()
  @StateObject private var google = GoogleSignInCoordinator()
  private var busy: Bool { state == .loading }
  private var error: String? { if case .error(let message) = state { message } else { nil } }
  var body: some View {
    NavigationStack {
      ZStack {
        NookWelcomeGallery(active: appeared)
        LinearGradient(
          colors: [.clear, NookColors.warmBlack.opacity(0.5), NookColors.warmBlack.opacity(0.98)],
          startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 126)
            HStack(spacing: 10) {
              NookCoffeeLogo(size: 42, animated: false)
              Text("NOOK").font(.system(size: 21, weight: .black, design: .rounded)).tracking(2)
            }.foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
              Text("Qué alegría\nverte.").font(NookTypography.display(48)).tracking(-1.5)
                .lineSpacing(-3)
              Text("Entra y retomamos ese café.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
            }.foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 14) {
              CinematicLoginField(
                label: "Email", icon: "envelope.fill", text: $email, keyboard: .emailAddress)
              CinematicLoginField(label: "Contraseña", icon: "lock.fill", text: $password, secure: true)
              if let error {
                Text(error).font(.callout.weight(.semibold)).foregroundStyle(.red).padding(.horizontal, 4)
                  .transition(.move(edge: .top).combined(with: .opacity))
              }
              NookButton(
                title: busy ? (waitingForServer ? "DESPERTANDO NOOK…" : "ENTRANDO…") : "ENTRAR",
                icon: "arrow.right", isLoading: busy
              ) { Task { await submit() } }.disabled(busy || email.isEmpty || password.count < 8)
                .opacity(busy ? 0.65 : 1)
              HStack(spacing: 12) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                Text("O CONTINÚA CON").font(.system(size: 9, weight: .bold, design: .rounded))
                  .tracking(1.4).foregroundStyle(.white.opacity(0.56)).fixedSize()
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
              }.padding(.vertical, 2)
              VStack(spacing: 10) {
                NookAuthProviderButton(
                  provider: .google, isLoading: providerLoading == "Google", disabled: busy
                ) { Task { await signInWithGoogle() } }
                NookAuthProviderButton(provider: .apple, disabled: busy) {
                  state = .error("Apple necesita activar Sign in with Apple en una cuenta Developer de pago.")
                }
                NookAuthProviderButton(provider: .facebook, disabled: busy) {
                  state = .error("Facebook necesita configurar su App ID y secreto para continuar.")
                }
              }
              Button("¿Aún no tienes cuenta? Crear una") { app.stage = .registration }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .padding(.top, 6)
          }
          .padding(.horizontal, 20).padding(.bottom, 24)
          .offset(y: appeared ? 0 : 22).opacity(appeared ? 1 : 0)
        }.scrollDismissesKeyboard(.interactively)
      }.onAppear {
        withAnimation(.easeOut(duration: 0.75)) { appeared = true }
      }.toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            app.stage = .welcome
          } label: {
            Image(systemName: "chevron.left").font(.headline).frame(width: 42, height: 42)
              .foregroundStyle(.white)
              .background(NookColors.warmBlack.opacity(0.32), in: Circle())
              .overlay { Circle().stroke(.white.opacity(0.22), lineWidth: 1) }
          }
        }
      }.toolbarBackground(.hidden, for: .navigationBar)
    }
  }
  private func submit() async {
    guard !busy else { return }
    state = .loading
    waitingForServer = false
    let waitingTask = Task {
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled else { return }
      await MainActor.run { waitingForServer = true }
    }
    defer { waitingTask.cancel(); waitingForServer = false }
    do {
      try await app.login(email, password)
      state = .success
      Haptics.success()
    } catch { withAnimation(NookMotion.spring) { state = .error(friendly(error)) } }
  }
  private func signInWithApple() async {
    guard !busy else { return }
    state = .loading; providerLoading = "Apple"
    defer { providerLoading = nil }
    do {
      let credential = try await apple.signIn()
      try await app.federatedLogin(
        provider: "apple", identityToken: credential.identityToken,
        displayName: credential.displayName)
      state = .success
      Haptics.success()
    } catch let value as ASAuthorizationError where value.code == .canceled {
      state = .idle
    } catch { state = .error(friendly(error)) }
  }
  private func signInWithGoogle() async {
    guard !busy else { return }
    state = .loading; providerLoading = "Google"
    defer { providerLoading = nil }
    do {
      let token = try await google.signIn()
      try await app.federatedLogin(provider: "google", identityToken: token, displayName: nil)
      state = .success
      Haptics.success()
    } catch let value as ASWebAuthenticationSessionError where value.code == .canceledLogin {
      state = .idle
    } catch { state = .error(friendly(error)) }
  }
  private func friendly(_ error: Error) -> String {
    let message = error.localizedDescription
    return message.isEmpty ? "No hemos podido iniciar sesión. Inténtalo de nuevo." : message
  }
}

private struct NookAuthProviderButton: View {
  enum Provider: Equatable {
    case google, apple, facebook

    var title: String {
      switch self {
      case .google: "Google"
      case .apple: "Apple"
      case .facebook: "Facebook"
      }
    }
  }

  let provider: Provider
  var isLoading = false
  var disabled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 13) {
        if isLoading {
          ProgressView().controlSize(.small).tint(foreground).frame(width: 24)
        } else {
          providerIcon.frame(width: 24)
        }
        Text("Continuar con \(provider.title)")
          .font(.system(size: 17, weight: .semibold, design: .rounded))
        Spacer()
        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, 18).frame(height: 56)
      .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(border, lineWidth: 0.75)
      }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled && !isLoading ? 0.62 : 1)
  }

  @ViewBuilder private var providerIcon: some View {
    switch provider {
    case .google:
      Text("G").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
    case .apple:
      Image(systemName: "apple.logo").font(.system(size: 20, weight: .medium))
    case .facebook:
      Text("f").font(.system(size: 24, weight: .bold, design: .rounded)).offset(y: 2)
    }
  }

  private var background: Color {
    switch provider {
    case .google: NookColors.offWhite
    case .apple: .black
    case .facebook: Color(red: 0.09, green: 0.39, blue: 0.78)
    }
  }
  private var foreground: Color { provider == .google ? NookColors.espresso : .white }
  private var border: Color { provider == .google ? NookColors.espresso.opacity(0.12) : .white.opacity(0.16) }
}

private struct CinematicLoginField: View {
  let label: String
  let icon: String
  @Binding var text: String
  var secure = false
  var keyboard: UIKeyboardType = .default
  @FocusState private var focused: Bool
  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: icon).font(.system(size: 16, weight: .semibold))
        .foregroundStyle(focused ? .white : .white.opacity(0.54)).frame(width: 22)
      Group {
        if secure { SecureField(label, text: $text) }
        else { TextField(label, text: $text).keyboardType(keyboard) }
      }
      .font(.system(size: 17, weight: .semibold, design: .rounded))
      .foregroundStyle(.white).tint(.white)
      .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
      .focused($focused)
    }
    .padding(.horizontal, 17).frame(height: 56)
    .background(.black.opacity(focused ? 0.3 : 0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(.white.opacity(focused ? 0.48 : 0.2), lineWidth: focused ? 1.5 : 1)
    }
    .animation(NookMotion.fast, value: focused)
  }
}

struct RegistrationFlow: View {
  @EnvironmentObject var app: AppSession
  @State private var step = 0
  @State private var direction = 1
  @State private var name = ""
  @State private var birth = Calendar.current.date(byAdding: .year, value: -25, to: Date())!
  @State private var gender = Gender.woman
  @State private var looking = LookingFor.casualCoffee
  @State private var email = ""
  @State private var password = ""
  @State private var busy = false
  @State private var error: String?
  private let total = 16
  var body: some View {
    ZStack {
      NookBackground()
      VStack(spacing: 0) {
        HStack {
          Button { back() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
          NookProgressBar(step: step, total: total)
        }.padding(.horizontal, 18).padding(.top, 8)
        ZStack { currentStep.id(step).transition(stepTransition) }.animation(NookMotion.spring, value: step)
        NookButton(title: busy ? "CREANDO CUENTA…" : "CONTINUAR", icon: "arrow.right", isLoading: busy) {
          advance()
        }.disabled(!canContinue || busy).opacity(canContinue ? 1 : 0.35).padding(.horizontal, 22).padding(.bottom, 14)
      }
    }
  }
  private var stepTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
      removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity))
  }
  @ViewBuilder private var currentStep: some View {
    switch step {
    case 0: question("¿Cómo te llamas?", "Así te conocerán en Nook.") { MinimalOnboardingField(placeholder: "Tu nombre", text: $name) }
    case 1: question("¿Cuándo naciste?", "Nook es solo para mayores de 18 años.") {
      DatePicker("Fecha de nacimiento", selection: $birth, in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!, displayedComponents: .date)
        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
    }
    case 2: question("¿Cómo te identificas?", "Elige la opción que mejor te represente.") { options(Gender.allCases.map { ($0.rawValue, $0.title) }, selected: gender.rawValue) { gender = Gender(rawValue: $0)! } }
    case 3: question("¿Para qué te apetece quedar?", "Esto aparecerá en tu perfil. Elige lo que mejor encaje contigo ahora.") { options(LookingFor.registrationChoices.map { ($0.rawValue, $0.title) }, selected: looking.rawValue) { looking = LookingFor(rawValue: $0)! } }
    case 4: question("¿Cuál es tu email?", "Solo lo usaremos para proteger tu cuenta.") { MinimalOnboardingField(placeholder: "nombre@email.com", text: $email, keyboard: .emailAddress) }
    default: question("Crea una contraseña", "Mínimo 8 caracteres.") {
      MinimalOnboardingField(placeholder: "Contraseña", text: $password, secure: true)
      if let error { Text(error).foregroundStyle(.red).font(.callout.weight(.semibold)) }
    }
    }
  }
  private func question<C: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Spacer(minLength: 82)
        Text(title).font(NookTypography.display(43)).tracking(-0.7)
        Text(subtitle).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(NookColors.espresso.opacity(0.58))
        content()
        Spacer(minLength: 40)
      }.padding(.horizontal, 24)
    }.scrollDismissesKeyboard(.interactively)
  }
  private func options(_ values: [(String, String)], selected: String, action: @escaping (String) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(values, id: \.0) { item in
        MinimalChoiceRow(title: item.1, selected: selected == item.0) { action(item.0) }
      }
    }
  }
  private var canContinue: Bool {
    switch step { case 0: !name.trimmingCharacters(in: .whitespaces).isEmpty; case 4: email.contains("@"); case 5: password.count >= 8; default: true }
  }
  private func advance() {
    guard canContinue else { return }
    if step < 5 { direction = 1; withAnimation(NookMotion.spring) { step += 1 }; return }
    busy = true
    Task {
      do { try await app.register(email: email, password: password) }
      catch { self.error = error.localizedDescription; busy = false }
    }
  }
  private func back() {
    if step == 0 { app.stage = .welcome } else { direction = -1; withAnimation(NookMotion.spring) { step -= 1 } }
  }
}

private struct MinimalOnboardingField: View {
  let placeholder: String
  @Binding var text: String
  var secure = false
  var keyboard: UIKeyboardType = .default
  @FocusState private var focused: Bool
  var body: some View {
    Group {
      if secure { SecureField(placeholder, text: $text) }
      else { TextField(placeholder, text: $text).keyboardType(keyboard) }
    }
    .font(.system(size: 24, weight: .medium, design: .rounded))
    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
    .autocorrectionDisabled(keyboard == .emailAddress)
    .focused($focused).padding(.vertical, 14)
    .overlay(alignment: .bottom) {
      Rectangle().fill(focused ? NookColors.espresso : NookColors.espresso.opacity(0.2))
        .frame(height: focused ? 2 : 1).animation(NookMotion.fast, value: focused)
    }
  }
}

private struct MinimalChoiceRow: View {
  let title: String
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button {
      Haptics.selection()
      withAnimation(NookMotion.fast) { action() }
    } label: {
      HStack(spacing: 14) {
        Text(title).font(.system(size: 18, weight: selected ? .semibold : .medium, design: .rounded))
        Spacer()
        Image(systemName: selected ? "checkmark" : "circle")
          .font(.system(size: 15, weight: .semibold)).opacity(selected ? 1 : 0.22)
      }.foregroundStyle(NookColors.espresso).frame(minHeight: 54)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
    Divider().overlay(NookColors.espresso.opacity(0.1))
  }
}

struct OnboardingView: View {
  @EnvironmentObject var app: AppSession
  @State private var page = 0
  @State private var direction = 1
  @State private var name = ""
  @State private var birth = Calendar.current.date(byAdding: .year, value: -25, to: Date())!
  @State private var gender = Gender.woman
  @State private var looking = LookingFor.casualCoffee
  @State private var photoItem: PhotosPickerItem?
  @State private var photoData: Data?
  @State private var uploadingPhoto = false
  @State private var finishing = false
  @State private var bio = ""
  @State private var city = ""
  @State private var coffee = "MILK_COFFEE"
  @State private var vibe = "CALM"
  @State private var coffeesPerDay = 2
  @State private var moment = "MORNING"
  @State private var plan = "LONG_TALKS"
  @State private var minAge = 22.0
  @State private var maxAge = 38.0
  @State private var distance = 25.0
  @State private var error: String?
  private let coffeeOptions = [
    ("BLACK", "☕ Solo"), ("CORTADO", "🥛 Cortado"), ("MILK_COFFEE", "☕🥛 Café con leche"),
    ("ICED_COFFEE", "🧊 Café frío"), ("MATCHA", "🍵 Matcha"), ("TEA", "🫖 Té"),
  ]
  private let total = 15
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Button { back() } label: { Image(systemName: "chevron.left").frame(width: 42, height: 42) }
        NookProgressBar(step: page, total: total)
      }.padding(.horizontal, 18).padding(.top, 8)
      ZStack { currentQuestion.id(page).transition(stepTransition) }.animation(NookMotion.spring, value: page)
      NookButton(
        title: finishing ? "GUARDANDO PERFIL…" : (page == 14 ? "ENTRAR EN NOOK ☕" : "CONTINUAR"),
        icon: "arrow.right", isLoading: uploadingPhoto || finishing
      ) {
        if page < 14 {
          if page == 4, let photoData {
            uploadingPhoto = true
            Task {
              do {
                let mimeType = photoItem?.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                _ = try await app.repository.uploadPhoto(data: photoData, mimeType: mimeType)
              } catch {
                self.error = "No hemos podido subir la foto. Comprueba tu conexión e inténtalo otra vez."
                uploadingPhoto = false
                return
              }
              do { try await persistAndAdvance() }
              catch { self.error = error.localizedDescription }
              uploadingPhoto = false
            }
          } else {
            Task {
              do { try await persistAndAdvance() }
              catch { self.error = error.localizedDescription }
            }
          }
        } else {
          guard !finishing else { return }
          finishing = true
          Task {
            let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
            let placemarks = try? await CLGeocoder().geocodeAddressString(trimmedCity)
            let approximateLocation = placemarks?.first?.location
            do { try await app.finish(
              ProfileUpdate(
                bio: bio, city: trimmedCity, latitude: approximateLocation?.coordinate.latitude,
                longitude: approximateLocation?.coordinate.longitude, coffeePersonality: coffeeTitle, preferredPlan: plan,
                preferredVibe: vibe, coffeesPerDay: coffeesPerDay, favoriteCoffeeMoment: moment,
                minAge: Int(minAge), maxAge: Int(maxAge), maxDistanceKm: Int(distance),
                coffeePreferences: [coffee], onboardingComplete: true, onboardingStep: total))
            } catch {
              self.error = "No hemos podido terminar tu perfil. Inténtalo de nuevo."
              finishing = false
            }
          }
        }
      }.disabled(!canAdvance || uploadingPhoto || finishing)
        .opacity(canAdvance ? 1 : 0.35)
        .padding(.horizontal, 22).padding(.bottom, 14)
    }.alert("Algo se ha enfriado", isPresented: Binding(
      get: { error != nil }, set: { if !$0 { error = nil } }
    )) { Button("Entendido") { error = nil } } message: { Text(error ?? "") }
      .onChange(of: bio) { _, value in if value.count > 500 { bio = String(value.prefix(500)) } }
      .onAppear { restoreProgress() }
  }
  private var stepTransition: AnyTransition {
    .asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity), removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity))
  }
  @ViewBuilder private var currentQuestion: some View {
    switch page {
    case 0: question("¿Cómo te llamas?", "Así te conocerán en Nook.") {
      MinimalOnboardingField(placeholder: "Tu nombre", text: $name)
    }
    case 1: question("¿Cuándo naciste?", "Nook es solo para mayores de 18 años.") {
      DatePicker(
        "Fecha de nacimiento", selection: $birth,
        in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!, displayedComponents: .date
      ).datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
    }
    case 2: question("¿Cómo te identificas?", "Elige la opción que mejor te represente.") {
      optionList(Gender.allCases.map { ($0.rawValue, $0.title) }, selected: gender.rawValue) {
        gender = Gender(rawValue: $0) ?? .woman
      }
    }
    case 3: question("¿Qué buscas en Nook?", "Elige lo que mejor encaja contigo ahora.") {
      optionList(LookingFor.registrationChoices.map { ($0.rawValue, $0.title) }, selected: looking.rawValue) {
        looking = LookingFor(rawValue: $0) ?? .casualCoffee
      }
    }
    case 4: question("Añade una foto", "Una foto clara ayuda a empezar con confianza.") {
      VStack(spacing: 18) {
        Group {
          if let photoData, let image = UIImage(data: photoData) { Image(uiImage: image).resizable().scaledToFill() }
          else { ZStack { Circle().fill(NookColors.oat.opacity(0.35)); Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 54)).foregroundStyle(NookColors.mocha) } }
        }.frame(width: 190, height: 190).clipShape(Circle()).frame(maxWidth: .infinity)
        PhotosPicker(selection: $photoItem, matching: .images) { Text(photoData == nil ? "ELEGIR FOTO" : "CAMBIAR FOTO").font(.headline).foregroundStyle(NookColors.espresso).padding(.horizontal, 24).frame(height: 54).background(NookColors.offWhite, in: Capsule()) }
      }.onChange(of: photoItem) { _, item in Task { photoData = try? await item?.loadTransferable(type: Data.self) } }
    }
    case 5: question("Cuéntanos algo sobre ti", "Dos líneas bastan para empezar.") {
      TextEditor(text: $bio).font(.title3.weight(.medium)).scrollContentBackground(.hidden).frame(height: 140)
        .overlay(alignment: .topLeading) { if bio.isEmpty { Text("Arquitectura · conciertos · cafeterías pequeñas").foregroundStyle(NookColors.espresso.opacity(0.32)).padding(.top, 8).allowsHitTesting(false) } }
        .overlay(alignment: .bottom) { Rectangle().fill(NookColors.espresso.opacity(0.18)).frame(height: 1) }
    }
    case 6: question("Necesitamos saber\nde dónde eres", "Con tu ciudad o pueblo es suficiente. No necesitamos ni mostraremos tu ubicación exacta.") {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 13) {
          Image(systemName: "location.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(NookColors.mocha)
          TextField("Ciudad o pueblo", text: $city)
            .font(.system(size: 22, weight: .semibold, design: .rounded)).textContentType(.addressCity)
            .textInputAutocapitalization(.words).submitLabel(.continue)
        }.padding(.vertical, 15).overlay(alignment: .bottom) { Rectangle().fill(NookColors.espresso.opacity(0.2)).frame(height: 1) }
        Label("Solo utilizaremos una zona aproximada para encontrar personas y calcular puntos medios.", systemImage: "lock.fill")
          .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(NookColors.espresso.opacity(0.5)).lineSpacing(3)
      }
    }
    case 7: question("¿Cómo te gusta el café?", "Elige tu taza habitual.") { optionList(coffeeOptions, selected: coffee) { coffee = $0 } }
    case 8: question("¿Qué ambiente prefieres?", "El lugar también forma parte del encuentro.") { optionList([("CALM", "😌 Tranquila"), ("SOCIAL", "🙂 Con ambiente"), ("LIVELY", "🎵 Animada")], selected: vibe) { vibe = $0 } }
    case 9: question("¿Cuántos cafés tomas al día?", "Prometemos no juzgar.") { cupsPicker }
    case 10: question("¿Tu momento favorito?", "¿Cuándo sabe mejor un café?") { optionList([("MORNING", "🌅 Mañana"), ("MIDDAY", "☀️ Mediodía"), ("AFTERWORK", "🌆 Afterwork"), ("EVENING", "🌙 Tarde / noche")], selected: moment) { moment = $0 } }
    case 11: question("¿Qué plan prefieres?", "Tú marcas el ritmo.") { optionList([("QUICK", "⚡ Café rápido"), ("LONG_TALKS", "💬 Hablar sin prisas"), ("WALK", "🚶 Café y paseo"), ("IMPROVISE", "✨ Improvisar")], selected: plan) { plan = $0 } }
    case 12: question("¿Hasta dónde nos movemos?", "Puedes cambiarlo cuando quieras.") { slider(value: $distance, title: "Hasta \(Int(distance)) km", range: 1...100) }
    case 13: question("¿Qué edades buscas?", "Solo mostramos personas adultas.") {
      VStack(alignment: .leading, spacing: 24) { Text("\(Int(minAge)) — \(Int(maxAge)) años").font(.title.bold()); Slider(value: $minAge, in: 18...60, step: 1); Slider(value: $maxAge, in: minAge...80, step: 1) }.tint(NookColors.espresso)
    }
    default: question("Todo listo", "Tu próxima conversación puede empezar con una taza.") { NookCoffeeLogo(size: 120).frame(maxWidth: .infinity).padding(.top, 20) }
    }
  }
  private func question<C: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Spacer(minLength: 66)
        Text(title).font(NookTypography.display(43)).tracking(-0.7)
        Text(subtitle).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(NookColors.espresso.opacity(0.58))
        content()
        Spacer(minLength: 40)
      }.padding(NookSpacing.lg)
    }.scrollDismissesKeyboard(.interactively)
  }
  private func optionList(_ values: [(String, String)], selected: String, action: @escaping (String) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 0) { ForEach(values, id: \.0) { item in MinimalChoiceRow(title: item.1, selected: selected == item.0) { action(item.0) } } }
  }
  private var cupsPicker: some View {
    HStack(spacing: 10) {
      ForEach(0...4, id: \.self) { count in
        Button {
          Haptics.selection(); withAnimation(NookMotion.playful) { coffeesPerDay = count }
        } label: {
          VStack(spacing: 9) {
            Text(count == 0 ? "0" : String(repeating: "☕", count: count)).font(.system(size: count > 2 ? 17 : 23)).minimumScaleFactor(0.6)
            Text(count == 4 ? "4+" : "\(count)").font(.caption.bold())
          }.frame(maxWidth: .infinity).frame(height: 66).foregroundStyle(coffeesPerDay == count ? NookColors.inverseText : NookColors.espresso).background(coffeesPerDay == count ? NookColors.espresso : .clear, in: Circle()).scaleEffect(coffeesPerDay == count ? 1.04 : 1)
        }.buttonStyle(.plain)
      }
    }
  }
  private func slider(value: Binding<Double>, title: String, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: 22) { Text(title).font(.title.bold()); Slider(value: value, in: range, step: 1).tint(NookColors.espresso) }
  }
  private var coffeeTitle: String { coffeeOptions.first(where: { $0.0 == coffee })?.1 ?? "Coffee person ☕" }
  private var canAdvance: Bool {
    if page == 0 { return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if page == 4 { return photoData != nil || !(app.me?.photos.isEmpty ?? true) }
    if page == 6 { return city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
    return true
  }
  @MainActor private func persistAndAdvance() async throws {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
    let next = page + 1
    let update: ProfileUpdate
    switch page {
    case 0: update = ProfileUpdate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), onboardingStep: next)
    case 1: update = ProfileUpdate(birthDate: formatter.string(from: birth), onboardingStep: next)
    case 2: update = ProfileUpdate(gender: gender, onboardingStep: next)
    case 3: update = ProfileUpdate(lookingFor: looking, onboardingStep: next)
    case 5: update = ProfileUpdate(bio: bio, onboardingStep: next)
    case 6: update = ProfileUpdate(city: city.trimmingCharacters(in: .whitespacesAndNewlines), onboardingStep: next)
    case 7: update = ProfileUpdate(coffeePersonality: coffeeTitle, coffeePreferences: [coffee], onboardingStep: next)
    case 8: update = ProfileUpdate(preferredVibe: vibe, onboardingStep: next)
    case 9: update = ProfileUpdate(coffeesPerDay: coffeesPerDay, onboardingStep: next)
    case 10: update = ProfileUpdate(favoriteCoffeeMoment: moment, onboardingStep: next)
    case 11: update = ProfileUpdate(preferredPlan: plan, onboardingStep: next)
    case 12: update = ProfileUpdate(maxDistanceKm: Int(distance), onboardingStep: next)
    case 13: update = ProfileUpdate(minAge: Int(minAge), maxAge: Int(maxAge), onboardingStep: next)
    default: update = ProfileUpdate(onboardingStep: next)
    }
    try await app.saveOnboarding(update)
    direction = 1
    withAnimation(NookMotion.spring) { page = next }
  }
  private func restoreProgress() {
    guard let me = app.me else { return }
    name = me.name == "Nuevo café" ? "" : me.name
    if let value = me.birthDate {
      let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
      birth = formatter.date(from: value) ?? birth
    }
    gender = me.gender ?? gender; looking = me.lookingFor ?? looking
    bio = me.bio; city = me.city ?? ""; vibe = me.preferredVibe ?? vibe
    coffeesPerDay = me.coffeesPerDay ?? coffeesPerDay; moment = me.favoriteCoffeeMoment ?? moment
    plan = me.preferredPlan ?? plan; distance = Double(me.maxDistanceKm)
    minAge = Double(me.minAge); maxAge = Double(me.maxAge)
    coffee = me.coffeePreferences.first ?? coffee
    page = min(max(me.onboardingStep ?? 0, 0), total - 1)
  }
  private func back() { guard page > 0 else { return }; direction = -1; withAnimation(NookMotion.spring) { page -= 1 } }
}

struct MainTabView: View {
  @EnvironmentObject var app: AppSession
  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch app.selectedTab {
        case 0: NavigationStack { DiscoverView() }
        case 1:
          NavigationStack {
            if app.selectedCoffeeMatch != nil { CoffeeShopsView().id(app.placesReloadID) }
            else { ChatsView() }
          }
        default: NavigationStack { ConversationsView() }
        }
      }
      .id(app.selectedTab)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .transition(.opacity)
      if !app.tabBarHidden {
        NookFloatingTabBar(selection: $app.selectedTab)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(NookMotion.fast, value: app.tabBarHidden)
    .background {
      if app.selectedTab == 0 { NookColors.warmBlack.ignoresSafeArea() }
      else { NookBackground() }
    }
  }
}

struct FloatingTabBar: View {
  @EnvironmentObject var app: AppSession
  @Binding var selection: Int
  @State private var coffeeNotifications = 0
  @State private var chatNotifications = 0
  let items = [
    ("cup.and.saucer", "Descubrir"),
    ("cup.and.saucer.fill", "Mis cafés"),
    ("bubble.left.and.bubble.right.fill", "Chats"),
  ]
  var body: some View {
    HStack(spacing: 0) {
      ForEach(items.indices, id: \.self) { i in
        Button {
          Haptics.selection()
          if i == 1 {
            app.selectedCoffeeMatch = nil
          }
          selection = i
        } label: {
          VStack(spacing: 5) {
            ZStack {
              Image(systemName: items[i].0)
                .font(.system(size: 22, weight: selection == i ? .medium : .light))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selection == i ? NookColors.espresso : NookColors.espresso.opacity(0.48))
                .scaleEffect(selection == i ? 1.1 : 1)
                .symbolEffect(.bounce, value: selection == i)
            if i == 1 && coffeeNotifications > 0 {
              Text(coffeeNotifications > 9 ? "9+" : "\(coffeeNotifications)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(NookColors.inverseText)
                .frame(minWidth: 18, minHeight: 18).background(NookColors.mocha, in: Circle())
                .overlay(Circle().stroke(NookColors.cream, lineWidth: 2))
                .offset(x: 14, y: -12)
                .accessibilityLabel("\(coffeeNotifications) acciones de café pendientes")
            }
            if i == 2 && chatNotifications > 0 {
              Text(chatNotifications > 99 ? "99+" : "\(chatNotifications)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).padding(.horizontal, chatNotifications > 9 ? 5 : 0)
                .frame(minWidth: 18, minHeight: 18).background(NookColors.mocha, in: Capsule())
                .overlay(Capsule().stroke(NookColors.cream, lineWidth: 2))
                .offset(x: 15, y: -12)
                .accessibilityLabel("\(chatNotifications) mensajes sin leer")
            }
            }
            Circle().fill(NookColors.mocha).frame(width: 4, height: 4)
              .opacity(selection == i ? 1 : 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(items[i].1)
          .accessibilityAddTraits(selection == i ? .isSelected : [])
      }
    }
    .padding(.horizontal, 18).padding(.top, 7)
    .frame(maxWidth: .infinity).frame(height: 60, alignment: .center)
    .background {
      NookColors.warmBlack.ignoresSafeArea(edges: .bottom)
    }
    .animation(NookMotion.fast, value: selection)
    .task(id: "\(selection)-\(app.coffeeDataRevision)-\(app.matchDataRevision)") {
      await refreshNotifications()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { break }
        await refreshNotifications()
      }
    }
  }
  @MainActor private func refreshNotifications() async {
    guard app.me != nil else {
      coffeeNotifications = 0; chatNotifications = 0; return
    }
    async let notificationRequest = try? app.repository.notifications()
    async let dateRequest = try? app.repository.dates()
    let notifications = await notificationRequest ?? []
    let dates = await dateRequest ?? []
    let unread = notifications.filter { !$0.read }
    let unreadCoffee = unread.filter { ["COFFEE_ACCEPTED", "COFFEE_PROPOSAL", "COFFEE_COUNTER_PROPOSAL", "COFFEE_CANCELLED"].contains($0.type) }
    let unreadChats = unread.filter { $0.type == "MESSAGE" }
    let counts = NavigationBadgeCounts.calculate(
      notifications: notifications, dates: dates, currentUserID: app.me!.id)
    withAnimation(NookMotion.fast) {
      coffeeNotifications = counts.coffees
      chatNotifications = counts.chats
    }
    if selection == 1 && !unreadCoffee.isEmpty {
      for notification in unreadCoffee {
        try? await app.repository.markNotificationRead(notification.id)
      }
      await refreshDatesOnly()
    } else if selection == 2 && !unreadChats.isEmpty {
      for notification in unreadChats { try? await app.repository.markNotificationRead(notification.id) }
      withAnimation(NookMotion.fast) { chatNotifications = 0 }
    }
  }
  @MainActor private func refreshDatesOnly() async {
    guard let dates = try? await app.repository.dates() else { return }
    withAnimation(NookMotion.fast) {
      coffeeNotifications = dates.filter {
        ($0.status == .pending || $0.status == .counterProposed) && $0.receiverId == app.me?.id
      }.count
    }
  }
}

typealias NookFloatingTabBar = FloatingTabBar
