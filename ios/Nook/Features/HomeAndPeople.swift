import PhotosUI
import SwiftUI
import UserNotifications

private enum NookDemoProfiles {
  static let people: [DiscoverProfile] = [
    person("D0000000-0000-0000-0000-000000000001", "Laura", 29,
      "Arquitecta, conciertos y cafeterías pequeñas.", 1.4, "Café con leche",
      "asset://NookDemoProfile", .casualCoffee),
    person("D0000000-0000-0000-0000-000000000002", "Clara", 28,
      "Diseño, vinilos y sobremesas largas.", 1.8, "Cortado",
      "asset://NookDemoProfile3", .friendship),
    person("D0000000-0000-0000-0000-000000000003", "Elena", 32,
      "Cine, cocina y rincones tranquilos.", 2.4, "Solo",
      "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&w=1000&q=85", .somethingMore),
    person("D0000000-0000-0000-0000-000000000004", "Nora", 26,
      "Ilustración, montaña y probar sitios nuevos.", 3.0, "Matcha",
      "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=1000&q=85", .meetPeople),
    person("D0000000-0000-0000-0000-000000000005", "Julia", 30,
      "Editorial, teatro y escapadas de domingo.", 3.7, "Latte",
      "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=1000&q=85", .project),
    person("D0000000-0000-0000-0000-000000000006", "Marc", 30,
      "Diseño de producto, rutas urbanas y café de filtro.", 4.1, "V60",
      "asset://NookDemoProfile2", .friendship),
    person("D0000000-0000-0000-0000-000000000007", "Kenji", 32,
      "Fotografía, jazz y descubrir barras de café tranquilas.", 4.8, "Flat white",
      "asset://NookDemoProfile4", .seeWhatHappens)
  ]

  static func contains(_ id: UUID) -> Bool { people.contains { $0.id == id } }

