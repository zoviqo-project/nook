import PhotosUI
import SwiftUI
import UserNotifications

@MainActor final class DiscoverVM: ObservableObject {
  @Published var people: [DiscoverProfile] = []
  @Published var match: Match?
  @Published var loading = true
  @Published var error: String?
  @Published private(set) var actingOn: UUID?
  func seed(_ snapshot: DiscoverSnapshot) {
    guard people.isEmpty else { return }
    people = snapshot.people
    loading = false
  }
  func load(_ repo: any NookRepository, showLoader: Bool = true) async {
    let startedAt = Date()
    if showLoader { loading = true }
    error = nil
    defer { loading = false }
    do {
      people = try await repo.discover()
    } catch { self.error = error.localizedDescription }
    #if DEBUG
      print("[PERF] Discover API + decode: \(Int(Date().timeIntervalSince(startedAt) * 1_000))ms")
    #endif
  }
  func pass(_ person: DiscoverProfile, repo: any NookRepository) async {
    guard actingOn == nil else { return }
    actingOn = person.id
    defer { actingOn = nil }
    do {
      try await repo.pass(person.id)
      withAnimation(NookMotion.spring) { people.removeAll { $0.id == person.id } }
      Haptics.selection()
      if people.isEmpty { await load(repo) }
    } catch { self.error = error.localizedDescription }
  }
  func coffee(_ person: DiscoverProfile, repo: any NookRepository) async {
    guard actingOn == nil else { return }
    actingOn = person.id
    defer { actingOn = nil }
    Haptics.coffee()
    NookSoundManager.shared.play(.coffeeLike)
    do {
      let result = try await repo.like(person.id)
      withAnimation(NookMotion.playful) {
        people.removeAll { $0.id == person.id }
        match = result.match
      }
      if result.matched { Haptics.success() }
      if people.isEmpty { await load(repo) }
    } catch { self.error = error.localizedDescription }
  }
}

struct DiscoverView: View {
  @EnvironmentObject var app: AppSession
  @StateObject private var vm = DiscoverVM()
  @State private var drag: CGSize = .zero
  @State private var liking = false
  @State private var entrance = false
  @State private var showFilters = false
  @State private var selectedProfile: DiscoverProfile?
  @AppStorage("didSeeDiscoverySwipeHint") private var didSeeSwipeHint = false
  @State private var showSwipeHint = false
  @State private var swipeHintPulse = false
  var body: some View {
    NookScreenContainer(
      eyebrow: "NOOK", title: "Un café con…", solidBackground: NookColors.warmBlack,
      brandedHeader: true,
      actionIcon: "slider.horizontal.3",
      actionLabel: "Filtros", action: { showFilters = true }
    ) {
      Group {
          if vm.loading && vm.people.isEmpty {
            NookSkeletonScreen(layout: .profileCard)
          } else if let person = vm.people.first {
            cardStack(person)
          } else if let error = vm.error {
            NookErrorView(message: error) { Task { await vm.load(app.repository) } }
          } else {
            empty
          }
      }.frame(maxHeight: .infinity).padding(.top, 4)
    }
    .task {
      if let cache = app.discoverCache { vm.seed(cache) }
      await vm.load(app.repository, showLoader: app.discoverCache == nil)
      app.cacheDiscover(vm.people)
      NookImagePrefetch.schedule(vm.people.prefix(3).flatMap { $0.photos.map(\.url) })
      entrance = true
      if !didSeeSwipeHint {
        showSwipeHint = true
        withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
          swipeHintPulse = true
        }
      }
    }.onChange(of: app.discoveryRevision) { _, _ in
      Task {
        await vm.load(app.repository, showLoader: false)
        app.cacheDiscover(vm.people)
        NookImagePrefetch.schedule(vm.people.prefix(3).flatMap { $0.photos.map(\.url) })
      }
    }.sheet(item: $vm.match) { MatchCelebration(match: $0) }
      .sheet(isPresented: $showFilters) { DiscoveryFiltersView() }
      .fullScreenCover(item: $selectedProfile) { PersonProfileView(person: $0) }
      .onChange(of: vm.people) { _, people in
        app.cacheDiscover(people)
        NookImagePrefetch.schedule(people.prefix(3).flatMap { $0.photos.map(\.url) })
      }
  }
  private func cardStack(_ person: DiscoverProfile) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        if vm.people.count > 1 {
          NookProfileCard(person: vm.people[1], viewer: app.me, height: proxy.size.height - 10)
            .scaleEffect(0.975).offset(y: 8).opacity(0.5)
        }
        NookProfileCard(person: person, viewer: app.me, height: proxy.size.height - 10)
          .offset(drag).rotationEffect(.degrees(Double(drag.width / 28)))
          .overlay { swipeHint }.gesture(
          DragGesture().onChanged {
            dismissSwipeHint()
            drag = $0.translation
          }.onEnded { value in
            if value.translation.width < -110 {
              withAnimation(NookMotion.spring) { drag = CGSize(width: -600, height: 30) }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                Task { await vm.pass(person, repo: app.repository); drag = .zero }
              }
            } else if value.translation.width > 110 {
              withAnimation(NookMotion.spring) { drag = CGSize(width: 600, height: -20) }
              liking = true
              Task {
                await vm.coffee(person, repo: app.repository)
                drag = .zero
                liking = false
              }
            } else {
              withAnimation(NookMotion.spring) { drag = .zero }
            }
          }
          ).allowsHitTesting(vm.actingOn == nil)
          .scaleEffect(entrance ? 1 : 0.96).offset(y: entrance ? 0 : 28).animation(
            NookMotion.spring, value: person.id)
        actions(person).padding(.bottom, 22).offset(drag)
          .allowsHitTesting(vm.actingOn == nil)
      }
    }.padding(.horizontal, 10)
  }
  @ViewBuilder private var swipeHint: some View {
    if showSwipeHint {
      HStack {
        hintChevrons(direction: "left")
        Spacer()
        hintChevrons(direction: "right")
      }
      .padding(.horizontal, 18)
      .opacity(swipeHintPulse ? 1 : 0.35)
      .transition(.opacity)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Desliza la tarjeta a izquierda o derecha")
    }
  }
  private func hintChevrons(direction: String) -> some View {
    HStack(spacing: -2) {
      ForEach(0..<2, id: \.self) { _ in
        Image(systemName: "chevron.\(direction)")
      }
    }
    .font(.system(size: 22, weight: .semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 12).frame(height: 44)
    .background(.black.opacity(0.28), in: Capsule())
  }
  private func dismissSwipeHint() {
    guard showSwipeHint else { return }
    didSeeSwipeHint = true
    withAnimation(NookMotion.fast) { showSwipeHint = false }
  }
  private func actions(_ person: DiscoverProfile) -> some View {
    HStack(spacing: 30) {
      ZStack {
        CircleAction(icon: "xmark", size: 54) {
          withAnimation(NookMotion.spring) { drag = CGSize(width: -600, height: 10) }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Task { await vm.pass(person, repo: app.repository); drag = .zero }
          }
        }
        if vm.actingOn == person.id && !liking {
          Circle().fill(NookColors.offWhite).frame(width: 54, height: 54)
          ProgressView().tint(NookColors.espresso)
        }
      }
      Button {
        liking = true
        Task {
          await vm.coffee(person, repo: app.repository)
          liking = false
        }
      } label: {
        ZStack {
          Circle().fill(NookColors.espresso).frame(width: 76, height: 76).shadow(
            color: NookColors.espresso.opacity(0.3), radius: 20, y: 10)
          if vm.actingOn == person.id && !liking {
            ProgressView().tint(NookColors.offWhite)
          } else {
            Image(systemName: liking ? "cup.and.saucer.fill" : "cup.and.saucer").font(
              .system(size: 31, weight: .bold)
            ).foregroundStyle(NookColors.offWhite).rotationEffect(.degrees(liking ? -10 : 0))
          }
          SteamView(active: liking).offset(y: -47)
        }.scaleEffect(liking ? 1.16 : 1).animation(NookMotion.playful, value: liking)
      }.buttonStyle(.plain).disabled(vm.actingOn != nil)
      CircleAction(icon: "info", size: 54) { selectedProfile = person }
    }.frame(maxWidth: .infinity)
  }
  private var empty: some View {
    VStack(spacing: 18) {
      CoffeeLogo(size: 78)
      Text("Tazas en pausa").font(.title.bold())
      Text("Vuelve pronto para descubrir personas nuevas.").foregroundStyle(NookColors.warmGray)
        .multilineTextAlignment(.center)
      NookButton(title: "VOLVER A CARGAR", icon: "arrow.clockwise", secondary: true) {
        Task { await vm.load(app.repository) }
      }
    }.padding(32)
  }
}

