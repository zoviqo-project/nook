import PhotosUI
import SwiftUI
import UserNotifications

private enum NookDemoProfiles {
  static let people: [DiscoverProfile] = [
    person("D0000000-0000-0000-0000-000000000001", "Laura", 29,
      "Arquitecta, conciertos y cafeterías pequeñas.", 1.4, "Café con leche",
      "asset://NookDemoProfile"),
    person("D0000000-0000-0000-0000-000000000002", "Clara", 28,
      "Diseño, vinilos y sobremesas largas.", 1.8, "Cortado",
      "asset://NookDemoProfile3"),
    person("D0000000-0000-0000-0000-000000000003", "Elena", 32,
      "Cine, cocina y rincones tranquilos.", 2.4, "Solo",
      "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&w=1000&q=85"),
    person("D0000000-0000-0000-0000-000000000004", "Nora", 26,
      "Ilustración, montaña y probar sitios nuevos.", 3.0, "Matcha",
      "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=1000&q=85"),
    person("D0000000-0000-0000-0000-000000000005", "Julia", 30,
      "Editorial, teatro y escapadas de domingo.", 3.7, "Latte",
      "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=1000&q=85"),
    person("D0000000-0000-0000-0000-000000000006", "Marc", 30,
      "Diseño de producto, rutas urbanas y café de filtro.", 4.1, "V60",
      "asset://NookDemoProfile2"),
    person("D0000000-0000-0000-0000-000000000007", "Kenji", 32,
      "Fotografía, jazz y descubrir barras de café tranquilas.", 4.8, "Flat white",
      "asset://NookDemoProfile4")
  ]

  static func contains(_ id: UUID) -> Bool { people.contains { $0.id == id } }

  private static func person(
    _ id: String, _ name: String, _ age: Int, _ bio: String, _ distance: Double,
    _ coffee: String, _ photo: String
  ) -> DiscoverProfile {
    DiscoverProfile(
      id: UUID(uuidString: id)!, name: name, age: age, bio: bio, city: "Barcelona",
      distanceKm: distance, coffeePersonality: coffee, preferredPlan: "LONG_TALKS",
      preferredVibe: "CALM", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK",
      lookingFor: .seeWhatHappens, coffeePreferences: [coffee.uppercased()],
      photos: demoPhotos(for: photo))
  }

  private static func demoPhotos(for photo: String) -> [Photo] {
    let additionalPhotos: [String]
    switch photo {
    case "asset://NookDemoProfile":
      additionalPhotos = ["asset://NookDemoProfileGallery2", "asset://NookDemoProfileGallery3"]
    case "asset://NookDemoProfile2":
      additionalPhotos = ["asset://NookDemoMarcGallery2"]
    case "asset://NookDemoProfile3":
      additionalPhotos = ["asset://NookDemoClaraGallery2"]
    case "asset://NookDemoProfile4":
      additionalPhotos = ["asset://NookDemoKenjiGallery2"]
    case let url where url.contains("1531123897727"):
      additionalPhotos = ["asset://NookDemoElenaGallery2"]
    case let url where url.contains("1517841905240"):
      additionalPhotos = ["asset://NookDemoNoraGallery2"]
    case let url where url.contains("1529139574466"):
      additionalPhotos = ["asset://NookDemoJuliaGallery2"]
    default:
      additionalPhotos = []
    }
    let urls = [photo] + additionalPhotos
    return urls.enumerated().map { index, url in
      Photo(id: UUID(), url: url, position: index, isPrimary: index == 0)
    }
  }
}

@MainActor final class DiscoverVM: ObservableObject {
  @Published var people: [DiscoverProfile] = []
  @Published var match: Match?
  @Published var loading = true
  @Published var error: String?
  @Published private(set) var actingOn: UUID?
  @Published private(set) var pendingMatchedPersonID: UUID?
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
      let remotePeople = try await repo.discover()
      #if DEBUG
        // Development builds always keep the local gallery available so the
        // complete matching flow can be reviewed even with a sparse backend.
        let remoteIDs = Set(remotePeople.map(\.id))
        people = NookDemoProfiles.people.filter { !remoteIDs.contains($0.id) } + remotePeople
      #else
        people = remotePeople.isEmpty ? NookDemoProfiles.people : remotePeople
      #endif
    } catch {
      self.error = NookErrorCopy.message(
        for: error, fallback: "No hemos podido cargar nuevos perfiles. Inténtalo de nuevo.")
    }
    #if DEBUG
      print("[PERF] Discover API + decode: \(Int(Date().timeIntervalSince(startedAt) * 1_000))ms")
    #endif
  }
  func pass(_ person: DiscoverProfile, repo: any NookRepository) async {
    guard actingOn == nil, let index = people.firstIndex(where: { $0.id == person.id }) else { return }
    actingOn = person.id
    defer { actingOn = nil }
    if NookDemoProfiles.contains(person.id) {
      people.remove(at: index)
      Haptics.selection()
      if people.isEmpty { people = NookDemoProfiles.people }
      return
    }
    do {
      try await repo.pass(person.id)
      people.removeAll { $0.id == person.id }
      Haptics.selection()
      if people.isEmpty { await load(repo) }
    } catch {
      self.error = NookErrorCopy.message(
        for: error, fallback: "No hemos podido guardar esta acción. Inténtalo de nuevo.")
    }
  }
  func coffee(_ person: DiscoverProfile, repo: any NookRepository) async {
    guard actingOn == nil, people.contains(where: { $0.id == person.id }) else { return }
    actingOn = person.id
    defer { actingOn = nil }
    Haptics.coffee()
    NookSoundManager.shared.play(.coffeeLike)
    if NookDemoProfiles.contains(person.id) {
      people.removeAll { $0.id == person.id }
      if people.isEmpty { people = NookDemoProfiles.people }
      return
    }
    do {
      let result = try await repo.like(person.id)
      withAnimation(NookMotion.playful) {
        match = result.match
      }
      if result.matched {
        pendingMatchedPersonID = person.id
        Haptics.success()
      } else {
        people.removeAll { $0.id == person.id }
      }
      if people.isEmpty { await load(repo) }
    } catch {
      self.error = NookErrorCopy.message(
        for: error, fallback: "No hemos podido enviar tu café. Inténtalo de nuevo.")
    }
  }
  func finishMatch(repo: any NookRepository) async {
    guard let pendingMatchedPersonID else { return }
    people.removeAll { $0.id == pendingMatchedPersonID }
    self.pendingMatchedPersonID = nil
    if people.isEmpty { await load(repo) }
  }
}