  private static func person(
    _ id: String, _ name: String, _ age: Int, _ bio: String, _ distance: Double,
    _ coffee: String, _ photo: String, _ lookingFor: LookingFor
  ) -> DiscoverProfile {
    DiscoverProfile(
      id: UUID(uuidString: id)!, name: name, age: age, bio: bio, city: "Barcelona",
      distanceKm: distance, coffeePersonality: coffee, preferredPlan: "LONG_TALKS",
      preferredVibe: "CALM", coffeesPerDay: 2, favoriteCoffeeMoment: "AFTERWORK",
      lookingFor: lookingFor, coffeePreferences: [coffee.uppercased()],
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
  @State private var firstCardArrived = false
  @State private var showFilters = false
  @State private var showProfile = false
  @AppStorage("didSeeDiscoveryPhotoSwipeHint") private var didSeeSwipeHint = false
  @State private var showSwipeHint = false
  @State private var swipeHintPulse = false
  @State private var matchProgress = false
  @State private var showMyCafes = false
  var body: some View {
    GeometryReader { screen in
      let safeArea = activeWindowSafeAreaInsets
      ZStack {
        NookInteriorBackdrop().ignoresSafeArea()
        Group {
          if vm.loading && vm.people.isEmpty {
            DiscoverProfilesLoadingState()
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
                .opacity(entrance && firstCardArrived ? 1 : 0)
                .blur(radius: entrance && firstCardArrived ? 0 : 7)
                .scaleEffect(firstCardArrived ? 1 : 0.94)
                .rotationEffect(.degrees(firstCardArrived ? 0 : -2.4))
                .offset(y: firstCardArrived ? 0 : 44)

              matchingChrome(
                person, topInset: safeArea.top,
                bottomInset: safeArea.bottom,
                leadingInset: safeArea.left, trailingInset: safeArea.right)
                .opacity(entrance ? 1 : 0)
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
      entrance = false
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
        withAnimation(.easeOut(duration: 0.42)) { entrance = true }
      }
    }
    .onDisappear {
      app.tabBarHidden = false
      setLightStatusBar(false)
    }
    .task {
      if let cache = app.discoverCache {
        vm.seed(cache)
        animateFirstCardIfNeeded()
      }
      await vm.load(app.repository, showLoader: app.discoverCache == nil)
      animateFirstCardIfNeeded()
      app.cacheDiscover(vm.people)
      NookImagePrefetch.schedule(vm.people.prefix(3).flatMap { $0.photos.map(\.url) })
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
    }.sheet(isPresented: $showFilters) {
      DiscoveryFiltersView()
        .presentationDragIndicator(.hidden)
    }
      .sheet(isPresented: $showMyCafes) {
        NavigationStack { ChatsView(close: { showMyCafes = false }) }
          .presentationDetents([.large])
          .presentationContentInteraction(.scrolls)
          .presentationDragIndicator(.hidden)
          .presentationBackground(Color.white)
      }
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
      .onChange(of: vm.people) { _, people in
        photoIndex = 0
        app.cacheDiscover(people)
        NookImagePrefetch.schedule(people.prefix(3).flatMap { $0.photos.map(\.url) })
      }
  }
  private func animateFirstCardIfNeeded() {
    guard !firstCardArrived, !vm.people.isEmpty else { return }
    withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
      firstCardArrived = true
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
            expandableInfo: true, immersive: true,
          contentTopInset: topInset, contentBottomInset: bottomInset
        )
          .offset(drag).rotationEffect(.degrees(Double(drag.width / 28)))
          .overlay { photoSwipeHint(for: person) }
          .gesture(
            DragGesture(minimumDistance: 12)
              .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      profilePhotoURLs(for: person).count > 1 else { return }
                photoSwipeOffset = value.translation.height
              }
              .onEnded { value in
                guard abs(value.translation.height) > 52,
                      abs(value.translation.height) > abs(value.translation.width),
                      profilePhotoURLs(for: person).count > 1 else {
                  withAnimation(NookMotion.spring) { photoSwipeOffset = 0 }
                  return
                }
                completePhotoSwipe(
                  in: person, direction: value.translation.height < 0 ? 1 : -1,
                  cardHeight: cardHeight)
              }
          ).allowsHitTesting(vm.actingOn == nil && vm.match == nil)
      }
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
        cinematic: true)
        .frame(height: 56)

      HStack {
        ZStack(alignment: .leading) {
          purposeBadge(for: person)
            .id(person.id)
            .transition(.asymmetric(
              insertion: .move(edge: .leading).combined(with: .opacity),
              removal: .move(edge: .trailing).combined(with: .opacity)))
        }
        .animation(.easeOut(duration: 0.16), value: person.id)
        Spacer()
      }

      Spacer(minLength: 0)

      actions(person)
        .offset(drag)
        .allowsHitTesting(vm.actingOn == nil && vm.match == nil)
    }
    .padding(.top, topInset)
    .padding(.leading, leadingInset + 12)
    .padding(.trailing, trailingInset + 12)
    .padding(.bottom, bottomInset + 10)
    .overlay(alignment: .topTrailing) {
      immersiveNavigation
        .padding(.top, topInset + 8)
        .padding(.trailing, trailingInset + 8)
    }
    .overlay(alignment: .trailing) {
      nextPhotoThumbnail(for: person)
        .padding(.trailing, trailingInset + 19)
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
    if showSwipeHint && profilePhotoURLs(for: person).count > 1 {
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
    let photos = profilePhotoURLs(for: person)
    guard !photos.isEmpty else { return nil }
    return photos[min(photoIndex, photos.count - 1)]
  }

  private func adjacentPhotoURL(for person: DiscoverProfile) -> String? {
    let photos = profilePhotoURLs(for: person)
    guard photos.count > 1 else { return nil }
    let direction = photoSwipeOffset > 0 ? -1 : 1
    let index = (photoIndex + direction + photos.count) % photos.count
    return photos[index]
  }

  @ViewBuilder private func photoProgress(for person: DiscoverProfile) -> some View {
    let photos = profilePhotoURLs(for: person)
    if photos.count > 1 {
      HStack(spacing: 4) {
        ForEach(photos.indices, id: \.self) { index in
          Capsule()
            .fill(index == photoIndex ? Color.white : Color.white.opacity(0.36))
            .frame(width: index == photoIndex ? 18 : 7, height: 3)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: photoIndex)
      .accessibilityLabel("Foto \(photoIndex + 1) de \(photos.count)")
    }
  }

  @ViewBuilder private func nextPhotoThumbnail(for person: DiscoverProfile) -> some View {
    let photos = profilePhotoURLs(for: person)
    if photos.count > 1 {
      let nextIndex = (photoIndex + 1) % photos.count
      VStack(spacing: 7) {
        VStack(spacing: -10) {
          ProfileImage(url: photos[min(photoIndex, photos.count - 1)], name: person.name)
            .frame(width: 44, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(0.72)
            .scaleEffect(0.92)
          ProfileImage(url: photos[nextIndex], name: person.name)
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
    let photos = profilePhotoURLs(for: person)
    guard photos.count > 1 else { return }
    dismissSwipeHint()
    Haptics.selection()
    withAnimation(.easeOut(duration: 0.24)) {
      photoSwipeOffset = CGFloat(-direction) * max(cardHeight, 500)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
      photoIndex = (photoIndex + direction + photos.count) % photos.count
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { photoSwipeOffset = 0 }
    }
  }
  private func profilePhotoURLs(for person: DiscoverProfile) -> [String] {
    let urls = person.photos.map(\.url)
    guard urls.count == 1, let url = urls.first,
          let range = url.range(of: "/api/v1/demo/photos/", options: .backwards) else {
      return urls
    }
    let prefix = String(url[..<range.upperBound])
    return (0..<4).map { prefix + String($0) }
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
    VStack(alignment: .trailing, spacing: 10) {
      immersiveProfileButton
      immersiveActionButton(icon: "slider.horizontal.3", label: "Filtros") {
        showFilters = true
      }
      immersiveActionButton(icon: "cup.and.saucer.fill", label: "Mis cafés") {
        showMyCafes = true
      }
      immersiveNavigationButton(
        icon: "bubble.left.and.bubble.right.fill", label: "Chats", destination: 2)
    }
    // The icon column shares the same visual axis as the 56pt photo stack below.
    .padding(.trailing, 11)
  }

  private var immersiveProfileButton: some View {
    Button {
      Haptics.selection()
      showProfile = true
    } label: {
      Group {
        if let photoURL = ownProfilePhotoURL {
          ProfileImage(url: photoURL, name: app.me?.name ?? "N", faceAware: false)
        } else {
          Image(systemName: "person.crop.circle")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.38))
        }
      }
      .frame(width: 40, height: 40)
      .clipShape(Circle())
      .overlay(
        Circle()
          .strokeBorder(NookColors.nookGold, lineWidth: 1.5)
      )
      .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Mi perfil")
  }

  private var ownProfilePhotoURL: String? {
    app.me?.photos.sorted {
      if ($0.isPrimary == true) != ($1.isPrimary == true) { return $0.isPrimary == true }
      return $0.position < $1.position
    }.first?.url
  }

  private func immersiveActionButton(
    icon: String, label: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(.black.opacity(0.38), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.34), lineWidth: 1))
        .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
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
      app.selectedTab = destination
    } label: {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(.black.opacity(0.38), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.34), lineWidth: 1))
        .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
        .contentShape(Circle())
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

private struct CoffeeCalendarLoadingView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animate = false

  var body: some View {
    ZStack {
      NookColors.espresso.opacity(0.96).ignoresSafeArea()

      VStack(spacing: 18) {
        ZStack {
          Circle()
            .stroke(Color.white.opacity(0.20), lineWidth: 2)
            .frame(width: 104, height: 104)
            .scaleEffect(animate && !reduceMotion ? 1.16 : 0.94)
            .opacity(animate && !reduceMotion ? 0.12 : 0.7)

          Image(systemName: "calendar")
            .font(.system(size: 58, weight: .regular))
            .foregroundStyle(.white)

          Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .offset(y: animate && !reduceMotion ? 11 : 17)
            .scaleEffect(animate && !reduceMotion ? 1.08 : 0.92)
        }

        VStack(spacing: 5) {
          Text("PREPARANDO TU AGENDA")
            .font(.system(size: 10, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.68))
          Text("Buscando tus cafés…")
            .font(NookTypography.business(23, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 0.34).repeatForever(autoreverses: true)) {
        animate = true
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Cargando tus citas de café")
  }
}

private struct DiscoverProfilesLoadingState: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = false
  @State private var rotation = false
  @State private var profilesDrift = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [NookColors.primaryCoffeePressed, NookColors.warmBlack],
        startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()

      GeometryReader { proxy in
        let assets = ["NookDemoProfile", "NookDemoProfile3", "NookDemoProfile2", "NookDemoProfile4"]
        let names = ["Laura", "Clara", "Marc", "Kenji", "Elena", "Nora", "Julia", "Aina"]
        HStack(spacing: 9) {
          ForEach(0..<3, id: \.self) { column in
            VStack(spacing: 9) {
              ForEach(0..<6, id: \.self) { row in
                let index = row * 3 + column
                loadingProfile(
                  assets[index % assets.count],
                  name: names[index % names.count], age: 25 + (index * 3) % 9)
              }
            }
            .offset(
              y: CGFloat(column - 1) * 54
                + CGFloat(profilesDrift
                  ? (column.isMultiple(of: 2) ? -20 : 20)
                  : (column.isMultiple(of: 2) ? 20 : -20)))
          }
        }
        .frame(width: proxy.size.width * 1.14)
        .rotationEffect(.degrees(-3.5))
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      }
      .ignoresSafeArea()

      Color.black.opacity(0.46).ignoresSafeArea()

      Circle()
        .fill(NookColors.mocha.opacity(0.3))
        .frame(width: 330, height: 330)
        .blur(radius: 70)
        .scaleEffect(pulse ? 1.12 : 0.88)

      VStack(spacing: 26) {
        ZStack {
          Circle()
            .stroke(NookColors.caramelSoft.opacity(0.18), lineWidth: 1)
            .frame(width: 126, height: 126)
            .scaleEffect(pulse ? 1.12 : 0.94)
            .opacity(pulse ? 0.18 : 0.78)

          Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(
              AngularGradient(
                colors: [.clear, NookColors.caramelSoft, NookColors.nookGold, .clear],
                center: .center),
              style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 110, height: 110)
            .rotationEffect(.degrees(rotation ? 360 : 0))

          NookCoffeeLogo(size: 84, animated: true)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }

        VStack(spacing: 9) {
          Text("Buscando perfiles")
            .font(NookTypography.business(27, weight: .bold))
            .foregroundStyle(.white)
          Text("Preparando personas que encajan contigo")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))

          HStack(spacing: 7) {
            ForEach(0..<3) { index in
              Circle()
                .fill(NookColors.caramelSoft)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1 : 0.55)
                .opacity(pulse ? 1 : 0.4)
                .animation(
                  reduceMotion ? nil : .easeInOut(duration: 0.75)
                    .repeatForever(autoreverses: true).delay(Double(index) * 0.16),
                  value: pulse)
            }
          }
          .padding(.top, 5)
        }
      }
    }
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
        pulse = true
      }
      withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
        rotation = true
      }
      withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
        profilesDrift = true
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Buscando perfiles")
  }

  private func loadingProfile(_ asset: String, name: String, age: Int) -> some View {
    ZStack(alignment: .bottomLeading) {
      Image(asset)
        .resizable()
        .scaledToFill()
        .frame(width: 142, height: 196)
        .clipped()
      LinearGradient(
        colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
      Text("\(name), \(age)")
        .font(NookTypography.business(16, weight: .bold))
        .foregroundStyle(.white)
        .padding(12)
    }
    .frame(width: 142, height: 196)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.34), radius: 16, y: 9)
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
    uiView.window?.overrideUserInterfaceStyle = .unspecified
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
  var expandableInfo = false
  var immersive = false
  var editorialPhotoEffect = false
  var showImmersiveIntent = false
  var contentTopInset: CGFloat = 0
  var contentBottomInset: CGFloat = 0
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var infoExpanded = false
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        if let nextPhotoURL {
          ProfileImage(url: nextPhotoURL, name: person.name)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .modifier(ProfileCardPhotoEffect(enabled: editorialPhotoEffect))
        }
        ProfileImage(url: photoURL ?? person.photos.first?.url, name: person.name)
          .frame(width: proxy.size.width, height: proxy.size.height)
          .modifier(ProfileCardPhotoEffect(enabled: editorialPhotoEffect))
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
          if onNameTap != nil || expandableInfo {
            Button {
              Haptics.selection()
              if expandableInfo {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                  infoExpanded.toggle()
                }
              } else {
                onNameTap?()
              }
            } label: {
              profileName
            }
            .buttonStyle(.plain)
            .accessibilityLabel(infoExpanded ? "Ocultar información de \(person.name)" : "Ver información de \(person.name)")
          } else {
            profileName
          }
          if expandableInfo && infoExpanded {
            expandedProfileInfo
              .transition(.opacity.combined(with: .move(edge: .top)))
          }
          if !immersive || showImmersiveIntent {
            Text(person.intent?.subcategoryName ?? person.lookingFor.profileTitle)
              .font(NookTypography.business(13, weight: .bold))
              .textCase(.uppercase)
              .tracking(0.7)
              .foregroundStyle(.white)
              .lineLimit(2)
          }
          if !infoExpanded {
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
      if onNameTap != nil || expandableInfo {
        Image(systemName: infoExpanded ? "xmark.circle.fill" : "info.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white.opacity(0.88))
      }
    }
    .font(NookTypography.business(28, weight: .bold))
    .tracking(-0.45)
    .contentShape(Rectangle())
  }

  private var expandedProfileInfo: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(person.bio)
        .font(NookTypography.business(15, weight: .medium))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        infoChip(icon: "location.fill", text: "\(person.distanceKm.formatted()) km")
        infoChip(
          icon: "cup.and.saucer.fill",
          text: person.coffeePersonality ?? "Buena conversación")
      }
      HStack(spacing: 8) {
        infoChip(
          icon: "sparkles",
          text: person.intent?.subcategoryName ?? person.lookingFor.profileTitle)
        if let preference = person.coffeePreferences.first {
          infoChip(icon: "heart.fill", text: preference)
        }
      }
    }
    .foregroundStyle(.white)
    .padding(.top, 2).padding(.bottom, 3)
  }

  private func infoChip(icon: String, text: String) -> some View {
    Label(text, systemImage: icon)
      .font(.system(size: 11, weight: .semibold, design: .default))
      .lineLimit(1).minimumScaleFactor(0.72)
      .padding(.horizontal, 10).frame(height: 30)
      .background(.white.opacity(0.13), in: Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
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
        Color.white.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 0) {
            filtersHeroHeader

            VStack(alignment: .leading, spacing: 14) {

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
              .shadow(color: NookColors.espresso.opacity(0.18), radius: 10, y: 5)

              Button("Restablecer filtros") { reset() }
                .font(.subheadline.weight(.semibold)).foregroundStyle(NookColors.warmGray)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 28)
          }
        }
        .ignoresSafeArea(edges: .top)
      }.background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
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
    .background(Color.white.ignoresSafeArea())
    .preferredColorScheme(.light)
  }
  private var filtersHeroHeader: some View {
    ZStack(alignment: .bottomLeading) {
      filtersHeroImage

      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.08), location: 0),
          .init(color: .clear, location: 0.34),
          .init(color: NookColors.espresso.opacity(0.76), location: 1),
        ],
        startPoint: .top, endPoint: .bottom)

      VStack(alignment: .leading, spacing: 5) {
        Label("TU PRÓXIMO CAFÉ", systemImage: "slider.horizontal.3")
          .font(.system(size: 10, weight: .bold))
          .tracking(1.35)
          .foregroundStyle(.white.opacity(0.78))
        Text("Filtros")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .tracking(-1)
          .foregroundStyle(.white)
        Text("Elige lo importante y deja espacio para la sorpresa.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white.opacity(0.86))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 20)
      .shadow(color: .black.opacity(0.22), radius: 8, y: 2)

      filtersSheetGrabber
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
    .frame(height: 218)
    .background(NookColors.espresso)
  }
  private var filtersSheetGrabber: some View {
    Capsule()
      .fill(Color.white.opacity(0.96))
      .frame(width: 38, height: 5)
      .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
      .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
      .accessibilityHidden(true)
  }
  private var filtersHeroImage: some View {
    GeometryReader { proxy in
      let imageHeight = proxy.size.width * 1812 / 868
      let overflow = max(0, imageHeight - proxy.size.height)
      Image("NookMyCafesHero")
        .resizable()
        .frame(width: proxy.size.width, height: imageHeight)
        .offset(y: -overflow * 0.72)
        .accessibilityHidden(true)
    }
    .clipped()
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
    }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(NookColors.espresso.opacity(0.10), lineWidth: 0.8))
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
        .background(selected ? NookColors.espresso : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.clear : NookColors.espresso.opacity(0.14)))
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
  @AppStorage("profileCardPhotoEffectEnabled") private var cardPhotoEffect = false
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
  @State private var heroPhotoIndex = 0
  @State private var showProfilePreview = false
  var body: some View {
    GeometryReader { geometry in
      let heroHeight = max(360, min(430, geometry.size.height * 0.5))
      ZStack(alignment: .topTrailing) {
        Color.white.ignoresSafeArea()

      ScrollView {
        VStack(spacing: 0) {
            profileHero(height: heroHeight)

            VStack(alignment: .leading, spacing: 0) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.me?.name ?? "Tu perfil")
                  .font(.system(size: 30, weight: .bold, design: .rounded))
                  .tracking(-0.9)
                  .foregroundStyle(NookColors.espresso)
                Text("\(app.me?.age ?? 18)")
                  .font(.system(size: 25, weight: .medium, design: .rounded))
                  .foregroundStyle(NookColors.warmGray)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                  Circle().fill(visible ? NookColors.mocha : NookColors.warmGray).frame(width: 7, height: 7)
                  Text(visible ? "VISIBLE" : "EN PAUSA")
                    .font(.system(size: 10, weight: .bold)).tracking(1.1)
                }
                .foregroundStyle(NookColors.espresso.opacity(0.66))
              }

              Label(app.me?.city ?? "Añade tu ciudad", systemImage: "location")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NookColors.warmGray)
                .padding(.top, 7)

              Button {
                Haptics.selection()
                showProfilePreview = true
              } label: {
                Label("Vista previa de mi perfil", systemImage: "eye")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(NookColors.espresso)
                  .padding(.horizontal, 14)
                  .frame(height: 38)
                  .background(NookColors.offWhite, in: Capsule())
                  .overlay(Capsule().stroke(NookColors.espresso.opacity(0.08), lineWidth: 0.8))
              }
              .buttonStyle(.plain)
              .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
              Toggle(isOn: $visible) {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Aparecer en Descubrir")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NookColors.espresso)
                  Text(visible ? "Otras personas pueden encontrar tu perfil" : "Tu perfil está temporalmente oculto")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NookColors.warmGray)
                }
              }
              .tint(NookColors.mocha)
            }
            .profileFieldSurface()
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 16) {
              profileSectionTitle("Fotos", detail: "\(app.me?.photos.count ?? 0) de 8")
              Toggle(isOn: $cardPhotoEffect) {
                HStack(spacing: 12) {
                  Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(cardPhotoEffect ? NookColors.nookGold : NookColors.warmGray)
                    .frame(width: 34, height: 34)
                    .background(
                      cardPhotoEffect ? NookColors.espresso : NookColors.espresso.opacity(0.055),
                      in: Circle())
                  VStack(alignment: .leading, spacing: 3) {
                    Text("Retrato editorial Nook")
                      .font(.system(size: 15, weight: .semibold))
                      .foregroundStyle(NookColors.espresso)
                    Text(cardPhotoEffect ? "Luz cálida y contraste de las fotos demo" : "Mantener el aspecto original")
                      .font(.system(size: 12))
                      .foregroundStyle(NookColors.warmGray)
                  }
                }
              }
              .tint(NookColors.mocha)
              .profileFieldSurface(insets: 13)
              .animation(.easeInOut(duration: 0.22), value: cardPhotoEffect)

              ScrollView(.horizontal) {
                HStack(spacing: 10) {
                  ForEach(orderedPhotos) { photo in
                    ZStack(alignment: .topTrailing) {
                      ProfileImage(url: photo.url, name: app.me?.name ?? "N")
                        .frame(width: 92, height: 122)
                        .modifier(ProfileCardPhotoEffect(enabled: cardPhotoEffect))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                          if photo.isPrimary == true {
                            Text("PRINCIPAL")
                              .font(.system(size: 8, weight: .bold)).tracking(0.8)
                              .foregroundStyle(.white)
                              .padding(.horizontal, 8).frame(height: 22)
                              .background(.black.opacity(0.48), in: Capsule()).padding(7)
                          }
                        }
                      Menu {
                        if photo.isPrimary != true {
                          Button("Usar como principal", systemImage: "star.fill") { Task { await makePrimary(photo.id) } }
                        }
                        Button("Mover a la izquierda", systemImage: "arrow.left") { Task { await move(photo.id, offset: -1) } }
                          .disabled(orderedPhotos.first?.id == photo.id)
                        Button("Mover a la derecha", systemImage: "arrow.right") { Task { await move(photo.id, offset: 1) } }
                          .disabled(orderedPhotos.last?.id == photo.id)
                        Button("Eliminar foto", systemImage: "trash", role: .destructive) { photoToDelete = photo }
                      } label: {
                        Image(systemName: "ellipsis")
                          .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                          .frame(width: 30, height: 30).background(.black.opacity(0.42), in: Circle()).padding(6)
                      }.disabled(uploading || photoOperation != nil)
                      if photoOperation == photo.id {
                        ProgressView().tint(.white).frame(width: 92, height: 122)
                          .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                      }
                    }
                  }
                  if (app.me?.photos.count ?? 0) < 8 {
                    PhotosPicker(
                      selection: $photoItems,
                      maxSelectionCount: max(1, 8 - (app.me?.photos.count ?? 0)), matching: .images
                    ) {
                      VStack(spacing: 9) {
                        Image(systemName: uploading ? "hourglass" : "plus")
                          .font(.system(size: 18, weight: .medium))
                        Text(uploading ? "Subiendo" : "Añadir")
                          .font(.system(size: 12, weight: .semibold))
                      }
                      .frame(width: 92, height: 120)
                      .foregroundStyle(NookColors.espresso)
                      .background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                      .overlay(RoundedRectangle(cornerRadius: 14).stroke(NookColors.espresso.opacity(0.08)))
                    }.disabled(uploading)
                  }
                }
              }.scrollIndicators(.hidden)
            }.profileSection()

            VStack(alignment: .leading, spacing: 16) {
              profileSectionTitle("Datos del perfil")
              HStack(spacing: 12) {
                Image(systemName: "location").frame(width: 20).foregroundStyle(NookColors.warmGray)
                TextField("Ciudad o pueblo", text: $city)
                  .font(.system(size: 16, weight: .medium))
              }.profileFieldSurface()
              Text("Solo mostramos una ubicación aproximada.")
                .font(.system(size: 12, weight: .regular)).foregroundStyle(NookColors.warmGray)
            }.profileSection()

            VStack(alignment: .leading, spacing: 14) {
              profileSectionTitle("Sobre ti", detail: "\(bio.count) / 500")
              TextEditor(text: $bio)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 116)
                .profileFieldSurface(insets: 14)
            }.profileSection()

            VStack(alignment: .leading, spacing: 16) {
              profileSectionTitle("Qué te apetece")
              Menu {
                ForEach(LookingFor.registrationChoices) { intent in
                  Button(intent.title) { withAnimation(NookMotion.spring) { looking = intent } }
                }
              } label: {
                HStack(spacing: 13) {
                  Image(systemName: looking.icon)
                    .font(.system(size: 16, weight: .semibold)).frame(width: 24)
                    .foregroundStyle(NookColors.mocha)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(looking.profileTitle).font(.system(size: 16, weight: .semibold))
                    Text(looking.detail).font(.system(size: 12)).foregroundStyle(NookColors.warmGray).lineLimit(2)
                  }
                  Spacer(minLength: 8)
                  Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(NookColors.warmGray)
                }.foregroundStyle(NookColors.espresso).profileFieldSurface()
              }
              if let currentIntent {
                NookIntentBadge(intent: currentIntent, prominent: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }.profileSection()

            VStack(alignment: .leading, spacing: 16) {
              profileSectionTitle("Tu forma de tomar café")
              VStack(spacing: 0) {
                profileMenu("cup.and.saucer", coffeePersonality, values: [
                  ("Solo", "Solo"), ("Cortado", "Cortado"), ("Café con leche", "Café con leche"),
                  ("Iced coffee", "Iced coffee"), ("Matcha", "Matcha"), ("Té", "Té")
                ]) { coffeePersonality = $0 }
                profileHairline()
                profileMenu("sparkles", vibeCopy(preferredVibe), values: [
                  ("CALM", "Sitios tranquilos"), ("SOCIAL", "Con ambiente"), ("LIVELY", "Sitios animados")
                ]) { preferredVibe = $0 }
                profileHairline()
                profileMenu("clock", momentCopy(favoriteMoment), values: [
                  ("MORNING", "Por la mañana"), ("MIDDAY", "Al mediodía"), ("AFTERWORK", "Afterwork"), ("EVENING", "Por la tarde")
                ]) { favoriteMoment = $0 }
                profileHairline()
                profileMenu("figure.walk", planCopy(preferredPlan), values: [
                  ("QUICK", "Café rápido"), ("LONG_TALKS", "Sin prisas"), ("WALK", "Café y paseo"), ("IMPROVISE", "Improvisar")
                ]) { preferredPlan = $0 }
              }.profileFieldSurface(insets: 0)
              if let preferences = app.me?.coffeePreferences, !preferences.isEmpty {
                HStack(spacing: 7) {
                  ForEach(preferences.prefix(3), id: \.self) { value in
                    Text(coffeeCopy(value)).font(.system(size: 11, weight: .semibold))
                      .padding(.horizontal, 10).padding(.vertical, 7)
                      .background(NookColors.offWhite, in: Capsule())
                  }
                }
              }
            }.profileSection()

            VStack(alignment: .leading, spacing: 16) {
              profileSectionTitle("Preferencias")
              VStack(spacing: 0) {
                Toggle(isOn: $sounds) {
                  Label("Sonidos de café", systemImage: "speaker.wave.2")
                    .font(.system(size: 15, weight: .medium))
                }.tint(NookColors.mocha).padding(.vertical, 4)
                profileHairline()
                HStack(alignment: .top, spacing: 12) {
                  Image(systemName: "location.slash").frame(width: 20).foregroundStyle(NookColors.warmGray)
                  Text("Tu ubicación exacta nunca aparece en tu perfil.")
                    .font(.system(size: 13)).foregroundStyle(NookColors.warmGray)
                  Spacer()
                }.padding(.vertical, 5)
              }.profileFieldSurface()
            }.profileSection()

            Button { saveProfile() } label: {
              HStack(spacing: 9) {
                if saving { ProgressView().tint(.white).controlSize(.small) }
                Image(systemName: saved ? "checkmark" : "arrow.down")
                Text(saved ? "Guardado" : "Guardar cambios")
              }
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
              .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain).disabled(saving)
            .padding(.horizontal, 20).padding(.top, 34)

            Button("Cerrar sesión", role: .destructive) { Task { await app.logout() } }
              .font(.system(size: 14, weight: .medium))
              .padding(.top, 20)
              .padding(.bottom, max(28, geometry.safeAreaInsets.bottom + 16))
          }
          .frame(maxWidth: .infinity, alignment: .top)
      }
      .ignoresSafeArea(edges: .top)
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .defaultScrollAnchor(.top)
      .background(Color.white)
      .transaction { transaction in transaction.animation = nil }

        profileSheetGrabber
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
          .allowsHitTesting(false)
      }
    }
    .alert("No hemos podido guardar", isPresented: Binding(
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
      .onChange(of: orderedPhotos.map(\.id)) { _, photos in
        heroPhotoIndex = min(heroPhotoIndex, max(0, photos.count - 1))
      }
      .onChange(of: bio) { _, value in if value.count > 500 { bio = String(value.prefix(500)) } }
      .onChange(of: sounds) { _, value in NookSoundManager.shared.enabled = value }
      .toolbar(.hidden, for: .navigationBar)
      .preferredColorScheme(.light)
      .sheet(isPresented: $showProfilePreview) {
        ProfilePreviewSheet(
          person: previewProfile,
          viewer: app.me,
          editorialPhotoEffect: cardPhotoEffect)
          .presentationDetents([.large])
          .presentationContentInteraction(.scrolls)
          .presentationDragIndicator(.hidden)
          .presentationBackground(NookColors.warmBlack)
      }
  }
  private var profileSheetGrabber: some View {
    Capsule()
      .fill(Color.white.opacity(0.96))
      .frame(width: 38, height: 5)
      .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
      .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
      .accessibilityHidden(true)
  }
  private func profileHero(height: CGFloat) -> some View {
    ZStack {
      if orderedPhotos.isEmpty {
        ProfileImage(
          url: nil, name: app.me?.name ?? "N", alignment: .top, faceAware: false
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)

        PhotosPicker(selection: $photoItems, maxSelectionCount: 1, matching: .images) {
          Label(uploading ? "Subiendo…" : "Añadir foto", systemImage: "camera")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 42)
            .background(.black.opacity(0.34), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.7))
        }.disabled(uploading)
      } else {
        TabView(selection: $heroPhotoIndex) {
          ForEach(Array(orderedPhotos.enumerated()), id: \.element.id) { index, photo in
            ProfileImage(
              url: photo.url, name: app.me?.name ?? "N", alignment: .top, faceAware: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .modifier(ProfileCardPhotoEffect(enabled: cardPhotoEffect))
            .clipped()
            .tag(index)
            .accessibilityLabel("Foto \(index + 1) de \(orderedPhotos.count)")
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height)

        if orderedPhotos.count > 1 {
          HStack(spacing: 5) {
            ForEach(orderedPhotos.indices, id: \.self) { index in
              Capsule()
                .fill(.white.opacity(index == heroPhotoIndex ? 0.96 : 0.42))
                .frame(width: index == heroPhotoIndex ? 18 : 6, height: 6)
            }
          }
          .padding(.horizontal, 10).frame(height: 24)
          .background(.black.opacity(0.20), in: Capsule())
          .padding(.bottom, 12)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Foto principal del perfil")
  }
  private func profileSectionTitle(_ title: String, detail: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .tracking(-0.25)
        .foregroundStyle(NookColors.espresso)
      Spacer()
      if let detail {
        Text(detail)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(NookColors.warmGray)
      }
    }
  }
  private func profileHairline() -> some View {
    Rectangle()
      .fill(NookColors.espresso.opacity(0.07))
      .frame(height: 0.7)
      .padding(.leading, 36)
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
  private var previewProfile: DiscoverProfile {
    DiscoverProfile(
      id: app.me?.id ?? UUID(),
      name: app.me?.name ?? "Tu perfil",
      age: app.me?.age ?? 18,
      bio: bio.isEmpty ? "Añade una bio para contar algo sobre ti." : bio,
      city: city.isEmpty ? app.me?.city : city,
      distanceKm: 0,
      coffeePersonality: coffeePersonality,
      preferredPlan: preferredPlan,
      preferredVibe: preferredVibe,
      coffeesPerDay: app.me?.coffeesPerDay,
      favoriteCoffeeMoment: favoriteMoment,
      lookingFor: looking,
      coffeePreferences: app.me?.coffeePreferences ?? [],
      photos: orderedPhotos,
      intent: currentIntent)
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
        Image(systemName: icon).frame(width: 22).foregroundStyle(NookColors.warmGray)
        Text(text).font(.system(size: 15, weight: .medium, design: .default))
        Spacer()
        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(NookColors.warmGray)
      }
      .foregroundStyle(NookColors.espresso)
      .frame(minHeight: 52)
      .padding(.horizontal, 16)
      .contentShape(Rectangle())
    }
  }
  private func vibeCopy(_ value: String?) -> String { value == "CALM" ? "Sitios tranquilos" : value == "LIVELY" ? "Sitios animados" : "Con ambiente" }
  private func momentCopy(_ value: String?) -> String { value == "MORNING" ? "Por la mañana" : value == "MIDDAY" ? "Al mediodía" : value == "AFTERWORK" ? "Afterwork" : "Por la tarde" }
  private func planCopy(_ value: String?) -> String { value == "WALK" ? "Café y paseo" : value == "QUICK" ? "Café rápido" : value == "LONG_TALKS" ? "Sin prisas" : "Improvisar" }
  private func coffeeCopy(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
}

private struct ProfilePreviewSheet: View {
  let person: DiscoverProfile
  let viewer: Me?
  let editorialPhotoEffect: Bool
  @State private var photoIndex = 0

  var body: some View {
    GeometryReader { proxy in
      let windowInsets = activeWindowSafeAreaInsets
      let safeArea = EdgeInsets(
        top: windowInsets.top, leading: windowInsets.left,
        bottom: windowInsets.bottom, trailing: windowInsets.right)
      ZStack {
        NookColors.warmBlack.ignoresSafeArea()

        if person.photos.isEmpty {
          previewCard(photoURL: nil, height: proxy.size.height, safeArea: safeArea)
        } else {
          TabView(selection: $photoIndex) {
            ForEach(Array(person.photos.enumerated()), id: \.element.id) { index, photo in
              previewCard(
                photoURL: photo.url, height: proxy.size.height, safeArea: safeArea)
                .tag(index)
            }
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
          .ignoresSafeArea()
        }

        previewChrome(safeArea: safeArea)
          .allowsHitTesting(false)

        Capsule()
          .fill(Color.white.opacity(0.96))
          .frame(width: 38, height: 5)
          .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
          .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
          .padding(.top, 8)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .allowsHitTesting(false)

        HStack(spacing: 40) {
          CircleAction(icon: "xmark", size: 48, action: {})
          ZStack {
            Circle().fill(NookColors.offWhite).frame(width: 70, height: 70)
              .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            NookCoffeeLogo(size: 62, animated: false).clipShape(Circle())
          }
        }
        .allowsHitTesting(false)
        .opacity(0.94)
        .padding(.bottom, safeArea.bottom + 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .contain)
  }

  private func previewChrome(safeArea: EdgeInsets) -> some View {
    let topChromeLift: CGFloat = 16
    return ZStack {
      VStack(spacing: 8) {
        NookHeader(
          eyebrow: "NOOK", title: "Un café con…", branded: true, cinematic: true)
          .frame(height: 56)

        HStack {
          Label(person.lookingFor.profileTitle, systemImage: person.lookingFor.icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).frame(height: 30)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
          Spacer()
        }

        Spacer()
      }
      .padding(.top, max(0, safeArea.top - topChromeLift))
      .padding(.leading, safeArea.leading + 12)
      .padding(.trailing, safeArea.trailing + 12)
      .padding(.bottom, safeArea.bottom + 10)

      VStack(alignment: .trailing, spacing: 10) {
        previewProfileButton
        previewSideButton(icon: "slider.horizontal.3")
        previewSideButton(icon: "cup.and.saucer.fill")
        previewSideButton(icon: "bubble.left.and.bubble.right.fill")
      }
      .padding(.top, max(0, safeArea.top + 8 - topChromeLift))
      .padding(.trailing, safeArea.trailing + 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

      if person.photos.count > 1 {
        VStack(spacing: -9) {
          ForEach(person.photos.indices, id: \.self) { index in
            ProfileImage(url: person.photos[index].url, name: person.name, faceAware: false)
              .frame(width: index == photoIndex ? 48 : 38, height: index == photoIndex ? 62 : 48)
              .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .stroke(index == photoIndex ? Color.white : Color.white.opacity(0.42), lineWidth: index == photoIndex ? 2 : 1)
              }
              .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
              .zIndex(index == photoIndex ? 2 : 1)
          }
        }
        .padding(.trailing, safeArea.trailing + 19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
      }
    }
  }

  private var previewProfileButton: some View {
    Group {
      if let photo = viewer?.photos.first {
        ProfileImage(url: photo.url, name: viewer?.name ?? "N", faceAware: false)
      } else {
        Image(systemName: "person.crop.circle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
          .background(.black.opacity(0.38))
      }
    }
    .frame(width: 40, height: 40)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(NookColors.nookGold, lineWidth: 1.5))
    .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
  }

  private func previewSideButton(icon: String) -> some View {
    Image(systemName: icon)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 40, height: 40)
      .background(.black.opacity(0.38), in: Circle())
      .overlay(Circle().stroke(Color.white.opacity(0.34), lineWidth: 1))
      .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
  }

  private func previewCard(
    photoURL: String?, height: CGFloat, safeArea: EdgeInsets
  ) -> some View {
    NookProfileCard(
      person: person,
      viewer: viewer,
      height: height,
      photoURL: photoURL,
      expandableInfo: false,
      immersive: true,
      editorialPhotoEffect: editorialPhotoEffect,
      showImmersiveIntent: true,
      contentTopInset: safeArea.top,
      contentBottomInset: safeArea.bottom)
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }

  private var activeWindowSafeAreaInsets: UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
      ?? scenes.flatMap(\.windows).first
    return window?.safeAreaInsets ?? .zero
  }
}

private struct ProfileCardPhotoEffect: ViewModifier {
  let enabled: Bool

  func body(content: Content) -> some View {
    content
      .saturation(enabled ? 0.92 : 1)
      .contrast(enabled ? 1.11 : 1)
      .brightness(enabled ? 0.012 : 0)
      .hueRotation(.degrees(enabled ? -2.5 : 0))
      .overlay {
        if enabled {
          ZStack {
            Color(red: 0.93, green: 0.55, blue: 0.25)
              .opacity(0.10)
              .blendMode(.softLight)
            RadialGradient(
              stops: [
                .init(color: .clear, location: 0.46),
                .init(color: profileCardDarkCoffee.opacity(0.08), location: 0.73),
                .init(color: profileCardDarkCoffee.opacity(0.27), location: 1),
              ],
              center: .center, startRadius: 10, endRadius: 520)
              .blendMode(.multiply)
          }
          .allowsHitTesting(false)
        }
      }
      .animation(.easeInOut(duration: 0.28), value: enabled)
  }

  private var profileCardDarkCoffee: Color {
    Color(red: 0.16, green: 0.075, blue: 0.035)
  }
}

private extension View {
  func profileSection() -> some View {
    self
      .padding(.horizontal, 20)
      .padding(.top, 30)
  }

  func profileFieldSurface(insets: CGFloat = 16) -> some View {
    self
      .padding(insets)
      .background(NookColors.offWhite.opacity(0.88), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(NookColors.espresso.opacity(0.055), lineWidth: 0.7)
      )
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