struct NookProfileCard: View {
  let person: DiscoverProfile
  var viewer: Me? = nil
  var height: CGFloat? = nil
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        ProfileImage(url: person.photos.first?.url, name: person.name).frame(
          width: proxy.size.width, height: proxy.size.height)
        NookColors.warmBlack.opacity(0.38)
        VStack(alignment: .leading, spacing: 8) {
          Text("\(person.name), \(person.age)").font(
            .system(size: 34, weight: .black, design: .rounded))
          Label("\(person.distanceKm.formatted()) km", systemImage: "location.fill").font(
            .subheadline.bold())
          Text(person.coffeePersonality ?? "Un café y buena conversación")
            .font(.subheadline.bold())
          Text(person.bio).font(.system(size: 16, weight: .medium, design: .rounded)).lineLimit(2)
            .lineSpacing(3)
        }.foregroundStyle(.white).padding(.horizontal, 22).padding(.bottom, 116)
      }.clipShape(RoundedRectangle(cornerRadius: NookRadius.hero, style: .continuous))
    }.frame(maxWidth: .infinity).frame(height: height ?? (verticalSizeClass == .compact ? 330 : 460))
  }
}

struct ProfileImage: View {
  let url: String?
  let name: String
  var contentMode: ContentMode = .fill
  var alignment: Alignment = .center
  var body: some View {
    NookRemoteImage(
      url: resolvedURL, contentMode: contentMode, alignment: alignment, faceAware: true
    ) {
      ZStack {
          NookColors.latte
          Text(String(name.prefix(1))).font(.system(size: 130, weight: .black, design: .rounded))
            .foregroundStyle(NookColors.offWhite.opacity(0.8))
      }
    }.clipped()
  }
  private var resolvedURL: URL? {
    guard let url, !url.isEmpty else { return nil }
    if url.hasPrefix("/") {
      guard var components = URLComponents(url: AppConfiguration.apiURL, resolvingAgainstBaseURL: false) else { return nil }
      components.path = url
      components.query = nil
      return components.url
    }
    return URL(string: url)
  }
}

struct CircleAction: View {
  let icon: String
  let size: CGFloat
  let action: () -> Void
  var body: some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      Image(systemName: icon).font(.system(size: 21, weight: .bold)).foregroundStyle(
        NookColors.espresso
      ).frame(width: size, height: size).background(NookColors.offWhite, in: Circle()).shadow(
        color: NookColors.espresso.opacity(0.15), radius: 16, y: 8)
    }.buttonStyle(.plain)
  }
}
struct SteamView: View {
  let active: Bool
  var body: some View {
    HStack(spacing: 7) {
      ForEach(0..<3) { i in
        Capsule().fill(NookColors.latte).frame(width: 3, height: 19).offset(y: active ? -12 : 6)
          .opacity(active ? 0 : 0.8).animation(
            .easeOut(duration: 0.8).repeatCount(2).delay(Double(i) * 0.12), value: active)
      }
    }
  }
}

struct MatchCelebration: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let match: Match
  @State private var meet = false
  @State private var cups = false
  @State private var coffeeBurst = false
  var body: some View {
    ZStack {
      NookBackground()
      MatchCoffeeBurst(active: coffeeBurst).ignoresSafeArea().allowsHitTesting(false)
      VStack(spacing: 20) {
        Spacer()
        ZStack {
          HStack(spacing: meet ? -20 : 100) {
            avatar(name: "Tú", photo: app.me?.photos.first?.url, fromLeft: true)
            avatar(name: match.person.name, photo: match.person.photos.first?.url, fromLeft: false)
          }.animation(NookMotion.playful.delay(0.15), value: meet)
          NookCoffeeLogo(size: 62, animated: false)
            .scaleEffect(cups ? 1 : 0.22)
            .rotationEffect(.degrees(cups ? 0 : -28))
            .opacity(cups ? 1 : 0)
            .shadow(color: NookColors.mocha.opacity(0.34), radius: cups ? 18 : 2, y: 7)
            .offset(y: 84)
            .animation(NookMotion.playful.delay(0.46), value: cups)
        }.frame(height: 230)
        VStack(spacing: 10) {
          Text("Tenemos café").font(NookTypography.display(41)).tracking(
            -1)
          Text("\(match.person.name) también se tomaría\nun café contigo.").font(.title3)
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
          Text("El siguiente paso es encontrar un sitio que os vaya bien.")
            .font(.subheadline).foregroundStyle(NookColors.espresso.opacity(0.55)).multilineTextAlignment(.center)
        }.opacity(meet ? 1 : 0).offset(y: meet ? 0 : 16)
        Spacer()
        VStack(spacing: 10) {
          matchAction("Proponer un lugar", icon: "mappin.and.ellipse", primary: true) {
            app.selectedCoffeeMatch = match.id; app.selectedTab = 1; dismiss()
          }
          matchAction("Dejarlo para otro momento", icon: "clock", primary: false) {
            Haptics.selection()
            dismiss()
          }
        }.frame(maxWidth: 286)
      }.padding(NookSpacing.lg)
    }.onAppear {
      withAnimation(NookMotion.playful) { meet = true }
      withAnimation(NookMotion.playful.delay(0.38)) { cups = true }
      withAnimation(.easeOut(duration: 1.15).delay(0.4)) { coffeeBurst = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { Haptics.success() }
      NookSoundManager.shared.play(.match)
    }
  }
  private func avatar(name: String, photo: String?, fromLeft: Bool) -> some View {
    ZStack {
      ProfileImage(url: photo, name: name).frame(width: 132, height: 132).clipShape(Circle())
        .overlay(Circle().stroke(NookColors.offWhite, lineWidth: 5))
        .shadow(color: NookColors.espresso.opacity(0.2), radius: 18, y: 9)
    }.offset(x: meet ? 0 : (fromLeft ? -240 : 240))
  }
  private func matchAction(_ title: String, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 17, weight: .medium))
        Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
      }.foregroundStyle(primary ? NookColors.inverseText : NookColors.espresso)
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(primary ? NookColors.espresso : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(NookColors.espresso.opacity(primary ? 0 : 0.22), lineWidth: 0.8) }
    }.buttonStyle(.plain)
  }
}