struct DiscoverView: View {
  @EnvironmentObject var app: AppSession
  @StateObject private var vm = DiscoverVM()
  @State private var drag: CGSize = .zero
  @State private var photoIndex = 0
  @State private var photoSwipeOffset: CGFloat = 0
  @State private var liking = false
  @State private var entrance = false
  @State private var showFilters = false
  @State private var showProfile = false
  @State private var selectedProfile: DiscoverProfile?
  @AppStorage("didSeeDiscoveryPhotoSwipeHint") private var didSeeSwipeHint = false
  @State private var showSwipeHint = false
  @State private var swipeHintPulse = false
  @State private var matchProgress = false
  var body: some View {
    GeometryReader { screen in
      let safeArea = activeWindowSafeAreaInsets
      ZStack {
        NookInteriorBackdrop().ignoresSafeArea()
        Group {
          if vm.loading && vm.people.isEmpty {
            NookSkeletonScreen(layout: .profileCard)
              .ignoresSafeArea()
          } else if let person = vm.people.first {
            if vm.match != nil {
              celebrationPhoto(for: person)
                .ignoresSafeArea()
            } else {
              cardStack(
                person, topInset: safeArea.top,
                bottomInset: safeArea.bottom)
                .ignoresSafeArea()

              matchingChrome(
                person, topInset: safeArea.top,
                bottomInset: safeArea.bottom,
                leadingInset: safeArea.left, trailingInset: safeArea.right)
            }
          } else if let error = vm.error {
            NookErrorView(message: error) { Task { await vm.load(app.repository) } }
              .padding(.top, safeArea.top)
              .padding(.bottom, safeArea.bottom)
          } else {
            empty
              .padding(.top, safeArea.top)
              .padding(.bottom, safeArea.bottom)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let match = vm.match {
          MatchCelebration(match: match) {
            vm.match = nil
            Task { await vm.finishMatch(repo: app.repository) }
          }
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
          .zIndex(50)
        }
      }
      .frame(width: screen.size.width, height: screen.size.height)
      .ignoresSafeArea()
    }
    .ignoresSafeArea(.container, edges: .all)
    .preferredColorScheme(.dark)
    .environment(\.colorScheme, .dark)
    .background(NookLightStatusBarBridge())
    .onAppear {
      app.tabBarHidden = true
      setLightStatusBar(true)
    }
    .onDisappear {
      app.tabBarHidden = false
      setLightStatusBar(false)
    }
    .task {
      if let cache = app.discoverCache { vm.seed(cache) }
      await vm.load(app.repository, showLoader: app.discoverCache == nil)
      app.cacheDiscover(vm.people)
      NookImagePrefetch.schedule(vm.people.prefix(3).flatMap { $0.photos.map(\.url) })
      entrance = true
      withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
        matchProgress = true
      }
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
    }.sheet(isPresented: $showFilters) { DiscoveryFiltersView() }
      .sheet(isPresented: $showProfile) {
        NavigationStack { ProfileView() }
          // Keep the profile at the large detent. Without an explicit detent/content
          // policy, a vertical drag at the top of its ScrollView can move the whole
          // sheet, which looks like the complete body is jumping intermittently.
          .presentationDetents([.large])
          .presentationContentInteraction(.scrolls)
          .presentationDragIndicator(.hidden)
          .presentationBackground(NookColors.background)
      }
      .fullScreenCover(item: $selectedProfile) { PersonProfileView(person: $0) }
      .onChange(of: vm.people) { _, people in
        photoIndex = 0
        app.cacheDiscover(people)
        NookImagePrefetch.schedule(people.prefix(3).flatMap { $0.photos.map(\.url) })
      }
  }
  private func cardStack(
    _ person: DiscoverProfile, topInset: CGFloat, bottomInset: CGFloat
  ) -> some View {
    GeometryReader { proxy in
      let cardHeight = max(1, proxy.size.height)
      ZStack(alignment: .bottom) {
        if vm.people.count > 1 {
          NookProfileCard(
            person: vm.people[1], viewer: app.me, height: cardHeight,
            photoURL: vm.people[1].photos.first?.url, immersive: true,
            contentTopInset: topInset, contentBottomInset: bottomInset)
            .allowsHitTesting(false)
        }
          NookProfileCard(
            person: person, viewer: app.me, height: cardHeight,
            photoURL: selectedPhotoURL(for: person),
            nextPhotoURL: adjacentPhotoURL(for: person), photoOffset: photoSwipeOffset,
            onNameTap: { selectedProfile = person }, immersive: true,
          contentTopInset: topInset, contentBottomInset: bottomInset
        )
          .offset(drag).rotationEffect(.degrees(Double(drag.width / 28)))
          .overlay { photoSwipeHint(for: person) }
          .gesture(
            DragGesture(minimumDistance: 12)
              .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      person.photos.count > 1 else { return }
                photoSwipeOffset = value.translation.height
              }
              .onEnded { value in
                guard abs(value.translation.height) > 52,
                      abs(value.translation.height) > abs(value.translation.width),
                      person.photos.count > 1 else {
                  withAnimation(NookMotion.spring) { photoSwipeOffset = 0 }
                  return
                }
                completePhotoSwipe(
                  in: person, direction: value.translation.height < 0 ? 1 : -1,
                  cardHeight: cardHeight)
              }
          ).allowsHitTesting(vm.actingOn == nil)
      }
      .scaleEffect(entrance ? 1 : 0.96)
      .offset(y: entrance ? 0 : 28)
      .animation(NookMotion.spring, value: entrance)
      .frame(width: proxy.size.width, height: cardHeight, alignment: .center)
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  private func celebrationPhoto(for person: DiscoverProfile) -> some View {
    GeometryReader { proxy in
      ZStack {
        ProfileImage(url: selectedPhotoURL(for: person), name: person.name)
          .frame(width: proxy.size.width, height: proxy.size.height)
        LinearGradient(
          colors: [.black.opacity(0.30), .clear, .black.opacity(0.48)],
          startPoint: .top, endPoint: .bottom)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
    }
  }

  private func matchingChrome(
    _ person: DiscoverProfile, topInset: CGFloat, bottomInset: CGFloat,
    leadingInset: CGFloat, trailingInset: CGFloat
  ) -> some View {
    VStack(spacing: 8) {
      NookHeader(
        eyebrow: "NOOK", title: "Un café con…", branded: true,
        actionIcon: "slider.horizontal.3", actionLabel: "Filtros",
        action: { showFilters = true },
        secondaryActionIcon: "person.crop.circle",
        secondaryActionLabel: "Mi perfil", secondaryAction: { showProfile = true },
        cinematic: true)
        .frame(height: 56)

      HStack {
        purposeBadge(for: person)
        Spacer()
        immersiveNavigation
      }

      Spacer(minLength: 0)

      actions(person)
        .offset(drag)
        .allowsHitTesting(vm.actingOn == nil)
    }
    .padding(.top, topInset)
    .padding(.leading, leadingInset + 12)
    .padding(.trailing, trailingInset + 12)
    .padding(.bottom, bottomInset + 10)
    .overlay(alignment: .trailing) {
      nextPhotoThumbnail(for: person)
        .padding(.trailing, trailingInset + 12)
    }
  }

  private var activeWindowSafeAreaInsets: UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
      ?? scenes.flatMap(\.windows).first
    return window?.safeAreaInsets ?? .zero
  }

  private func setLightStatusBar(_ light: Bool) {
    UIApplication.shared.setStatusBarStyle(light ? .lightContent : .darkContent, animated: true)
  }
  @ViewBuilder private func photoSwipeHint(for person: DiscoverProfile) -> some View {
    if showSwipeHint && person.photos.count > 1 {
      VStack(spacing: 5) {
        Image(systemName: "arrow.up.and.down")
        Text("MÁS FOTOS")
          .font(.system(size: 9, weight: .bold))
          .tracking(1)
      }
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 13).frame(height: 48)
      .background(.black.opacity(0.30), in: Capsule())
      .opacity(swipeHintPulse ? 1 : 0.35)
      .transition(.opacity)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Desliza arriba o abajo para recorrer las fotos")
    }
  }
  private func dismissSwipeHint() {
    guard showSwipeHint else { return }
    didSeeSwipeHint = true
    withAnimation(NookMotion.fast) { showSwipeHint = false }
  }

  private func selectedPhotoURL(for person: DiscoverProfile) -> String? {
    guard !person.photos.isEmpty else { return nil }
    return person.photos[min(photoIndex, person.photos.count - 1)].url
  }

  private func adjacentPhotoURL(for person: DiscoverProfile) -> String? {
    guard person.photos.count > 1 else { return nil }
    let direction = photoSwipeOffset > 0 ? -1 : 1
    let index = (photoIndex + direction + person.photos.count) % person.photos.count
    return person.photos[index].url
  }

  @ViewBuilder private func photoProgress(for person: DiscoverProfile) -> some View {
    if person.photos.count > 1 {
      HStack(spacing: 4) {
        ForEach(person.photos.indices, id: \.self) { index in
          Capsule()
            .fill(index == photoIndex ? Color.white : Color.white.opacity(0.36))
            .frame(width: index == photoIndex ? 18 : 7, height: 3)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: photoIndex)
      .accessibilityLabel("Foto \(photoIndex + 1) de \(person.photos.count)")
    }
  }

  @ViewBuilder private func nextPhotoThumbnail(for person: DiscoverProfile) -> some View {
    if person.photos.count > 1 {
      let nextIndex = (photoIndex + 1) % person.photos.count
      VStack(spacing: 7) {
        VStack(spacing: -10) {
          ProfileImage(url: person.photos[photoIndex].url, name: person.name)
            .frame(width: 44, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(0.72)
            .scaleEffect(0.92)
          ProfileImage(url: person.photos[nextIndex].url, name: person.name)
            .frame(width: 56, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: darkThumbnailShadow, radius: 10, y: 5)
        }
      }
      .padding(.vertical, 5)
      .contentShape(Rectangle())
      .onTapGesture {
        completePhotoSwipe(in: person, direction: 1, cardHeight: UIScreen.main.bounds.height)
      }
      .accessibilityLabel("Ver la siguiente foto de \(person.name)")
      .accessibilityAddTraits(.isButton)
      .gesture(
        DragGesture(minimumDistance: 16).onEnded { value in
          guard value.translation.height < -34,
                abs(value.translation.height) > abs(value.translation.width) else { return }
          completePhotoSwipe(in: person, direction: 1, cardHeight: UIScreen.main.bounds.height)
        }
      )
    }
  }

  private var darkThumbnailShadow: Color {
    Color(red: 0.12, green: 0.055, blue: 0.025).opacity(0.55)
  }

  private func completePhotoSwipe(
    in person: DiscoverProfile, direction: Int, cardHeight: CGFloat
  ) {
    guard person.photos.count > 1 else { return }
    dismissSwipeHint()
    Haptics.selection()
    withAnimation(.easeOut(duration: 0.24)) {
      photoSwipeOffset = CGFloat(-direction) * max(cardHeight, 500)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
      photoIndex = (photoIndex + direction + person.photos.count) % person.photos.count
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { photoSwipeOffset = 0 }
    }
  }

  private func actions(_ person: DiscoverProfile) -> some View {
    HStack(alignment: .center, spacing: 40) {
      ZStack {
        matchSideAction(icon: "xmark", label: "Descartar") {
          discard(person)
        }
        if vm.actingOn == person.id && !liking {
          Circle().fill(.black.opacity(0.56)).frame(width: 48, height: 48)
          ProgressView().tint(.white)
        }
      }
      .frame(width: 48, height: 48)
      Button {
        accept(person)
      } label: {
        ZStack {
          Circle()
            .stroke(
              AngularGradient(
                colors: [
                  NookColors.mocha, NookColors.nookGold, NookColors.caramelSoft,
                  NookColors.primaryCoffeePressed, NookColors.nookGold, NookColors.mocha,
                ], center: .center),
              lineWidth: 5)
            .frame(width: 76, height: 76)
            .blur(radius: 6)
            .opacity(0.72)
            .rotationEffect(.degrees(matchProgress ? 360 : 0))
            .animation(
              .linear(duration: 4.8).repeatForever(autoreverses: false),
              value: matchProgress)
          Circle()
            .stroke(
              AngularGradient(
                colors: [NookColors.mocha, NookColors.nookGold, NookColors.caramelSoft, NookColors.mocha],
                center: .center),
              lineWidth: 2.5)
            .frame(width: 70, height: 70)
            .rotationEffect(.degrees(matchProgress ? 360 : 0))
            .animation(
              .linear(duration: 4.8).repeatForever(autoreverses: false),
              value: matchProgress)
          Circle()
            .trim(from: 0, to: matchProgress ? 0.96 : 0.08)
            .stroke(NookColors.nookGold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 70, height: 70)
            .rotationEffect(.degrees(-90))
          NookCoffeeLogo(size: 62, animated: false)
            .clipShape(Circle())
            .overlay {
              Circle().stroke(NookColors.caramelSoft.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: NookColors.nookGold.opacity(0.32), radius: 12)
          if vm.actingOn == person.id {
            Circle().fill(NookColors.espresso.opacity(0.78)).frame(width: 62, height: 62)
            ProgressView().tint(NookColors.inverseText)
          }
        }
        .scaleEffect(liking ? 1.08 : 1)
        .rotationEffect(.degrees(liking ? -4 : 0))
        .animation(NookMotion.playful, value: liking)
      }
      .buttonStyle(.plain)
      .disabled(vm.actingOn != nil)
    }
    .frame(maxWidth: 190)
    .frame(height: 78)
  }

  private func discard(_ person: DiscoverProfile) {
    dismissSwipeHint()
    withAnimation(NookMotion.spring) { drag = CGSize(width: -600, height: 24) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      Task {
        await vm.pass(person, repo: app.repository)
        resetInteractionPosition()
      }
    }
  }

  private func accept(_ person: DiscoverProfile) {
    dismissSwipeHint()
    liking = true
    withAnimation(NookMotion.spring) { drag = CGSize(width: 600, height: -18) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      Task {
        await vm.coffee(person, repo: app.repository)
        if vm.match != nil { app.matchesChanged() }
        resetInteractionPosition()
        liking = false
      }
    }
  }

  private func resetInteractionPosition() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { drag = .zero }
  }

  private func matchSideAction(
    icon: String, label: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(.black.opacity(0.30), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  private var immersiveNavigation: some View {
    HStack(spacing: 8) {
      immersiveNavigationButton(
        icon: "cup.and.saucer.fill", label: "Mis cafés", destination: 1)
      immersiveNavigationButton(
        icon: "bubble.left.and.bubble.right.fill", label: "Chats", destination: 2)
    }
    .padding(5)
    .background(.black.opacity(0.18), in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
  }

  private func purposeBadge(for person: DiscoverProfile) -> some View {
    HStack(spacing: 10) {
      Capsule()
        .fill(NookColors.nookGold)
        .frame(width: 2, height: 26)

      VStack(alignment: .leading, spacing: 1) {
        Text("PROPÓSITO")
          .font(.system(size: 8, weight: .bold))
          .tracking(1.35)
          .foregroundStyle(NookColors.caramelSoft.opacity(0.9))
        Text(person.intent?.subcategoryName ?? person.lookingFor.profileTitle)
          .font(NookTypography.business(12.5, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.76)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 48)
    .frame(maxWidth: 238, alignment: .leading)
    .background(NookColors.espresso.opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func immersiveNavigationButton(
    icon: String, label: String, destination: Int
  ) -> some View {
    Button {
      Haptics.selection()
      if destination == 1 { app.selectedCoffeeMatch = nil }
      app.selectedTab = destination
    } label: {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .background(.black.opacity(0.34), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
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
    }
    .frame(maxWidth: 330, maxHeight: .infinity, alignment: .center)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .multilineTextAlignment(.center)
    .padding(32)
  }
}

private struct NookLightStatusBarBridge: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    DispatchQueue.main.async { view.window?.overrideUserInterfaceStyle = .dark }
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async { uiView.window?.overrideUserInterfaceStyle = .dark }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
    uiView.window?.overrideUserInterfaceStyle = .light
  }
}

struct NookProfileCard: View {
  let person: DiscoverProfile
  var viewer: Me? = nil
  var height: CGFloat? = nil
  var photoURL: String? = nil
  var nextPhotoURL: String? = nil
  var photoOffset: CGFloat = 0
  var onNameTap: (() -> Void)? = nil
  var immersive = false
  var contentTopInset: CGFloat = 0
  var contentBottomInset: CGFloat = 0
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        if let nextPhotoURL {
          ProfileImage(url: nextPhotoURL, name: person.name)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        ProfileImage(url: photoURL ?? person.photos.first?.url, name: person.name)
          .frame(width: proxy.size.width, height: proxy.size.height)
          .offset(y: photoOffset)
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: .clear, location: 0.38),
            .init(color: darkCoffee.opacity(0.20), location: 0.52),
            .init(color: darkCoffee.opacity(0.68), location: 0.76),
            .init(color: darkCoffee.opacity(0.98), location: 1),
          ]),
          startPoint: .top, endPoint: .bottom)
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: darkCoffee.opacity(0.82), location: 0),
            .init(color: darkCoffee.opacity(0.48), location: 0.13),
            .init(color: darkCoffee.opacity(0.14), location: 0.27),
            .init(color: .clear, location: 0.39),
          ]),
          startPoint: .top, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 8) {
          if let onNameTap {
            Button(action: onNameTap) {
              profileName
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver información de \(person.name)")
          } else {
            profileName
          }
          if !immersive {
            Text(person.intent?.subcategoryName ?? person.lookingFor.profileTitle)
              .font(NookTypography.business(13, weight: .bold))
              .textCase(.uppercase)
              .tracking(0.7)
              .foregroundStyle(.white)
              .lineLimit(2)
          }
          Text(person.bio).font(NookTypography.business(15)).lineLimit(2).lineSpacing(2)
            .foregroundStyle(.white.opacity(0.88))
            .padding(.bottom, 2)
          HStack(spacing: 9) {
            Label("\(person.distanceKm.formatted()) km", systemImage: "location.fill")
            Circle().fill(.white.opacity(0.48)).frame(width: 3, height: 3)
            Text(person.coffeePersonality ?? "Buena conversación").lineLimit(1)
          }
          .font(NookTypography.business(13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white).padding(.horizontal, 16)
        .padding(.bottom, 88 + (immersive ? contentBottomInset : 0))
      }
      .clipShape(
        RoundedRectangle(cornerRadius: immersive ? 0 : 22, style: .continuous))
    }.frame(maxWidth: .infinity).frame(height: height ?? (verticalSizeClass == .compact ? 320 : 438))
  }

  private var darkCoffee: Color {
    Color(red: 0.16, green: 0.075, blue: 0.035)
  }

  private var profileName: some View {
    HStack(spacing: 8) {
      Text("\(person.name), \(person.age)")
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      if onNameTap != nil {
        Image(systemName: "info.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white.opacity(0.88))
      }
    }
    .font(NookTypography.business(28, weight: .bold))
    .tracking(-0.45)
    .contentShape(Rectangle())
  }
}

struct ProfileImage: View {
  let url: String?
  let name: String
  var contentMode: ContentMode = .fill
  var alignment: Alignment = .center
  var faceAware = true
  var body: some View {
    Group {
      if let localAssetName {
        localImage(named: localAssetName)
      } else {
        NookRemoteImage(
          url: resolvedURL, contentMode: contentMode, alignment: alignment, faceAware: faceAware
        ) {
          localImage(named: fallbackAssetName)
        }
      }
    }
    .clipped()
  }

  private func localImage(named assetName: String) -> some View {
    Image(assetName)
      .resizable()
      .aspectRatio(contentMode: contentMode)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  private var localAssetName: String? {
    guard let url, url.hasPrefix("asset://") else { return nil }
    return String(url.dropFirst("asset://".count))
  }
  private var fallbackAssetName: String {
    let assets = [
      "NookDemoProfile", "NookDemoProfile2", "NookDemoProfile3", "NookDemoProfile4",
    ]
    let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return assets[seed % assets.count]
  }
  private var resolvedURL: URL? {
    AppConfiguration.publicAssetURL(from: url)
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
        color: .black.opacity(0.18), radius: 9, y: 5)
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
  let match: Match
  let onDismiss: () -> Void
  @State private var meet = false
  @State private var cups = false
  @State private var coffeeBurst = false
  @State private var matchRing = false
  @State private var departing = false
  var body: some View {
    ZStack {
      Color.black.opacity(departing ? 0 : 0.28)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.65), value: departing)
      MatchCoffeeBurst(active: coffeeBurst).ignoresSafeArea().allowsHitTesting(false)
      VStack(spacing: 20) {
        Spacer()
        ZStack {
          HStack(spacing: meet ? -20 : 100) {
            avatar(name: "Tú", photo: app.me?.photos.first?.url, fromLeft: true)
            avatar(name: match.person.name, photo: match.person.photos.first?.url, fromLeft: false)
          }.animation(NookMotion.playful.delay(0.15), value: meet)
          ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 3).frame(width: 74, height: 74)
            Circle()
              .trim(from: 0, to: matchRing ? 0.96 : 0.08)
              .stroke(NookColors.mocha, style: StrokeStyle(lineWidth: 3, lineCap: .round))
              .frame(width: 74, height: 74)
              .rotationEffect(.degrees(-90))
            NookCoffeeLogo(size: 64, animated: false).clipShape(Circle())
          }
            .scaleEffect(cups ? 1 : 0.22)
            .rotationEffect(.degrees(cups ? 0 : -28))
            .opacity(cups ? 1 : 0)
            .shadow(color: NookColors.mocha.opacity(0.34), radius: cups ? 18 : 2, y: 7)
            .offset(y: 84)
            .animation(NookMotion.playful.delay(0.46), value: cups)
        }.frame(height: 230)
        VStack(spacing: 10) {
          Text("Tenemos café").font(NookTypography.display(41)).tracking(
            -1).foregroundStyle(.white)
          Text("\(match.person.name) también se tomaría\nun café contigo.").font(.title3)
            .foregroundStyle(.white.opacity(0.82)).multilineTextAlignment(.center)
        }.opacity(meet ? 1 : 0).offset(y: meet ? 0 : 16)
        Spacer()
        VStack(spacing: 10) {
          matchAction("Proponer un lugar", icon: "mappin.and.ellipse", primary: true) {
            beginMidpointTransition()
          }
          matchAction("Dejarlo para otro momento", icon: "clock", primary: false) {
            Haptics.selection()
            onDismiss()
          }
        }
        .frame(maxWidth: 330)
        .padding(10)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      .padding(.horizontal, NookSpacing.lg)
      .safeAreaPadding(.top, NookSpacing.sm)
      .safeAreaPadding(.bottom, NookSpacing.sm)
        .opacity(departing ? 0 : 1)
        .scaleEffect(departing ? 0.985 : 1)
        .allowsHitTesting(!departing)
      if departing {
        Color.clear.allowsHitTesting(false)
      }
    }.onAppear {
      withAnimation(NookMotion.playful) { meet = true }
      withAnimation(NookMotion.playful.delay(0.38)) { cups = true }
      withAnimation(.easeOut(duration: 1.15).delay(0.4)) { coffeeBurst = true }
      withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
        matchRing = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { Haptics.success() }
      NookSoundManager.shared.play(.match)
    }
  }
  private func beginMidpointTransition() {
    guard !departing else { return }
    Haptics.selection()
    withAnimation(.easeInOut(duration: 0.28)) {
      departing = true
      app.selectedCoffeeMatch = match.id
      app.selectedTab = 1
    }
    onDismiss()
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
        Text(title).font(.system(size: 17, weight: .semibold, design: .default))
      }
      .foregroundStyle(primary ? NookColors.espresso : Color.white)
      .frame(maxWidth: .infinity).frame(height: 54)
      .background(
        primary ? NookColors.offWhite : Color.black.opacity(0.46),
        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(primary ? Color.white.opacity(0.34) : Color.white.opacity(0.30), lineWidth: 1)
      }
      .shadow(color: .black.opacity(primary ? 0.24 : 0.12), radius: 8, y: 4)
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
      NookInteriorBackdrop()
      ScrollView {
        VStack(spacing: 0) {
          ZStack(alignment: .bottomLeading) {
            TabView(selection: $photoIndex) {
              ForEach(Array(person.photos.prefix(8).enumerated()), id: \.element.id) { index, photo in
                ProfileImage(url: photo.url, name: person.name).tag(index)
              }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 420)
            LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.84)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
              HStack(spacing: 5) {
                ForEach(0..<max(1, min(person.photos.count, 8)), id: \.self) { index in
                  Capsule().fill(index == photoIndex ? .white : .white.opacity(0.38)).frame(height: 3)
                }
              }
              Text("\(person.name), \(person.age)").font(NookTypography.business(32, weight: .bold))
              Text([person.city, "\(person.distanceKm.formatted()) km"].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline.bold()).foregroundStyle(.white.opacity(0.82))
            }.foregroundStyle(.white).padding(18)
          }
          VStack(alignment: .leading, spacing: 16) {
            if let intent = person.intent { NookIntentBadge(intent: intent, prominent: true) }
            MeetingIntentCard(intent: person.lookingFor, personName: person.name)
            profileSection("SOBRE MÍ") { Text(person.bio).font(.body.weight(.medium)).lineSpacing(3) }
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
          }.padding(16).padding(.bottom, 24)
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
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.caption.bold()).tracking(1.5).foregroundStyle(NookColors.mocha)
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(NookColors.offWhite.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
  }
  private func vibeCopy(_ value: String) -> String { value == "CALM" ? "Sitios tranquilos" : value == "LIVELY" ? "Sitios animados" : "Con ambiente" }
  private func momentCopy(_ value: String) -> String { value == "MORNING" ? "Por la mañana" : value == "AFTERWORK" ? "Después del trabajo" : "Por la tarde" }
}