private struct MatchCoffeeBurst: View {
  let active: Bool
  private let positions: [CGSize] = [
    .init(width: -155, height: -270), .init(width: -78, height: -245),
    .init(width: 18, height: -282), .init(width: 108, height: -236),
    .init(width: 164, height: -128), .init(width: 172, height: 12),
    .init(width: 138, height: 146), .init(width: 54, height: 244),
    .init(width: -45, height: 258), .init(width: -136, height: 170),
    .init(width: -174, height: 38), .init(width: -164, height: -116),
  ]
  var body: some View {
    ZStack {
      Circle().stroke(NookColors.mocha.opacity(active ? 0 : 0.18), lineWidth: 12)
        .frame(width: active ? 620 : 70, height: active ? 620 : 70)
        .scaleEffect(active ? 1 : 0.2).opacity(active ? 0 : 1)
        .animation(.easeOut(duration: 1.05), value: active)
      ForEach(positions.indices, id: \.self) { index in
        MatchCoffeeBean()
          .frame(width: 16, height: 26)
          .rotationEffect(.degrees(Double(index * 41) + (active ? 170 : 0)))
          .offset(active ? positions[index] : .zero)
          .scaleEffect(active ? 0.72 : 0.12).opacity(active ? 0 : 0.95)
          .animation(.easeOut(duration: 1.08).delay(Double(index) * 0.018), value: active)
      }
      VStack(spacing: 0) {
        Capsule().fill(
          LinearGradient(colors: [NookColors.latte.opacity(0.15), NookColors.mocha], startPoint: .top, endPoint: .bottom)
        ).frame(width: 9, height: active ? 0 : 130)
        ZStack {
          ForEach(0..<3) { index in
            Circle().stroke(NookColors.cream.opacity(0.8 - Double(index) * 0.18), lineWidth: 4)
              .frame(width: CGFloat(34 + index * 28), height: CGFloat(34 + index * 28))
              .scaleEffect(active ? 1.8 : 0.25).opacity(active ? 0 : 1)
              .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.08), value: active)
          }
        }
      }.offset(y: -210)
      ForEach(0..<2) { index in
        Capsule().stroke(NookColors.latte.opacity(0.5), lineWidth: 3)
          .frame(width: 12, height: 44).offset(x: CGFloat(index * 2 - 1) * 18, y: active ? -260 : -110)
          .opacity(active ? 0 : 0.7)
          .animation(.easeOut(duration: 1).delay(0.25 + Double(index) * 0.08), value: active)
      }
    }
  }
}

private struct MatchCoffeeBean: View {
  var body: some View {
    ZStack {
      Capsule().fill(NookColors.mocha)
      Capsule().fill(NookColors.latte.opacity(0.65)).frame(width: 2, height: 15).rotationEffect(.degrees(12))
    }.shadow(color: NookColors.warmBlack.opacity(0.18), radius: 2, y: 1)
  }
}

struct PersonProfileView: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let person: DiscoverProfile
  @State private var photoIndex = 0
  @State private var moderationAction: ModerationAction?
  @State private var moderationError: String?
  var body: some View {
    ZStack(alignment: .topLeading) {
      NookBackground()
      ScrollView {
        VStack(spacing: 0) {
          ZStack(alignment: .bottomLeading) {
            TabView(selection: $photoIndex) {
              ForEach(Array(person.photos.prefix(8).enumerated()), id: \.element.id) { index, photo in
                ProfileImage(url: photo.url, name: person.name).tag(index)
              }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 520)
            LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.84)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
              HStack(spacing: 5) {
                ForEach(0..<max(1, min(person.photos.count, 8)), id: \.self) { index in
                  Capsule().fill(index == photoIndex ? .white : .white.opacity(0.38)).frame(height: 3)
                }
              }
              Text("\(person.name), \(person.age)").font(NookTypography.display(41))
              Text([person.city, "\(person.distanceKm.formatted()) km"].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline.bold()).foregroundStyle(.white.opacity(0.82))
            }.foregroundStyle(.white).padding(22)
          }
          VStack(alignment: .leading, spacing: 22) {
            MeetingIntentCard(intent: person.lookingFor, personName: person.name)
            profileSection("SOBRE MÍ") { Text(person.bio).font(.title3.weight(.medium)).lineSpacing(4) }
            profileSection("SU FORMA DE TOMAR CAFÉ") {
              VStack(alignment: .leading, spacing: 13) {
                Label(person.coffeePersonality ?? "El café que surja", systemImage: "cup.and.saucer.fill")
                if let vibe = person.preferredVibe { Label(vibeCopy(vibe), systemImage: "sparkles") }
                if let moment = person.favoriteCoffeeMoment { Label(momentCopy(moment), systemImage: "clock") }
              }.font(.body.weight(.semibold))
            }
            if !person.coffeePreferences.isEmpty {
              profileSection("AFINIDADES") {
                Text("También os apetece descubrir cafeterías y conversar sin convertir cada encuentro en una entrevista.")
                  .foregroundStyle(.secondary)
              }
            }
          }.padding(20).padding(.bottom, 30)
        }
      }.ignoresSafeArea(edges: .top)
      Button { dismiss() } label: {
        Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
          .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
      }.padding(.leading, 16).padding(.top, 8)
      Menu {
        Button("Reportar perfil", systemImage: "exclamationmark.bubble") { moderationAction = .report }
        Button("Bloquear a \(person.name)", systemImage: "hand.raised", role: .destructive) { moderationAction = .block }
      } label: {
        Image(systemName: "ellipsis").font(.headline).foregroundStyle(.white)
          .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
      }.padding(.trailing, 16).padding(.top, 8).frame(maxWidth: .infinity, alignment: .topTrailing)
    }
    .confirmationDialog(moderationAction == .block ? "¿Bloquear a \(person.name)?" : "¿Reportar este perfil?", isPresented: Binding(get: { moderationAction != nil }, set: { if !$0 { moderationAction = nil } }), titleVisibility: .visible) {
      if moderationAction == .block {
        Button("Bloquear", role: .destructive) { Task { await moderate(.block) } }
      } else {
        Button("Contenido o comportamiento inapropiado", role: .destructive) { Task { await moderate(.report) } }
      }
      Button("Cancelar", role: .cancel) { moderationAction = nil }
    }
    .alert("No hemos podido completar la acción", isPresented: Binding(get: { moderationError != nil }, set: { if !$0 { moderationError = nil } })) { Button("Entendido") { moderationError = nil } } message: { Text(moderationError ?? "") }
  }
  private enum ModerationAction { case block, report }
  private func moderate(_ action: ModerationAction) async {
    do {
      switch action {
      case .block: try await app.repository.block(person.id)
      case .report: try await app.repository.report(person.id, reason: "INAPPROPRIATE_BEHAVIOR", details: nil)
      }
      moderationAction = nil
      dismiss()
    } catch { moderationError = error.localizedDescription }
  }
  private func profileSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.caption.bold()).tracking(1.5).foregroundStyle(NookColors.mocha)
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
      .background(NookColors.offWhite.opacity(0.88), in: RoundedRectangle(cornerRadius: NookRadius.large))
  }
  private func vibeCopy(_ value: String) -> String { value == "CALM" ? "Sitios tranquilos" : value == "LIVELY" ? "Sitios animados" : "Con ambiente" }
  private func momentCopy(_ value: String) -> String { value == "MORNING" ? "Por la mañana" : value == "AFTERWORK" ? "Después del trabajo" : "Por la tarde" }
}

private struct MeetingIntentCard: View {
  let intent: LookingFor
  let personName: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(personName.map { "LO QUE BUSCA \($0.uppercased())" } ?? "LO QUE BUSCO")
          .font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
        Spacer()
        Image(systemName: intent.icon).font(.system(size: 15, weight: .semibold))
          .foregroundStyle(NookColors.mocha)
      }
      Text(intent.profileTitle).font(NookTypography.display(29)).tracking(-0.25)
      Text(intent.detail).font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(NookColors.espresso.opacity(0.64)).lineSpacing(3)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(21)
      .background(
        LinearGradient(colors: [NookColors.oat.opacity(0.38), NookColors.offWhite], startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: NookRadius.large))
      .overlay(RoundedRectangle(cornerRadius: NookRadius.large).stroke(NookColors.mocha.opacity(0.12)))
  }
}

struct DiscoveryFiltersView: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  @State private var minAge = 22.0
  @State private var maxAge = 40.0
  @State private var distance = 25.0
  @State private var vibes: Set<String> = []
  @State private var moments: Set<String> = []
  @State private var plans: Set<String> = []
  @State private var intentions: Set<String> = []
  @State private var saving = false
  @State private var error: String?
  private let columns = [GridItem(.flexible()), GridItem(.flexible())]
  var body: some View {
    NavigationStack {
      ZStack {
        NookRegalCoffeeBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
              Text("TU PRÓXIMO CAFÉ").font(NookTypography.caption).tracking(1.8)
                .foregroundStyle(NookColors.mocha)
              Text("¿A quién te apetece conocer?").font(NookTypography.display(34))
                .tracking(-0.5).fixedSize(horizontal: false, vertical: true)
              Text("Afina lo justo. Lo interesante también ocurre por sorpresa.")
                .font(.subheadline).foregroundStyle(NookColors.warmGray).lineSpacing(3)
            }.padding(.bottom, 4)

            filterBlock("CERCA DE TI", "\(Int(minAge))–\(Int(maxAge)) años · hasta \(Int(distance)) km", "location.fill") {
              VStack(spacing: 15) {
                rangeRow("Edad mínima", "\(Int(minAge))") { Slider(value: $minAge, in: 18...maxAge, step: 1) }
                rangeRow("Edad máxima", "\(Int(maxAge))") { Slider(value: $maxAge, in: minAge...80, step: 1) }
                rangeRow("Distancia", "\(Int(distance)) km") { Slider(value: $distance, in: 1...100, step: 1) }
              }.tint(NookColors.mocha)
            }

            filterBlock("LA INTENCIÓN", intentions.isEmpty ? "Cualquier buena conversación" : "\(intentions.count) preferencias", "sparkles") {
              LazyVGrid(columns: columns, spacing: 9) {
                option("Un café sin más", "cup.and.saucer", LookingFor.casualCoffee.rawValue, in: $intentions)
                option("Algo más", "heart", LookingFor.somethingMore.rawValue, in: $intentions)
                option("Nuevos amigos", "person.2", LookingFor.friendship.rawValue, in: $intentions)
                option("Ideas y proyectos", "lightbulb", LookingFor.project.rawValue, in: $intentions)
              }
            }

            filterBlock("EL AMBIENTE", vibes.isEmpty ? "Cualquier sitio con encanto" : vibeSummary, "music.note") {
              LazyVGrid(columns: columns, spacing: 9) {
                option("Tranquilo", "leaf", "CALM", in: $vibes)
                option("Con ambiente", "person.2", "SOCIAL", in: $vibes)
                option("Animado", "music.note", "LIVELY", in: $vibes)
              }
            }

            filterBlock("EL MOMENTO", moments.isEmpty ? "Cuando surja" : "Momentos favoritos", "clock") {
              LazyVGrid(columns: columns, spacing: 9) {
                option("Mañana", "sunrise", "MORNING", in: $moments)
                option("Mediodía", "sun.max", "MIDDAY", in: $moments)
                option("Afterwork", "briefcase", "AFTERWORK", in: $moments)
                option("Tarde", "sunset", "EVENING", in: $moments)
              }
            }

            filterBlock("EL PLAN", plans.isEmpty ? "Déjate sorprender" : "Planes compatibles", "figure.walk") {
              LazyVGrid(columns: columns, spacing: 9) {
                option("Café rápido", "bolt", "QUICK", in: $plans)
                option("Sin prisas", "text.bubble", "LONG_TALKS", in: $plans)
                option("Café y paseo", "figure.walk", "WALK", in: $plans)
                option("Improvisar", "shuffle", "IMPROVISE", in: $plans)
              }
            }

            Button {
              saving = true
              Task {
                do {
                  app.me = try await app.repository.updateProfile(ProfileUpdate(
                    minAge: Int(minAge), maxAge: Int(maxAge),
                    maxDistanceKm: Int(distance), discoveryIntentions: Array(intentions),
                    discoveryVibes: Array(vibes), discoveryMoments: Array(moments),
                    discoveryMeetingStyles: Array(plans)))
                  app.discoveryPreferencesPersisted()
                  NookSoundManager.shared.play(.coffeeLike)
                  dismiss()
                } catch { self.error = error.localizedDescription; saving = false }
              }
            } label: {
              HStack { Text(saving ? "Preparando…" : "Descubrir personas"); Spacer(); Image(systemName: "arrow.right") }
                .font(.headline).foregroundStyle(NookColors.inverseText)
                .padding(.horizontal, 20).frame(height: 56)
                .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }.buttonStyle(.plain).disabled(saving).opacity(saving ? 0.65 : 1)

            Button("Restablecer filtros") { reset() }
              .font(.subheadline.weight(.semibold)).foregroundStyle(NookColors.warmGray)
              .frame(maxWidth: .infinity).padding(.vertical, 8)
          }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 34)
        }
      }.toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark").font(.caption.bold()).frame(width: 36, height: 36).background(NookColors.offWhite.opacity(0.9), in: Circle()) }.foregroundStyle(NookColors.espresso).accessibilityLabel("Cerrar filtros") } }
        .onAppear {
          minAge = Double(app.me?.minAge ?? 22); maxAge = Double(app.me?.maxAge ?? 40)
          distance = Double(app.me?.maxDistanceKm ?? 25)
          vibes = Set(app.me?.discoveryVibes ?? [])
          moments = Set(app.me?.discoveryMoments ?? [])
          plans = Set(app.me?.discoveryMeetingStyles ?? [])
          intentions = Set(app.me?.discoveryIntentions ?? [])
        }
        .alert("No hemos podido guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
          Button("Entendido") { error = nil }
        } message: { Text(error ?? "") }
    }
  }
  private var vibeSummary: String {
    ["CALM": "Tranquilo", "SOCIAL": "Con ambiente", "LIVELY": "Animado"]
      .compactMap { vibes.contains($0.key) ? $0.value : nil }.joined(separator: " · ")
  }
  private func filterBlock<C: View>(_ title: String, _ value: String, _ icon: String, @ViewBuilder content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 11) {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(NookColors.mocha)
          .frame(width: 32, height: 32).background(NookColors.mocha.opacity(0.1), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.caption.bold()).tracking(1.25).foregroundStyle(NookColors.mocha)
          Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(NookColors.espresso)
        }
      }
      content()
    }.padding(18).background(NookColors.offWhite.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(NookColors.latte.opacity(0.16), lineWidth: 0.8))
  }
  private func rangeRow<C: View>(_ title: String, _ value: String, @ViewBuilder control: () -> C) -> some View {
    VStack(spacing: 5) {
      HStack { Text(title); Spacer(); Text(value).foregroundStyle(NookColors.mocha) }
        .font(.caption.weight(.semibold)).foregroundStyle(NookColors.warmGray)
      control()
    }
  }
  private func option(_ title: String, _ icon: String, _ value: String, in selection: Binding<Set<String>>) -> some View {
    let selected = selection.wrappedValue.contains(value)
    return Button {
      Haptics.selection()
      withAnimation(NookMotion.fast) {
        if selected { selection.wrappedValue.remove(value) } else { selection.wrappedValue.insert(value) }
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 17)
        Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 0)
      }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? NookColors.inverseText : NookColors.espresso)
        .background(selected ? NookColors.espresso : NookColors.cream.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.clear : NookColors.oat.opacity(0.18)))
    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func reset() {
    withAnimation(NookMotion.normal) {
      minAge = 18; maxAge = 55; distance = 30
      vibes.removeAll(); moments.removeAll(); plans.removeAll(); intentions.removeAll()
    }
  }
}