private struct MeetingIntentCard: View {
  let intent: LookingFor
  let personName: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack {
        Text(personName.map { "LO QUE BUSCA \($0.uppercased())" } ?? "LO QUE BUSCO")
          .font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
        Spacer()
        Image(systemName: intent.icon).font(.system(size: 15, weight: .semibold))
          .foregroundStyle(NookColors.mocha)
      }
      Text(intent.profileTitle).font(NookTypography.business(25, weight: .bold)).tracking(-0.2)
      Text(intent.detail).font(.system(size: 15, weight: .medium, design: .default))
        .foregroundStyle(NookColors.espresso.opacity(0.64)).lineSpacing(3)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
      .background(
        LinearGradient(colors: [NookColors.oat.opacity(0.38), NookColors.offWhite], startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: NookRadius.card))
      .shadow(color: NookShadow.card.opacity(0.55), radius: 7, y: 3)
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
          VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
              Text("TU PRÓXIMO CAFÉ").font(NookTypography.caption).tracking(1.8)
                .foregroundStyle(NookColors.mocha)
              Text("¿A quién te apetece conocer?").font(NookTypography.business(30, weight: .bold))
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
                .padding(.horizontal, 18).frame(height: 50)
                .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).disabled(saving).opacity(saving ? 0.65 : 1)

            Button("Restablecer filtros") { reset() }
              .font(.subheadline.weight(.semibold)).foregroundStyle(NookColors.warmGray)
              .frame(maxWidth: .infinity).padding(.vertical, 8)
          }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 28)
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
    }.padding(16).background(NookColors.offWhite.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(NookColors.latte.opacity(0.16), lineWidth: 0.8))
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
  @State private var currentIntent: UserIntent?
  var body: some View {
    NookScreenContainer(
      eyebrow: visible ? "PERFIL VISIBLE" : "PERFIL EN PAUSA",
      title: "Este eres tú"
    ) {
      ScrollView {
        VStack(spacing: 18) {
          ZStack(alignment: .bottomLeading) {
            ProfileImage(
              url: orderedPhotos.first?.url, name: app.me?.name ?? "N", faceAware: false
            ).frame(
              height: 320)
            LinearGradient(
              colors: [.clear, NookColors.warmBlack.opacity(0.82)], startPoint: .center,
              endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
              Text("\(app.me?.name ?? "Tu perfil"), \(app.me?.age ?? 18)").font(NookTypography.business(30, weight: .bold))
              HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(app.me?.city ?? "Añade tu ciudad")
              }
              .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
            }.foregroundStyle(.white).padding(18)
            if orderedPhotos.isEmpty {
              PhotosPicker(selection: $photoItems, maxSelectionCount: 1, matching: .images) {
                Label(uploading ? "Subiendo…" : "Añadir foto principal", systemImage: "camera.fill")
                  .font(.system(size: 14, weight: .bold, design: .default))
                  .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 42)
                  .background(.black.opacity(0.54), in: Capsule())
              }.disabled(uploading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
          }.clipShape(RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 16)

          if let currentIntent {
            NookIntentBadge(intent: currentIntent, prominent: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 22)
          }

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
                .font(.system(size: 16, weight: .semibold, design: .default))
            }.padding(.vertical, 9)
            Divider().overlay(NookColors.oat.opacity(0.25))
            Text("Solo mostramos una ubicación aproximada.").font(.caption).foregroundStyle(NookColors.warmGray)
          }.profileSurface()

          VStack(alignment: .leading, spacing: 11) {
            Text("SOBRE TI").font(.caption.bold()).tracking(1.35).foregroundStyle(NookColors.mocha)
            TextEditor(text: $bio).font(.system(size: 18, weight: .medium, design: .default))
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
          }.font(.system(size: 15, weight: .semibold, design: .default)).tint(NookColors.mocha).profileSurface()

          Button { saveProfile() } label: {
            HStack(spacing: 8) {
              if saving {
                Image(systemName: "cup.and.saucer.fill")
                  .symbolEffect(.pulse, options: .repeating)
              }
              Image(systemName: saved ? "checkmark" : "arrow.down")
              Text(saved ? "Guardado" : "Guardar cambios")
            }.font(.system(size: 15, weight: .bold, design: .default)).foregroundStyle(.white)
              .padding(.horizontal, 22).frame(height: 48).background(NookColors.espresso, in: Capsule())
          }.disabled(saving)

          Button("Cerrar sesión", role: .destructive) { Task { await app.logout() } }
            .font(.callout.weight(.semibold)).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 18)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .defaultScrollAnchor(.top)
      // Image loading and profile refreshes must not inherit the perpetual
      // animations running in DiscoverView behind this sheet.
      .transaction { transaction in
        transaction.animation = nil
      }
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
    }.task { currentIntent = try? await app.repository.currentIntent() }
      .onChange(of: photoItems) { _, items in upload(items) }
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
        Text(text).font(.system(size: 15, weight: .semibold, design: .default))
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
    self.padding(NookSpacing.md)
      .background(
        NookColors.surfaceRaised,
        in: RoundedRectangle(cornerRadius: NookRadius.card, style: .continuous))
      .padding(.horizontal, NookSpacing.md)
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
  @State private var intentCategories: [IntentCategory] = []
  @State private var selectedIntentCategory: UUID?
  @State private var selectedIntentSubcategory: UUID?
  @State private var savingIntent = false
  var body: some View {
    NavigationStack {
      ZStack {
        NookInteriorBackdrop()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text("Edita tu historia").font(NookTypography.business(28, weight: .bold))
            intentSelector
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
            TextEditor(text: $bio).font(.body.weight(.medium)).scrollContentBackground(.hidden)
              .padding(15).frame(height: 150).background(
                NookColors.offWhite, in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 8) {
              Text("¿PARA QUÉ TE APETECE QUEDAR?").font(.caption.bold()).tracking(1.3).foregroundStyle(NookColors.mocha)
              ForEach(LookingFor.registrationChoices) { intent in
                Button { withAnimation(NookMotion.spring) { looking = intent } } label: {
                  HStack(spacing: 13) {
                    Image(systemName: intent.icon).frame(width: 22)
                    Text(intent.title).font(.system(size: 15, weight: .semibold, design: .default))
                    Spacer()
                    Image(systemName: looking == intent ? "checkmark.circle.fill" : "circle")
                  }.foregroundStyle(NookColors.espresso).padding(.vertical, 12)
                }.buttonStyle(.plain)
                if intent != LookingFor.registrationChoices.last { Divider().opacity(0.45) }
              }
            }.padding(16).background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 20))
            NookCard {
              Toggle("Perfil visible", isOn: $visible).font(.headline).tint(NookColors.espresso)
            }
            if let photoError {
              Text(photoError).font(.footnote.weight(.semibold)).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            NookButton(title: "GUARDAR CAMBIOS", icon: "checkmark", isLoading: savingIntent) {
              Task { await saveAll() }
            }
          }.padding(18)
        }
      }.navigationTitle("Perfil").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        .task { await loadIntents() }
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

  private var selectedCategory: IntentCategory? {
    intentCategories.first { $0.id == selectedIntentCategory }
  }
  private var intentSelector: some View {
    VStack(alignment: .leading, spacing: 13) {
      VStack(alignment: .leading, spacing: 4) {
        Text("¿QUÉ TE APETECE AHORA?").font(NookTypography.sectionLabel).tracking(1.35)
          .foregroundStyle(NookColors.mocha)
        Text("Tu intención se verá antes de conectar contigo.")
          .font(NookTypography.metadata).foregroundStyle(NookColors.warmGray)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(intentCategories) { category in
            Button {
              Haptics.selection()
              selectedIntentCategory = category.id
              selectedIntentSubcategory = category.subcategories.first?.id
            } label: {
              Label(category.name, systemImage: category.icon)
                .font(NookTypography.business(13, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 38)
                .foregroundStyle(selectedIntentCategory == category.id ? NookColors.inverseText : NookColors.espresso)
                .background(selectedIntentCategory == category.id ? NookColors.espresso : NookColors.surfaceSecondary.opacity(0.5), in: Capsule())
            }.buttonStyle(.plain)
          }
        }
      }.scrollIndicators(.hidden)
      if let category = selectedCategory {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
          ForEach(category.subcategories) { subcategory in
            Button {
              Haptics.selection(); selectedIntentSubcategory = subcategory.id
            } label: {
              HStack(spacing: 7) {
                Image(systemName: selectedIntentSubcategory == subcategory.id ? "checkmark.circle.fill" : "circle")
                Text(subcategory.name).lineLimit(2)
              }
              .font(NookTypography.business(12, weight: .semibold))
              .foregroundStyle(NookColors.espresso)
              .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
              .padding(.horizontal, 10)
              .background(selectedIntentSubcategory == subcategory.id ? NookColors.primaryCoffeeSoft.opacity(0.65) : NookColors.surface, in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
          }
        }
      }
    }.padding(16).background(NookColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
  }
  @MainActor private func loadIntents() async {
    do {
      async let categoriesRequest = app.repository.intentCategories()
      async let currentRequest = app.repository.currentIntent()
      intentCategories = try await categoriesRequest
      let current = try await currentRequest
      selectedIntentCategory = current?.categoryId ?? intentCategories.first?.id
      selectedIntentSubcategory = current?.subcategoryId ?? intentCategories.first?.subcategories.first?.id
    } catch { photoError = "No hemos podido cargar las intenciones. Inténtalo de nuevo." }
  }
  @MainActor private func saveAll() async {
    savingIntent = true
    defer { savingIntent = false }
    do {
      if let selectedIntentCategory, let selectedIntentSubcategory {
        _ = try await app.repository.updateIntent(
          categoryID: selectedIntentCategory, subcategoryID: selectedIntentSubcategory)
      }
      save()
    } catch { photoError = "No hemos podido guardar tu intención. Inténtalo de nuevo." }
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
        NookInteriorBackdrop()
        ScrollView {
          VStack(spacing: 12) {
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
              Text(errorMessage).font(NookTypography.metadata).foregroundStyle(NookColors.error).multilineTextAlignment(.center)
            }
          }.padding(16)
        }
      }.navigationTitle("Ajustes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
              Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
            }.accessibilityLabel("Cerrar")
          }
        }
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