struct ProfileView: View {
  @EnvironmentObject var app: AppSession
  @AppStorage("coffeeSoundsEnabled") private var sounds = true
  @State private var bio = ""
  @State private var visible = true
  @State private var looking = LookingFor.casualCoffee
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var city = ""
  @State private var coffeePersonality = "Café con leche"
  @State private var preferredVibe = "SOCIAL"
  @State private var favoriteMoment = "AFTERWORK"
  @State private var preferredPlan = "IMPROVISE"
  @State private var uploading = false
  @State private var photoOperation: UUID?
  @State private var photoToDelete: Photo?
  @State private var saving = false
  @State private var saved = false
  @State private var profileError: String?
  var body: some View {
    NookScreenContainer(
      eyebrow: visible ? "PERFIL VISIBLE" : "PERFIL EN PAUSA",
      title: "Este eres tú"
    ) {
      ScrollView {
        VStack(spacing: 18) {
          ZStack(alignment: .bottomLeading) {
            ProfileImage(url: orderedPhotos.first?.url, name: app.me?.name ?? "N").frame(
              height: 405)
            LinearGradient(
              colors: [.clear, NookColors.warmBlack.opacity(0.82)], startPoint: .center,
              endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
              Text("\(app.me?.name ?? "Tu perfil"), \(app.me?.age ?? 18)").font(NookTypography.display(39))
              HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(app.me?.city ?? "Añade tu ciudad")
              }
              .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
            }.foregroundStyle(.white).padding(24)
            if orderedPhotos.isEmpty {
              PhotosPicker(selection: $photoItems, maxSelectionCount: 1, matching: .images) {
                Label(uploading ? "Subiendo…" : "Añadir foto principal", systemImage: "camera.fill")
                  .font(.system(size: 14, weight: .bold, design: .rounded))
                  .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 42)
                  .background(.black.opacity(0.54), in: Capsule())
              }.disabled(uploading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
          }.clipShape(RoundedRectangle(cornerRadius: 30)).padding(.horizontal, 14)

          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("TUS FOTOS").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
              Spacer()
              Text("\(app.me?.photos.count ?? 0) / 8").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
              HStack(spacing: 9) {
                ForEach(orderedPhotos) { photo in
                  ZStack(alignment: .topTrailing) {
                    ProfileImage(url: photo.url, name: app.me?.name ?? "N").frame(width: 86, height: 108)
                      .clipShape(RoundedRectangle(cornerRadius: 17))
                      .overlay(alignment: .bottomLeading) {
                        if photo.isPrimary == true {
                          Text("PRINCIPAL").font(.system(size: 8, weight: .heavy)).tracking(0.7)
                            .foregroundStyle(.white).padding(.horizontal, 7).frame(height: 22)
                            .background(.black.opacity(0.58), in: Capsule()).padding(6)
                        }
                      }
                    Menu {
                      if photo.isPrimary != true {
                        Button("Usar como principal", systemImage: "star.fill") {
                          Task { await makePrimary(photo.id) }
                        }
                      }
                      Button("Mover a la izquierda", systemImage: "arrow.left") {
                        Task { await move(photo.id, offset: -1) }
                      }.disabled(orderedPhotos.first?.id == photo.id)
                      Button("Mover a la derecha", systemImage: "arrow.right") {
                        Task { await move(photo.id, offset: 1) }
                      }.disabled(orderedPhotos.last?.id == photo.id)
                      Button("Eliminar foto", systemImage: "trash", role: .destructive) {
                        photoToDelete = photo
                      }
                    } label: {
                      Image(systemName: "ellipsis").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(.black.opacity(0.52), in: Circle()).padding(5)
                    }.disabled(uploading || photoOperation != nil)
                    if photoOperation == photo.id {
                      ProgressView().tint(.white).frame(width: 86, height: 108)
                        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 17))
                    }
                  }
                }
                if (app.me?.photos.count ?? 0) < 8 {
                  PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: max(1, 8 - (app.me?.photos.count ?? 0)),
                    matching: .images
                  ) {
                    VStack(spacing: 7) {
                      Image(systemName: uploading ? "hourglass" : "photo.badge.plus").font(.headline)
                      Text(uploading ? "Subiendo" : "Añadir fotos").font(.caption2.bold())
                    }.frame(width: 104, height: 98).foregroundStyle(NookColors.espresso)
                      .background(NookColors.latte.opacity(0.20), in: RoundedRectangle(cornerRadius: 17))
                      .overlay(RoundedRectangle(cornerRadius: 17).stroke(NookColors.mocha.opacity(0.35)))
                  }.disabled(uploading)
                }
              }
            }.scrollIndicators(.hidden)
          }.padding(.horizontal, 22)

          VStack(alignment: .leading, spacing: 14) {
            Text("DATOS DEL PERFIL").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
            HStack(spacing: 12) {
              Image(systemName: "mappin.and.ellipse").frame(width: 22).foregroundStyle(NookColors.mocha)
              TextField("Ciudad o pueblo", text: $city)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            }.padding(.vertical, 9)
            Divider().overlay(NookColors.oat.opacity(0.25))
            Text("Solo mostramos una ubicación aproximada.").font(.caption).foregroundStyle(NookColors.warmGray)
          }.profileSurface()

          VStack(alignment: .leading, spacing: 11) {
            Text("SOBRE TI").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
            TextEditor(text: $bio).font(.system(size: 18, weight: .medium, design: .rounded))
              .scrollContentBackground(.hidden).frame(minHeight: 92)
            Text("\(bio.count) / 500").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }.profileSurface()

          VStack(alignment: .leading, spacing: 14) {
            Text("¿PARA QUÉ TE APETECE QUEDAR?").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
            Menu {
              ForEach(LookingFor.registrationChoices) { intent in
                Button(intent.title) { withAnimation(NookMotion.spring) { looking = intent } }
              }
            } label: {
              HStack(spacing: 14) {
                Image(systemName: looking.icon).font(.headline).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                  Text(looking.profileTitle).font(.headline)
                  Text(looking.detail).font(.caption).foregroundStyle(NookColors.espresso.opacity(0.58)).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
              }.foregroundStyle(NookColors.espresso)
            }
          }.profileSurface()

          VStack(alignment: .leading, spacing: 15) {
            Text("TU FORMA DE TOMAR CAFÉ").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
            profileMenu("cup.and.saucer.fill", coffeePersonality, values: [
              ("Solo", "Solo"), ("Cortado", "Cortado"), ("Café con leche", "Café con leche"),
              ("Iced coffee", "Iced coffee"), ("Matcha", "Matcha"), ("Té", "Té")
            ]) { coffeePersonality = $0 }
            Divider().overlay(NookColors.oat.opacity(0.25))
            profileMenu("sparkles", vibeCopy(preferredVibe), values: [
              ("CALM", "Sitios tranquilos"), ("SOCIAL", "Con ambiente"), ("LIVELY", "Sitios animados")
            ]) { preferredVibe = $0 }
            Divider().overlay(NookColors.oat.opacity(0.25))
            profileMenu("clock", momentCopy(favoriteMoment), values: [
              ("MORNING", "Por la mañana"), ("MIDDAY", "Al mediodía"), ("AFTERWORK", "Afterwork"), ("EVENING", "Por la tarde")
            ]) { favoriteMoment = $0 }
            Divider().overlay(NookColors.oat.opacity(0.25))
            profileMenu("figure.walk", planCopy(preferredPlan), values: [
              ("QUICK", "Café rápido"), ("LONG_TALKS", "Sin prisas"), ("WALK", "Café y paseo"), ("IMPROVISE", "Improvisar")
            ]) { preferredPlan = $0 }
            if let preferences = app.me?.coffeePreferences, !preferences.isEmpty {
              HStack(spacing: 7) {
                ForEach(preferences.prefix(3), id: \.self) { value in
                  Text(coffeeCopy(value)).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(NookColors.oat.opacity(0.28), in: Capsule())
                }
              }
            }
          }.profileSurface()

          VStack(spacing: 0) {
            Toggle(isOn: $visible) {
              Label("Aparecer en Descubrir", systemImage: "eye")
            }.padding(.vertical, 15)
            Divider()
            Toggle(isOn: $sounds) {
              Label("Sonidos de café", systemImage: "speaker.wave.2")
            }.padding(.vertical, 15)
            Divider()
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "location.slash").frame(width: 22)
              Text("Tu ubicación exacta nunca aparece en tu perfil.").font(.callout).foregroundStyle(.secondary)
              Spacer()
            }.padding(.vertical, 15)
          }.font(.system(size: 15, weight: .semibold, design: .rounded)).tint(NookColors.mocha).profileSurface()

          Button { saveProfile() } label: {
            HStack(spacing: 8) {
              if saving {
                Image(systemName: "cup.and.saucer.fill")
                  .symbolEffect(.pulse, options: .repeating)
              }
              Image(systemName: saved ? "checkmark" : "arrow.down")
              Text(saved ? "Guardado" : "Guardar cambios")
            }.font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
              .padding(.horizontal, 22).frame(height: 48).background(NookColors.espresso, in: Capsule())
          }.disabled(saving)

          Button("Cerrar sesión", role: .destructive) { Task { await app.logout() } }
            .font(.callout.weight(.semibold)).padding(.top, 5)
        }.padding(.bottom, 18)
      }.scrollIndicators(.hidden)
    }.alert("No hemos podido guardar", isPresented: Binding(
      get: { profileError != nil }, set: { if !$0 { profileError = nil } }
    )) { Button("Entendido") { profileError = nil } } message: { Text(profileError ?? "") }
    .confirmationDialog(
      "¿Eliminar esta foto?", isPresented: Binding(
        get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Eliminar foto", role: .destructive) {
        guard let photo = photoToDelete else { return }
        photoToDelete = nil
        Task { await deletePhoto(photo.id) }
      }
      Button("Cancelar", role: .cancel) { photoToDelete = nil }
    } message: {
      Text("Se eliminará de tu perfil de Nook.")
    }
    .onAppear {
      bio = app.me?.bio ?? ""
      visible = app.me?.visible ?? true
      looking = app.me?.lookingFor ?? .casualCoffee
      city = app.me?.city ?? ""
      coffeePersonality = app.me?.coffeePersonality ?? "Café con leche"
      preferredVibe = app.me?.preferredVibe ?? "SOCIAL"
      favoriteMoment = app.me?.favoriteCoffeeMoment ?? "AFTERWORK"
      preferredPlan = app.me?.preferredPlan ?? "IMPROVISE"
    }.onChange(of: photoItems) { _, items in upload(items) }
      .onChange(of: bio) { _, value in if value.count > 500 { bio = String(value.prefix(500)) } }
      .onChange(of: sounds) { _, value in NookSoundManager.shared.enabled = value }
      .toolbar(.hidden, for: .navigationBar)
  }
  private func saveProfile() {
    saving = true; saved = false
    Task {
      do {
        app.me = try await app.repository.updateProfile(ProfileUpdate(
          bio: bio, city: city.trimmingCharacters(in: .whitespacesAndNewlines),
          lookingFor: looking, coffeePersonality: coffeePersonality, preferredPlan: preferredPlan,
          preferredVibe: preferredVibe, favoriteCoffeeMoment: favoriteMoment, visible: visible))
        withAnimation(NookMotion.spring) { saved = true }
      } catch { profileError = error.localizedDescription }
      saving = false
    }
  }
  private func upload(_ items: [PhotosPickerItem]) {
    guard !items.isEmpty, !uploading else { return }
    uploading = true
    Task {
      do {
        for item in items.prefix(max(0, 8 - (app.me?.photos.count ?? 0))) {
          guard let data = try await item.loadTransferable(type: Data.self) else { continue }
          let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
          _ = try await app.repository.uploadPhoto(data: data, mimeType: mime)
        }
        app.me = try await app.repository.me()
      } catch { profileError = "No hemos podido añadir todas las fotos. Inténtalo de nuevo." }
      uploading = false; photoItems = []
    }
  }
  private var orderedPhotos: [Photo] {
    (app.me?.photos ?? []).sorted {
      if ($0.isPrimary == true) != ($1.isPrimary == true) { return $0.isPrimary == true }
      return $0.position < $1.position
    }
  }
  @MainActor private func refreshPhotos() async throws {
    app.me = try await app.repository.me()
  }
  @MainActor private func makePrimary(_ id: UUID) async {
    guard photoOperation == nil else { return }
    photoOperation = id
    defer { photoOperation = nil }
    do {
      _ = try await app.repository.makePrimaryPhoto(id)
      try await refreshPhotos()
      Haptics.success()
    } catch { profileError = "No hemos podido cambiar la foto principal. Inténtalo de nuevo." }
  }
  @MainActor private func deletePhoto(_ id: UUID) async {
    guard photoOperation == nil else { return }
    photoOperation = id
    defer { photoOperation = nil }
    do {
      try await app.repository.deletePhoto(id)
      try await refreshPhotos()
      Haptics.success()
    } catch { profileError = "No hemos podido eliminar la foto. Inténtalo de nuevo." }
  }
  @MainActor private func move(_ id: UUID, offset: Int) async {
    guard photoOperation == nil else { return }
    var photos = orderedPhotos
    guard let from = photos.firstIndex(where: { $0.id == id }) else { return }
    let destination = min(max(0, from + offset), photos.count - 1)
    guard from != destination else { return }
    photos.swapAt(from, destination)
    photoOperation = id
    defer { photoOperation = nil }
    do {
      _ = try await app.repository.reorderPhotos(photos.map(\.id))
      try await refreshPhotos()
      Haptics.selection()
    } catch { profileError = "No hemos podido reordenar las fotos. Inténtalo de nuevo." }
  }
  private func profileMenu(_ icon: String, _ text: String, values: [(String, String)], select: @escaping (String) -> Void) -> some View {
    Menu {
      ForEach(values, id: \.0) { value in Button(value.1) { select(value.0) } }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 22).foregroundStyle(NookColors.mocha)
        Text(text).font(.system(size: 15, weight: .semibold, design: .rounded))
        Spacer()
        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(NookColors.warmGray)
      }.foregroundStyle(NookColors.espresso).contentShape(Rectangle())
    }
  }
  private func vibeCopy(_ value: String?) -> String { value == "CALM" ? "Sitios tranquilos" : value == "LIVELY" ? "Sitios animados" : "Con ambiente" }
  private func momentCopy(_ value: String?) -> String { value == "MORNING" ? "Por la mañana" : value == "MIDDAY" ? "Al mediodía" : value == "AFTERWORK" ? "Afterwork" : "Por la tarde" }
  private func planCopy(_ value: String?) -> String { value == "WALK" ? "Café y paseo" : value == "QUICK" ? "Café rápido" : value == "LONG_TALKS" ? "Sin prisas" : "Improvisar" }
  private func coffeeCopy(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
}

private extension View {
  func profileSurface() -> some View {
    self.padding(20).background(NookColors.offWhite.opacity(0.88), in: RoundedRectangle(cornerRadius: 24))
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(NookColors.mocha.opacity(0.08)))
      .padding(.horizontal, 18)
  }
}

struct EditProfileSheet: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  @Binding var bio: String
  @Binding var visible: Bool
  @Binding var looking: LookingFor
  let save: () -> Void
  @State private var photoItem: PhotosPickerItem?
  @State private var uploading = false
  @State private var photoError: String?
  var body: some View {
    NavigationStack {
      ZStack {
        NookBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Text("Edita tu historia").font(NookTypography.display(42))
            VStack(alignment: .leading, spacing: 12) {
              Text("TUS FOTOS · \(app.me?.photos.count ?? 0)/8").font(.caption.bold()).tracking(1.3).foregroundStyle(NookColors.mocha)
              ScrollView(.horizontal) {
                HStack(spacing: 10) {
                  ForEach(app.me?.photos.sorted(by: { $0.position < $1.position }) ?? []) { photo in
                    ZStack(alignment: .topTrailing) {
                      ProfileImage(url: photo.url, name: app.me?.name ?? "N").frame(width: 94, height: 122)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(alignment: .bottomLeading) {
                          if photo.isPrimary == true {
                            Text("PRINCIPAL").font(.system(size: 9, weight: .bold)).tracking(0.7)
                              .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6)
                              .background(.black.opacity(0.48), in: Capsule()).padding(7)
                          }
                        }
                      Menu {
                        if photo.isPrimary != true {
                          Button("Usar como principal", systemImage: "star.fill") { Task { await makePrimary(photo.id) } }
                        }
                        Button("Mover a la izquierda", systemImage: "arrow.left") { Task { await move(photo.id, offset: -1) } }
                        Button("Mover a la derecha", systemImage: "arrow.right") { Task { await move(photo.id, offset: 1) } }
                        Button("Eliminar foto", systemImage: "trash", role: .destructive) { Task { await delete(photo.id) } }
                      } label: {
                        Image(systemName: "ellipsis").font(.caption.bold()).foregroundStyle(.white)
                          .frame(width: 30, height: 30).background(.black.opacity(0.46), in: Circle()).padding(6)
                      }
                    }
                  }
                  if (app.me?.photos.count ?? 0) < 8 {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                      VStack(spacing: 8) { Image(systemName: "plus").font(.title2); Text(uploading ? "Subiendo" : "Añadir").font(.caption.bold()) }
                        .frame(width: 94, height: 122).background(NookColors.oat.opacity(0.25), in: RoundedRectangle(cornerRadius: 20))
                    }.disabled(uploading)
                  }
                }
              }.scrollIndicators(.hidden)
            }
            TextEditor(text: $bio).font(.title3.weight(.medium)).scrollContentBackground(.hidden)
              .padding(18).frame(height: 180).background(
                NookColors.offWhite, in: RoundedRectangle(cornerRadius: NookRadius.large))
            VStack(alignment: .leading, spacing: 8) {
              Text("¿PARA QUÉ TE APETECE QUEDAR?").font(.caption.bold()).tracking(1.3).foregroundStyle(NookColors.mocha)
              ForEach(LookingFor.registrationChoices) { intent in
                Button { withAnimation(NookMotion.spring) { looking = intent } } label: {
                  HStack(spacing: 13) {
                    Image(systemName: intent.icon).frame(width: 22)
                    Text(intent.title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: looking == intent ? "checkmark.circle.fill" : "circle")
                  }.foregroundStyle(NookColors.espresso).padding(.vertical, 12)
                }.buttonStyle(.plain)
                if intent != LookingFor.registrationChoices.last { Divider().opacity(0.45) }
              }
            }.padding(19).background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: NookRadius.large))
            NookCard {
              Toggle("Perfil visible", isOn: $visible).font(.headline).tint(NookColors.espresso)
            }
            if let photoError {
              Text(photoError).font(.footnote.weight(.semibold)).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            NookButton(title: "GUARDAR CAMBIOS", icon: "checkmark") { save() }
          }.padding(24)
        }
      }.navigationTitle("Perfil").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        .onChange(of: photoItem) { _, item in
          guard let item else { return }
          uploading = true
          Task {
            do {
              guard let data = try await item.loadTransferable(type: Data.self) else { throw URLError(.cannotDecodeContentData) }
              let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
              _ = try await app.repository.uploadPhoto(data: data, mimeType: mime)
              try await refreshPhotos()
              photoError = nil
            } catch { photoError = error.localizedDescription }
            uploading = false
          }
        }
    }
  }

  @MainActor private func refreshPhotos() async throws { app.me = try await app.repository.me() }
  @MainActor private func delete(_ id: UUID) async {
    do { try await app.repository.deletePhoto(id); try await refreshPhotos(); photoError = nil }
    catch { photoError = error.localizedDescription }
  }
  @MainActor private func makePrimary(_ id: UUID) async {
    do { _ = try await app.repository.makePrimaryPhoto(id); try await refreshPhotos(); photoError = nil }
    catch { photoError = error.localizedDescription }
  }
  @MainActor private func move(_ id: UUID, offset: Int) async {
    var photos = app.me?.photos.sorted { $0.position < $1.position } ?? []
    guard let from = photos.firstIndex(where: { $0.id == id }) else { return }
    let target = min(max(0, from + offset), photos.count - 1)
    guard target != from else { return }
    photos.swapAt(from, target)
    do { _ = try await app.repository.reorderPhotos(photos.map(\.id)); try await refreshPhotos(); photoError = nil }
    catch { photoError = error.localizedDescription }
  }
}

struct SettingsView: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  @AppStorage("coffeeSoundsEnabled") private var sounds = true
  @State private var visible = true
  @State private var pushEnabled = true
  @State private var loaded = false
  @State private var savingVisibility = false
  @State private var savingSettings = false
  @State private var lastSavedSounds = true
  @State private var lastSavedPush = true
  @State private var errorMessage: String?
  var body: some View {
    NavigationStack {
      ZStack {
        NookBackground()
        ScrollView {
          VStack(spacing: 16) {
            NookCard {
              VStack(spacing: 0) {
                Toggle(isOn: $sounds) { Label("Sonidos de café", systemImage: "speaker.wave.2.fill") }
                  .padding(.vertical, 12).disabled(!loaded || savingSettings)
                Divider()
                Toggle(isOn: $pushEnabled) { Label("Notificaciones", systemImage: "bell.fill") }
                  .padding(.vertical, 12).disabled(!loaded || savingSettings)
                Divider()
                Toggle(isOn: $visible) { Label("Aparecer en Descubrir", systemImage: "eye.fill") }
                  .padding(.vertical, 12).disabled(!loaded || savingVisibility)
              }.font(.headline).tint(NookColors.mocha)
            }
            NookCard {
              VStack(alignment: .leading, spacing: 10) {
                Label("Privacidad y seguridad", systemImage: "lock.shield.fill").font(.headline)
                Text("Tu ubicación exacta nunca se muestra a otras personas.").font(.callout).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Cerrar sesión", role: .destructive) { Task { await app.logout(); dismiss() } }
              .font(.headline).padding(18)
            if let errorMessage {
              Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
          }.padding(20)
        }
      }.navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        .task {
          visible = app.me?.visible ?? true
          do {
            let remote = try await app.repository.settings()
            sounds = remote.coffeeSoundsEnabled
            let authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            let systemAllowsPush = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
            pushEnabled = remote.pushEnabled && systemAllowsPush
            lastSavedSounds = sounds
            lastSavedPush = pushEnabled
            NookSoundManager.shared.enabled = sounds
          } catch { errorMessage = "No hemos podido cargar tus ajustes." }
          loaded = true
        }
        .onChange(of: visible) { _, value in
          guard loaded else { return }
          savingVisibility = true
          Task {
            do {
              app.me = try await app.repository.updateProfile(ProfileUpdate(visible: value))
              errorMessage = nil
            } catch {
              loaded = false
              visible = app.me?.visible ?? !value
              loaded = true
              errorMessage = "No hemos podido guardar este ajuste. Inténtalo de nuevo."
            }
            savingVisibility = false
          }
        }
        .onChange(of: sounds) { _, value in
          NookSoundManager.shared.enabled = value
          guard loaded else { return }
          savingSettings = true
          Task {
            defer { savingSettings = false }
            do {
              _ = try await app.repository.updateSettings(.init(coffeeSoundsEnabled: value))
              lastSavedSounds = value
              errorMessage = nil
            } catch {
              loaded = false; sounds = lastSavedSounds; loaded = true
              NookSoundManager.shared.enabled = lastSavedSounds
              errorMessage = "No hemos podido guardar este ajuste. Inténtalo de nuevo."
            }
          }
        }
        .onChange(of: pushEnabled) { _, value in
          guard loaded else { return }
          savingSettings = true
          Task {
            defer { savingSettings = false }
            do {
              if value, !(await app.requestPushAuthorization()) {
                loaded = false; pushEnabled = false; loaded = true
                errorMessage = "Activa las notificaciones de Nook desde Ajustes del iPhone para recibir confirmaciones."
                return
              }
              _ = try await app.repository.updateSettings(.init(pushEnabled: value))
              lastSavedPush = value
              errorMessage = nil
            } catch {
              loaded = false; pushEnabled = lastSavedPush; loaded = true
              errorMessage = "No hemos podido guardar este ajuste. Inténtalo de nuevo."
            }
          }
        }
    }
  }

}
