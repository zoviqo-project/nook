import MapKit
import SwiftUI

@MainActor final class LocationSearchService: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
  @Published var suggestions: [MKLocalSearchCompletion] = []
  private let completer = MKLocalSearchCompleter()
  override init() {
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest]
  }
  func update(_ query: String) {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { suggestions = []; return }
    completer.queryFragment = query
  }
  func resolve(_ completion: MKLocalSearchCompletion) async throws -> (GeoPoint, String) {
    let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
    guard let item = response.mapItems.first else { throw URLError(.cannotFindHost) }
    let name = item.name ?? completion.title
    return (GeoPoint(item.placemark.coordinate), name)
  }
  func resolve(query: String) async throws -> (GeoPoint, String) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    let response = try await MKLocalSearch(request: request).start()
    guard let item = response.mapItems.first else { throw URLError(.cannotFindHost) }
    return (GeoPoint(item.placemark.coordinate), item.name ?? query)
  }
  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { suggestions = Array(completer.results.prefix(5)) }
  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { suggestions = [] }
}

@MainActor final class ShopsVM: ObservableObject {
  enum State: Equatable {
    case idle, requestingLocation, loading, loaded, empty, error(String)
  }
  @Published var shops: [CoffeeShop] = []
  @Published var matches: [Match] = []
  @Published private(set) var state: State = .idle
  @Published var meetingArea: String?
  @Published var mapLoading = false
  @Published private(set) var origin: CafeSearchOrigin?
  @Published var selectedCafe: CoffeeShop?
  @Published var radiusKm = 2.0
  private var searchTask: Task<Void, Never>?

  var searchPoint: GeoPoint? { origin?.point }
  var loading: Bool { state == .loading || state == .requestingLocation }
  var error: String? { if case .error(let message) = state { message } else { nil } }

  func beginLocationRequest() { if shops.isEmpty { state = .requestingLocation } }
  func failLocation(_ message: String) { if shops.isEmpty { state = .error(message) } }

  func prepare(_ repo: any NookRepository) async {
    if matches.isEmpty { matches = (try? await repo.matches()) ?? [] }
  }

  func useCurrentLocation(_ location: CLLocation, repo: any NookRepository) async {
    do {
      try await repo.updateLocation(latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy,
        capturedAt: location.timestamp)
    } catch {
      state = .error("No hemos podido guardar tu ubicación actual. Comprueba la conexión y reinténtalo.")
      return
    }
    let point = GeoPoint(location.coordinate)
    origin = .currentLocation(point)
    meetingArea = await locality(for: point.coordinate, fallback: "Tu ubicación")
    await search(repo, showMainLoader: shops.isEmpty)
  }

  func useMidpoint(
    matchID: UUID, currentLocation: CLLocation, repo: any NookRepository
  ) async {
    await prepare(repo)
    do {
      try await repo.updateLocation(latitude: currentLocation.coordinate.latitude,
        longitude: currentLocation.coordinate.longitude, accuracy: currentLocation.horizontalAccuracy,
        capturedAt: currentLocation.timestamp)
    } catch {
      state = .error("No hemos podido guardar tu ubicación actual. Comprueba la conexión y reinténtalo.")
      return
    }
    let point: GeoPoint
    do {
      point = try await repo.meetingPoint(matchID: matchID)
    } catch {
      state = .error("Aún no podemos calcular vuestro punto medio con ubicaciones reales. Reinténtalo cuando ambos tengáis ubicación disponible.")
      return
    }
    origin = .midpoint(point)
    meetingArea = await locality(for: point.coordinate, fallback: "Punto medio")
    #if DEBUG
      print("[NOOK MIDPOINT] calculated=true")
    #endif
    await search(repo, showMainLoader: shops.isEmpty)
  }

  func useSelectedLocation(_ point: GeoPoint, name: String, repo: any NookRepository) async {
    origin = .selectedLocation(point, name: name)
    meetingArea = name
    await search(repo, showMainLoader: shops.isEmpty)
  }

  func searchVisibleArea(_ point: GeoPoint, repo: any NookRepository) async {
    origin = .selectedLocation(point, name: "Esta zona")
    meetingArea = await locality(for: point.coordinate, fallback: "Esta zona")
    await search(repo)
  }

  func setRadius(_ value: Double, repo: any NookRepository) {
    radiusKm = value
    searchTask?.cancel()
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      await search(repo)
    }
  }

  func retry(_ repo: any NookRepository) async { await search(repo, showMainLoader: shops.isEmpty) }

  private func search(_ repo: any NookRepository, showMainLoader: Bool = false) async {
    guard let origin else {
      state = .error("Necesitamos una ubicación válida para buscar cafeterías.")
      return
    }
    if showMainLoader || shops.isEmpty { state = .loading } else { mapLoading = true }
    defer { mapLoading = false }
    do {
      let point = origin.point
      let found = try await repo.shops(
        latitude: point.latitude, longitude: point.longitude, radiusKm: radiusKm)
      shops = found.sorted(by: usefulOrder)
      state = shops.isEmpty ? .empty : .loaded
      #if DEBUG
        print("[NOOK CAFE SEARCH] Origin: \(origin.logName) latitude=\(point.latitude) longitude=\(point.longitude) radius=\(GeographicMath.meters(fromKilometers: radiusKm))m results=\(shops.count)")
      #endif
    } catch {
      shops = []
      state = .error("No hemos podido obtener cafeterías reales. Comprueba la conexión y vuelve a intentarlo.")
    }
  }
  private func locality(for coordinate: CLLocationCoordinate2D, fallback: String?) async -> String {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    if let place = try? await CLGeocoder().reverseGeocodeLocation(location).first {
      return place.locality ?? place.subLocality ?? place.administrativeArea ?? fallback ?? "Punto medio"
    }
    return fallback ?? "Punto medio"
  }
  private func usefulOrder(_ lhs: CoffeeShop, _ rhs: CoffeeShop) -> Bool {
    let distanceBandL = Int(lhs.distanceKm / 0.5)
    let distanceBandR = Int(rhs.distanceKm / 0.5)
    if distanceBandL != distanceBandR { return distanceBandL < distanceBandR }
    if (lhs.openNow == true) != (rhs.openNow == true) { return lhs.openNow == true }
    if lhs.rating != rhs.rating { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
    return (lhs.reviewCount ?? 0) > (rhs.reviewCount ?? 0)
  }
}

struct CoffeeShopsView: View {
  @EnvironmentObject var app: AppSession
  @StateObject private var location = LocationManager()
  @StateObject private var vm = ShopsVM()
  @StateObject private var locationSearch = LocationSearchService()
  @Namespace private var namespace
  @State private var showMap = false
  @State private var selected: CoffeeShop?
  @State private var proposalShop: CoffeeShop?
  @State private var celebratedShop: CoffeeShop?
  @State private var appeared = false
  @State private var searching = true
  @State private var showAreaPicker = false
  @State private var customArea = ""
  @State private var searchTitle = "Buscando vuestro\npunto medio"
  @State private var searchLabel: String?
  @State private var otherPlaceMode = false
  @State private var locationHandled = false
  @State private var placeQuery = ""
  @State private var placeFilter: PlaceFilter = .all
  @State private var resultsExpanded = true
  @FocusState private var placeSearchFocused: Bool

  private enum PlaceFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case open = "Abiertos"
    case topRated = "Mejor valorados"
    case nearby = "A menos de 1 km"
    var id: String { rawValue }
  }
  var body: some View {
    ZStack(alignment: .top) {
      if searching && app.selectedCoffeeMatch != nil {
        MidpointSearchState(
          ownName: app.me?.name ?? "Tú",
          ownPhoto: app.me?.photos.first?.url,
          otherName: selectedMatch?.person.name ?? "Tu café",
          otherPhoto: selectedMatch?.person.photos.first?.url
        )
          .ignoresSafeArea()
          .transition(.opacity)
      } else if location.denied && app.selectedCoffeeMatch == nil && !otherPlaceMode {
        LocationPermissionState(openSettings: location.openSettings)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        GeometryReader { proxy in
          ZStack(alignment: .bottom) {
            CoffeeDiscoveryMap(
              shops: filteredShops, searchPoint: vm.searchPoint,
              recommendedShopID: vm.shops.first?.id,
              selected: $selected
            ) { shop in
              withAnimation(NookMotion.spring) {
                selected = shop
                resultsExpanded = true
              }
            } searchHere: { center in
              placeSearchFocused = false
              selected = nil
              await vm.searchVisibleArea(GeoPoint(center), repo: app.repository)
              await preloadVisibleShopImages()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            resultsPanel(in: proxy.size)
          }
        }
        .background(Color.white)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .transition(.opacity)
      }
      if let shop = celebratedShop {
        NookChoiceCelebration(shopName: shop.name)
          .transition(.opacity.combined(with: .scale(scale: 0.94))).zIndex(10)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background { NookInteriorBackdrop().ignoresSafeArea() }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      // Reserve the entire screen before the first loading frame is laid out;
      // otherwise the outgoing tab bar briefly leaves an empty strip below.
      app.tabBarHidden = true
    }
    .task {
      vm.beginLocationRequest()
      let midpointMode = app.selectedCoffeeMatch != nil
      withAnimation(NookMotion.fast) { app.tabBarHidden = true }
      location.request()
      for _ in 0..<150 where location.location == nil && !location.denied {
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard let current = location.location, !location.denied else {
        searching = false
        if !location.denied { vm.failLocation(location.locationError ?? "No hemos podido obtener tu ubicación.") }
        return
      }
      guard !locationHandled else { return }
      locationHandled = true
      await vm.prepare(app.repository)
      if let matchID = app.selectedCoffeeMatch {
        await vm.useMidpoint(matchID: matchID, currentLocation: current, repo: app.repository)
      } else {
        await vm.useCurrentLocation(current, repo: app.repository)
      }
      if midpointMode { await preloadVisibleShopImages() }
      withAnimation(.easeInOut(duration: 0.35)) { searching = false }
      withAnimation(NookMotion.spring) { appeared = true }
    }.sheet(item: $proposalShop) { shop in
      ProposalSheet(shop: shop, matches: vm.matches, isNookChoice: shop.id == vm.shops.first?.id)
    }
    .sheet(isPresented: $showAreaPicker) { areaPicker }
    .onDisappear {
      location.stop()
      app.tabBarHidden = false
    }
    .onChange(of: location.location?.timestamp) { _, timestamp in
      guard timestamp != nil, !locationHandled, vm.origin == nil, let current = location.location else { return }
      locationHandled = true
      Task {
        if let matchID = app.selectedCoffeeMatch {
          await vm.useMidpoint(matchID: matchID, currentLocation: current, repo: app.repository)
          await preloadVisibleShopImages()
        } else {
          await vm.useCurrentLocation(current, repo: app.repository)
        }
        withAnimation(.easeInOut(duration: 0.35)) { searching = false }
        withAnimation(NookMotion.spring) { appeared = true }
      }
    }
  }
  private var selectedMatch: Match? {
    guard let id = app.selectedCoffeeMatch else { return nil }
    return vm.matches.first { $0.id == id }
  }
  @MainActor private func preloadVisibleShopImages() async {
    let urls = vm.shops.prefix(6).compactMap { resolvedShopPhotoURL($0.photoUrl) }
      .filter { NookImageStore.shared.image(for: $0) == nil }
    await withTaskGroup(of: (URL, Data?).self) { group in
      for url in urls {
        group.addTask {
          var request = URLRequest(url: url)
          request.cachePolicy = .returnCacheDataElseLoad
          request.timeoutInterval = 12
          guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode ?? 200 < 300 else { return (url, nil) }
          return (url, data)
        }
      }
      for await (url, data) in group {
        if let data, let image = UIImage(data: data) {
          NookImageStore.shared.insert(image, for: url)
        }
      }
    }
  }
  private func resolvedShopPhotoURL(_ value: String?) -> URL? {
    guard let value, !value.isEmpty else { return nil }
    guard value.hasPrefix("/") else { return URL(string: value) }
    guard var components = URLComponents(
      url: AppConfiguration.apiURL, resolvingAgainstBaseURL: false) else { return nil }
    components.path = value
    components.query = nil
    return components.url
  }
  private var targetPerson: DiscoverProfile? {
    guard let selected = app.selectedCoffeeMatch else { return nil }
    return vm.matches.first(where: { $0.id == selected })?.person
  }
  private var listView: some View {
    ScrollView {
      LazyVStack(spacing: 18) {
        if vm.loading {
          ForEach(0..<3, id: \.self) { _ in CoffeePlaceCardSkeleton() }
        } else if let error = vm.error {
          NookErrorView(message: error) {
            Task {
              if let current = location.location {
                if let matchID = app.selectedCoffeeMatch {
                  await vm.useMidpoint(
                    matchID: matchID, currentLocation: current, repo: app.repository)
                } else {
                  await vm.useCurrentLocation(current, repo: app.repository)
                }
              } else {
                vm.beginLocationRequest()
                location.request()
              }
            }
          }.frame(maxWidth: .infinity).padding(.top, 28)
        } else if vm.state == .empty || filteredShops.isEmpty {
          NookEmptyState(
            icon: location.denied ? "location.slash" : (placeQuery.isEmpty ? "cup.and.saucer" : "magnifyingglass"),
            title: location.denied ? "Necesitamos tu zona" : (placeQuery.isEmpty ? "No encontramos cafeterías" : "No hay coincidencias"),
            text: location.denied
              ? "Activa la ubicación para descubrir cafeterías cercanas."
              : (placeQuery.isEmpty ? "No hay resultados disponibles en esta zona por ahora." : "Prueba con otro nombre, barrio o filtro."))
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        ForEach(Array(filteredShops.enumerated()), id: \.element.id) { index, shop in
          VStack(spacing: 0) {
            NookCoffeeShopCard(
              shop: shop, namespace: namespace,
              recommended: shop.id == vm.shops.first?.id,
              choose: {
                if shop.id == vm.shops.first?.id { celebrateAndContinue(with: shop) }
                else { proposalShop = shop }
              },
              details: {
                withAnimation(NookMotion.spring) { selected = selected?.id == shop.id ? nil : shop }
              })
            if selected?.id == shop.id {
              InlineCoffeeShopDetail(shop: shop, recommended: shop.id == vm.shops.first?.id) {
                if shop.id == vm.shops.first?.id { celebrateAndContinue(with: shop) }
                else { proposalShop = shop }
              } close: {
                withAnimation(NookMotion.spring) { selected = nil }
              }.transition(.move(edge: .top).combined(with: .opacity))
            }
          }.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 35).animation(
            NookMotion.spring.delay(Double(index) * 0.06), value: appeared)
        }
      }
      .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 34)
    }
    .scrollIndicators(.hidden)
    .background(Color.white)
  }
  private func resultsPanel(in size: CGSize) -> some View {
    let collapsedHeight = min(430, size.height * 0.52)
    let expandedHeight = max(collapsedHeight, size.height - 138)
    return VStack(spacing: 0) {
      VStack(spacing: 7) {
        Capsule().fill(NookColors.espresso.opacity(0.20)).frame(width: 38, height: 5)
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 2) {
            Text("CAFETERÍAS PARA VOSOTROS")
              .font(.system(size: 9, weight: .bold, design: .default)).tracking(1.35)
              .foregroundStyle(NookColors.mocha)
            Text(vm.loading ? "Buscando lugares…" : "\(filteredShops.count) lugares cerca")
              .font(NookTypography.business(18, weight: .bold))
              .foregroundStyle(NookColors.mocha)
          }
          Spacer()
          Button {
            withAnimation(NookMotion.spring) { resultsExpanded.toggle() }
          } label: {
            Image(systemName: resultsExpanded ? "chevron.down" : "chevron.up")
              .font(.system(size: 13, weight: .bold)).foregroundStyle(NookColors.espresso)
              .frame(width: 34, height: 34).background(NookColors.espresso.opacity(0.06), in: Circle())
          }.buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 10)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 10).onEnded { value in
          withAnimation(NookMotion.spring) {
            if value.translation.height < -28 { resultsExpanded = true }
            if value.translation.height > 28 { resultsExpanded = false }
          }
        })

      placesDiscoveryControls

      listView
    }
    .frame(height: resultsExpanded ? expandedHeight : collapsedHeight, alignment: .top)
    .background(Color.white)
    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    .shadow(color: NookColors.warmBlack.opacity(0.18), radius: 22, y: -7)
    .animation(NookMotion.spring, value: resultsExpanded)
  }
  private func celebrateAndContinue(with shop: CoffeeShop) {
    Haptics.success()
    withAnimation(NookMotion.spring) { celebratedShop = shop }
    Task {
      try? await Task.sleep(for: .milliseconds(2_350))
      withAnimation(.easeOut(duration: 0.38)) { celebratedShop = nil }
      try? await Task.sleep(for: .milliseconds(380))
      proposalShop = shop
    }
  }
  private var selectedArea: String {
    vm.meetingArea ?? app.me?.city ?? "Tu zona"
  }
  private var filteredShops: [CoffeeShop] {
    let query = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    var values = vm.shops.filter { shop in
      guard !query.isEmpty else { return true }
      return [shop.name, shop.address, shop.neighborhood, shop.category]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .contains(query)
    }
    switch placeFilter {
    case .all: break
    case .open: values = values.filter { $0.openNow == true }
    case .topRated:
      values = values.filter { ($0.rating ?? 0) >= 4.3 }
        .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
    case .nearby: values = values.filter { $0.distanceKm < 1 }
    }
    return values
  }

  private var placesDiscoveryControls: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .semibold)).foregroundStyle(NookColors.espresso.opacity(0.55))
        TextField("Buscar cafetería o zona", text: $placeQuery)
          .font(.system(size: 15, weight: .medium, design: .default))
          .textInputAutocapitalization(.words).submitLabel(.search)
          .focused($placeSearchFocused)
          .onChange(of: placeQuery) { _, value in
            if value.isEmpty { placeSearchFocused = false }
          }
        if !placeQuery.isEmpty {
          Button { placeQuery = "" } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(NookColors.espresso.opacity(0.32))
          }.buttonStyle(.plain).accessibilityLabel("Borrar búsqueda")
        }
      }
      .padding(.horizontal, 14).frame(height: 46)
      .background(NookColors.espresso.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(PlaceFilter.allCases) { filter in
            Button {
              Haptics.selection()
              withAnimation(NookMotion.fast) { placeFilter = filter }
            } label: {
              Text(filter.rawValue)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(placeFilter == filter ? NookColors.inverseText : NookColors.espresso.opacity(0.72))
                .padding(.horizontal, 13).frame(height: 34)
                .background(placeFilter == filter ? NookColors.espresso : NookColors.espresso.opacity(0.045), in: Capsule())
            }.buttonStyle(.plain)
          }
        }
      }.scrollIndicators(.hidden)
    }
    .padding(.horizontal, 16).padding(.bottom, 12)
    .background(Color.white)
  }

  private var placeModeSelector: some View {
    HStack(spacing: 6) {
      placeModeButton(targetPerson == nil ? "Mi ubicación" : "Punto medio", icon: targetPerson == nil ? "location.fill" : "point.3.connected.trianglepath.dotted", selected: !otherPlaceMode) {
        otherPlaceMode = false
        showMap = false
        searchTitle = "Buscando vuestro\npunto medio"
        searchLabel = nil
        exploreArea(nil)
      }
      placeModeButton("Otro lugar", icon: "map.fill", selected: otherPlaceMode) {
        otherPlaceMode = true
        showMap = true
        Haptics.selection()
      }
    }
    .padding(5).background(NookColors.espresso.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
  private func placeModeButton(
    _ title: String, icon: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: icon).font(.system(size: 13, weight: .semibold))
        Text(title).font(.system(size: 13, weight: .bold, design: .default))
      }
      .foregroundStyle(selected ? NookColors.inverseText : NookColors.espresso.opacity(0.64))
      .frame(maxWidth: .infinity).frame(height: 42)
      .background(selected ? NookColors.espresso : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }.buttonStyle(.plain)
  }
  private var areaPicker: some View {
    NavigationStack {
      ZStack {
        NookInteriorBackdrop()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
              Text("MOVER LA MESA").font(NookTypography.caption).tracking(1.5)
                .foregroundStyle(NookColors.mocha)
              Text("¿Dónde os apetece?").font(NookTypography.display(36)).tracking(-0.5)
              Text("Nook volverá a buscar sitios que encajen con los dos.")
                .font(.subheadline).foregroundStyle(NookColors.warmGray)
            }.padding(.bottom, 4)
            areaOption("El punto medio", "La opción más equilibrada", "arrow.triangle.swap", area: nil)
            if let city = app.me?.city {
              areaOption("Usar mi ubicación", city, "location.fill", area: "__CURRENT__")
            }
            if let person = targetPerson, let city = person.city {
              areaOption("Cerca de \(person.name)", city, "person.crop.circle", area: city)
            }
            VStack(alignment: .leading, spacing: 10) {
              Label("Otro lugar", systemImage: "magnifyingglass").font(.headline)
              HStack(spacing: 10) {
                TextField("Barrio, pueblo o ciudad", text: $customArea)
                  .textInputAutocapitalization(.words).submitLabel(.search)
                  .onSubmit { submitCustomArea() }
                  .onChange(of: customArea) { _, value in locationSearch.update(value) }
                Button { submitCustomArea() } label: {
                  Image(systemName: "arrow.right").font(.headline)
                    .frame(width: 40, height: 40).background(NookColors.espresso, in: Circle())
                    .foregroundStyle(NookColors.inverseText)
                }.disabled(customArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              }
              if !locationSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                  ForEach(Array(locationSearch.suggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button {
                      customArea = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                      locationSearch.suggestions = []
                      Task { await selectSuggestion(suggestion) }
                    } label: {
                      HStack(spacing: 10) {
                        Image(systemName: "mappin").foregroundStyle(NookColors.mocha)
                        VStack(alignment: .leading, spacing: 2) {
                          Text(suggestion.title).font(.subheadline.bold()).lineLimit(1)
                          if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle).font(.caption).foregroundStyle(NookColors.warmGray).lineLimit(1)
                          }
                        }
                        Spacer()
                      }.foregroundStyle(NookColors.espresso).padding(.vertical, 10)
                    }.buttonStyle(.plain)
                    if suggestion.title != locationSearch.suggestions.last?.title {
                      Divider().overlay(NookColors.espresso.opacity(0.08))
                    }
                  }
                }
              }
            }.padding(16).background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
          }.padding(20)
        }.scrollDismissesKeyboard(.interactively)
      }.toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cerrar") { showAreaPicker = false }.foregroundStyle(NookColors.espresso)
        }
      }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
  private func areaOption(_ title: String, _ subtitle: String, _ icon: String, area: String?) -> some View {
    Button {
      otherPlaceMode = area != nil
      showMap = area != nil
      searchTitle = area == nil ? "Buscando vuestro\npunto medio" : "Buscando en\n\(subtitle)"
      searchLabel = area
      exploreArea(area)
    } label: {
      HStack(spacing: 13) {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(NookColors.mocha)
          .frame(width: 42, height: 42).background(NookColors.mocha.opacity(0.10), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(NookColors.warmGray)
        }
        Spacer(); Image(systemName: "arrow.right").font(.caption.bold())
      }.foregroundStyle(NookColors.espresso).padding(14)
        .background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }.buttonStyle(.plain)
  }
  private func submitCustomArea() {
    let area = customArea.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !area.isEmpty else { return }
    otherPlaceMode = true
    showMap = true
    searchTitle = "Buscando en\n\(area)"
    searchLabel = area
    Task { await selectArea(query: area) }
  }
  private func exploreArea(_ area: String?) {
    if let area, area != "__CURRENT__" {
      Task { await selectArea(query: area) }
      return
    }
    showAreaPicker = false
    Task {
      appeared = false
      withAnimation(NookMotion.fast) { app.tabBarHidden = true }
      withAnimation(.easeInOut(duration: 0.25)) { searching = true }
      guard let current = location.location else {
        vm.failLocation("Todavía no tenemos una ubicación válida.")
        searching = false
        return
      }
      if area == nil, let matchID = app.selectedCoffeeMatch {
        await vm.useMidpoint(matchID: matchID, currentLocation: current, repo: app.repository)
      } else {
        await vm.useCurrentLocation(current, repo: app.repository)
      }
      withAnimation(.easeInOut(duration: 0.55)) { searching = false }
      withAnimation(NookMotion.spring) { appeared = true }
    }
  }
  private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) async {
    showAreaPicker = false
    searching = true
    do {
      let (point, name) = try await locationSearch.resolve(suggestion)
      await selectResolvedArea(point, name: name)
    } catch {
      searching = false
      vm.failLocation("No hemos podido localizar ese lugar.")
    }
  }
  private func selectArea(query: String) async {
    showAreaPicker = false
    searching = true
    do {
      let (point, name) = try await locationSearch.resolve(query: query)
      await selectResolvedArea(point, name: name)
    } catch {
      searching = false
      vm.failLocation("No hemos podido localizar ese lugar.")
    }
  }
  private func selectResolvedArea(_ point: GeoPoint, name: String) async {
    showAreaPicker = false
    searching = true
    await vm.useSelectedLocation(point, name: name, repo: app.repository)
    withAnimation(.easeInOut(duration: 0.35)) { searching = false }
    withAnimation(NookMotion.spring) { appeared = true }
  }
  private var mapView: some View {
    CoffeeMapExplorer(
      shops: filteredShops, areaName: selectedArea, searchPoint: vm.searchPoint,
      currentLocation: location.location.map { GeoPoint($0.coordinate) }, radiusKm: $vm.radiusKm,
      selected: $selected, loading: vm.mapLoading
    ) {
      withAnimation(NookMotion.spring) { showMap = false }
    } changeArea: {
      showAreaPicker = true
    } searchHere: { center in
      await vm.searchVisibleArea(GeoPoint(center), repo: app.repository)
    } useCurrentLocation: {
      guard let current = location.location else { location.request(); return }
      await vm.useCurrentLocation(current, repo: app.repository)
    } radiusChanged: { radius in
      vm.setRadius(radius, repo: app.repository)
    }
  }
}

private struct MidpointSearchState: View {
  let ownName: String
  let ownPhoto: String?
  let otherName: String
  let otherPhoto: String?

  var body: some View {
    SmartCoffeeSearch(
      person: nil, ownName: ownName, ownCity: nil, ownPhoto: ownPhoto,
      meetingArea: nil, otherName: otherName, otherPhoto: otherPhoto,
      title: "Buscando\npunto medio", minimal: true)
    .accessibilityElement(children: .combine)
  }
}

private struct CoffeeDiscoveryMap: View {
  let shops: [CoffeeShop]
  let searchPoint: GeoPoint?
  let recommendedShopID: UUID?
  @Binding var selected: CoffeeShop?
  let select: (CoffeeShop) -> Void
  let searchHere: @MainActor (CLLocationCoordinate2D) async -> Void
  @State private var camera: MapCameraPosition = .automatic
  @State private var visibleRegion: MKCoordinateRegion?
  @State private var searchedRegion: MKCoordinateRegion?
  @State private var userMovedMap = false
  @State private var searchingArea = false
  @State private var hasPositionedCamera = false

  var body: some View {
    ZStack(alignment: .top) {
      Map(position: $camera) {
        UserAnnotation()
        if let searchPoint {
          Annotation("Punto medio", coordinate: searchPoint.coordinate) {
            AnimatedMidpointMarker()
          }
        }
        ForEach(shops) { shop in
          if let latitude = shop.latitude, let longitude = shop.longitude {
            Annotation(shop.name, coordinate: .init(latitude: latitude, longitude: longitude)) {
              Button { select(shop) } label: {
                VStack(spacing: 3) {
                  ZStack {
                    Circle().fill(
                      shop.id == recommendedShopID
                        ? NookColors.nookGold
                        : (selected?.id == shop.id ? NookColors.mocha : NookColors.espresso))
                      .frame(width: selected?.id == shop.id ? 46 : 40, height: selected?.id == shop.id ? 46 : 40)
                    Image(systemName: shop.id == recommendedShopID ? "sparkles" : "cup.and.saucer.fill")
                      .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                  }
                  .overlay(Circle().stroke(.white, lineWidth: 2.5))
                  .shadow(color: .black.opacity(0.20), radius: 7, y: 4)
                  if shop.id == recommendedShopID, selected?.id != shop.id {
                    Text("NOOK").font(.system(size: 8, weight: .black)).tracking(0.8)
                      .foregroundStyle(NookColors.primaryCoffeePressed)
                      .padding(.horizontal, 6).frame(height: 18)
                      .background(.white, in: Capsule())
                  }
                  if selected?.id == shop.id {
                    Text(shop.name).font(.system(size: 10, weight: .bold)).lineLimit(1)
                      .foregroundStyle(NookColors.espresso).padding(.horizontal, 7).frame(height: 22)
                      .background(.white, in: Capsule())
                  }
                }
              }.buttonStyle(.plain)
            }
          }
        }
      }
      .onMapCameraChange(frequency: .onEnd) { context in
        visibleRegion = context.region
        guard hasPositionedCamera, let searchedRegion else { return }
        let moved = GeographicMath.distanceMeters(
          GeoPoint(context.region.center), GeoPoint(searchedRegion.center)) > 120
        let zoomed = abs(context.region.span.latitudeDelta - searchedRegion.span.latitudeDelta)
          > searchedRegion.span.latitudeDelta * 0.14
        userMovedMap = moved || zoomed
      }
      .mapStyle(.standard(elevation: .flat))
      .environment(\.colorScheme, .light)

      if userMovedMap, let region = visibleRegion {
        Button {
          Task { @MainActor in
            searchingArea = true
            await searchHere(region.center)
            searchedRegion = region
            userMovedMap = false
            searchingArea = false
          }
        } label: {
          HStack(spacing: 8) {
            if searchingArea { ProgressView().tint(.white).controlSize(.small) }
            else { Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .bold)) }
            Text(searchingArea ? "Buscando…" : "Buscar cafeterías en esta zona")
              .font(.system(size: 13, weight: .bold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 17).frame(height: 42)
          .background(NookColors.espresso.opacity(0.94), in: Capsule())
          .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        }
        .buttonStyle(.plain).disabled(searchingArea)
        .padding(.top, 64)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(NookMotion.fast, value: userMovedMap)
    .onAppear { positionCamera() }
    .onChange(of: searchPoint) { _, _ in
      if !userMovedMap { positionCamera() }
    }
  }

  private func positionCamera() {
    guard let searchPoint else { return }
    let region = MKCoordinateRegion(
      center: searchPoint.coordinate,
      span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))
    hasPositionedCamera = false
    searchedRegion = region
    camera = .region(region)
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      hasPositionedCamera = true
    }
  }
}

private struct AnimatedMidpointMarker: View {
  @State private var dashPhase: CGFloat = 0
  @State private var pulse = false

  var body: some View {
    ZStack {
      Path { path in
        path.move(to: CGPoint(x: 5, y: 9))
        path.addLine(to: CGPoint(x: 50, y: 38))
        path.move(to: CGPoint(x: 95, y: 9))
        path.addLine(to: CGPoint(x: 50, y: 38))
      }
      .stroke(
        NookColors.mocha.opacity(0.9),
        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 7], dashPhase: dashPhase))

      Circle()
        .fill(NookColors.caramelSoft.opacity(pulse ? 0.12 : 0.38))
        .frame(width: pulse ? 58 : 42, height: pulse ? 58 : 42)
        .position(x: 50, y: 38)

      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(NookColors.mocha, in: Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2.5))
        .shadow(color: NookColors.mocha.opacity(0.3), radius: 8, y: 4)
        .position(x: 50, y: 38)
    }
    .frame(width: 100, height: 62)
    .onAppear {
      withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
        dashPhase = -24
      }
      withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
        pulse = true
      }
    }
    .accessibilityLabel("Punto medio")
  }
}

private struct CoffeeMapExplorer: View {
  let shops: [CoffeeShop]
  let areaName: String
  let searchPoint: GeoPoint?
  let currentLocation: GeoPoint?
  @Binding var radiusKm: Double
  @Binding var selected: CoffeeShop?
  let loading: Bool
  let showList: () -> Void
  let changeArea: () -> Void
  let searchHere: @MainActor (CLLocationCoordinate2D) async -> Void
  let useCurrentLocation: @MainActor () async -> Void
  let radiusChanged: (Double) -> Void
  @State private var camera: MapCameraPosition = .automatic
  @State private var visibleCenter: CLLocationCoordinate2D?
  @State private var userMovedMap = false
  @State private var hasPositionedCamera = false

  private var visibleShops: [CoffeeShop] {
    shops.filter { shop in
      guard let latitude = shop.latitude, let longitude = shop.longitude else { return false }
      let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      let pin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      let origin = searchPoint?.coordinate ?? visibleCenter ?? coordinate
      let center = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
      return pin.distance(from: center) <= radiusKm * 1_000
    }
  }

  var body: some View {
    ZStack {
      Map(position: $camera) {
        UserAnnotation()
        ForEach(visibleShops) { shop in
          if let latitude = shop.latitude, let longitude = shop.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            Annotation(shop.name, coordinate: coordinate) {
              Button {
                Haptics.selection()
                withAnimation(NookMotion.spring) { selected = shop }
              } label: {
                ZStack {
                  Circle().fill(selected?.id == shop.id ? NookColors.mocha : NookColors.espresso)
                    .frame(width: selected?.id == shop.id ? 48 : 42, height: selected?.id == shop.id ? 48 : 42)
                  Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(NookColors.inverseText)
                }
                .overlay(Circle().stroke(NookColors.cream, lineWidth: 3))
                .shadow(color: NookColors.espresso.opacity(0.22), radius: 8, y: 4)
              }.buttonStyle(.plain).accessibilityLabel("\(shop.name), cafetería")
            }
          }
        }
      }
      .onMapCameraChange(frequency: .onEnd) { context in
        visibleCenter = context.region.center
        guard hasPositionedCamera, let searchPoint else { return }
        userMovedMap = GeographicMath.distanceMeters(GeoPoint(context.region.center), searchPoint) > 180
      }
      .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
      .overlay {
        LinearGradient(
          colors: [NookColors.caramelSoft.opacity(0.10), NookColors.mocha.opacity(0.07)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
          .blendMode(.multiply)
          .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(NookColors.espresso.opacity(0.10), lineWidth: 0.8)
      }

      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Button(action: changeArea) {
            HStack(spacing: 10) {
            Image(systemName: "location.fill").font(.system(size: 12, weight: .bold))
              .foregroundStyle(NookColors.caramelSoft)
            VStack(alignment: .leading, spacing: 1) {
              Text("BUSCANDO EN").font(.system(size: 9, weight: .bold, design: .default)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
              Text(areaName).font(.system(size: 14, weight: .bold, design: .default)).lineLimit(1)
            }
            Spacer()
            Text("Cambiar").font(.system(size: 11, weight: .bold, design: .default))
              .foregroundStyle(NookColors.caramelSoft)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
          }
          .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 52)
          .background(NookColors.warmBlack.opacity(0.91), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.12)))
          }.buttonStyle(.plain).accessibilityLabel("Cambiar zona, ahora \(areaName)")
          Button {
            Task {
              await useCurrentLocation()
              positionCameraIfNeeded(force: true)
            }
          } label: {
            Image(systemName: "location.circle.fill").font(.system(size: 20, weight: .semibold))
              .frame(width: 52, height: 52)
              .background(NookColors.caramelSoft, in: RoundedRectangle(cornerRadius: 17))
          }.buttonStyle(.plain).foregroundStyle(NookColors.warmBlack)
            .disabled(currentLocation == nil).accessibilityLabel("Mi ubicación")
        }

        Spacer()

        if loading {
          HStack(spacing: 10) {
            NookCoffeeLogo(size: 28, animated: true)
            VStack(alignment: .leading, spacing: 1) {
              Text("NOOK ESTÁ BUSCANDO").font(.system(size: 9, weight: .bold, design: .default)).tracking(1.1)
              Text("Nuevos cafés por aquí…").font(.system(size: 13, weight: .bold, design: .default))
            }
          }
          .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
          .background(NookColors.warmBlack.opacity(0.9), in: Capsule())
          .transition(.scale(scale: 0.92).combined(with: .opacity))
        }

        if userMovedMap, let visibleCenter {
          Button {
            Task {
              await searchHere(visibleCenter)
              userMovedMap = false
            }
          } label: {
            Label("Buscar en esta zona", systemImage: "magnifyingglass")
              .font(.system(size: 13, weight: .bold, design: .default))
              .padding(.horizontal, 16).frame(height: 42)
              .background(NookColors.espresso, in: Capsule()).foregroundStyle(NookColors.inverseText)
          }.buttonStyle(.plain)
        }

        if let shop = selected {
          Button(action: showList) {
            HStack(spacing: 12) {
              ShopImage(url: shop.photoUrl, seed: shop.name)
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              VStack(alignment: .leading, spacing: 3) {
                Text(shop.name).font(.system(size: 17, weight: .bold, design: .default)).lineLimit(1)
                Text("\(shop.vibeLabel)  ·  \(String(format: "%.1f", shop.distanceKm)) km")
                  .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.64)).lineLimit(1)
              }
              Spacer()
              Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                .frame(width: 38, height: 38).background(NookColors.caramelSoft, in: Circle())
                .foregroundStyle(NookColors.warmBlack)
            }.padding(9).background(NookColors.warmBlack.opacity(0.93), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.12)))
          }.buttonStyle(.plain).foregroundStyle(.white)
        } else {
          Label("Toca una taza", systemImage: "cup.and.saucer.fill")
            .font(.system(size: 12, weight: .semibold, design: .default)).foregroundStyle(.white.opacity(0.84))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(NookColors.warmBlack.opacity(0.88), in: Capsule())
        }

        VStack(spacing: 7) {
          HStack {
            Text("RADIO").font(.system(size: 9, weight: .bold, design: .default)).tracking(1.2)
            Spacer()
            Text("\(Int(radiusKm)) km").font(.system(size: 13, weight: .bold, design: .default))
              .foregroundStyle(NookColors.caramelSoft)
          }
          Slider(value: $radiusKm, in: 1...30, step: 1) { editing in
            if !editing { radiusChanged(radiusKm) }
          }.tint(NookColors.caramelSoft)
        }.foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
          .background(NookColors.warmBlack.opacity(0.93), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.12)))
      }
      .padding(12)
    }
    .padding(14)
    .background(Color.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .layoutPriority(1)
    .animation(NookMotion.fast, value: loading)
    .onAppear { positionCameraIfNeeded() }
    .onChange(of: searchPoint) { _, _ in positionCameraIfNeeded(force: true) }
  }

  private func positionCameraIfNeeded(force: Bool = false) {
    guard let searchPoint, force || !hasPositionedCamera else { return }
    let span = max(0.012, min(radiusKm / 90, 0.22))
    camera = .region(MKCoordinateRegion(
      center: searchPoint.coordinate,
      span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    visibleCenter = searchPoint.coordinate
    userMovedMap = false
    hasPositionedCamera = true
  }
}

private struct LocationPermissionState: View {
  let openSettings: () -> Void
  var body: some View {
    VStack(spacing: 18) {
      Spacer()
      ZStack {
        Circle().fill(NookColors.mocha.opacity(0.12)).frame(width: 88, height: 88)
        Image(systemName: "location.slash.fill").font(.system(size: 30, weight: .medium))
          .foregroundStyle(NookColors.mocha)
      }
      VStack(spacing: 8) {
        Text("Cafés cerca de ti").font(NookTypography.display(32))
        Text("Necesitamos tu ubicación aproximada para encontrar cafeterías reales a tu alrededor. Nunca mostramos dónde estás.")
          .font(.system(size: 14, weight: .medium, design: .default)).foregroundStyle(NookColors.warmGray)
          .multilineTextAlignment(.center).lineSpacing(3)
      }
      Button(action: openSettings) {
        Label("Abrir Ajustes", systemImage: "gearshape.fill")
          .font(.system(size: 15, weight: .bold, design: .default)).foregroundStyle(NookColors.inverseText)
          .frame(maxWidth: .infinity).frame(height: 54).background(NookColors.espresso, in: Capsule())
      }.buttonStyle(.plain)
      Spacer()
    }.padding(.horizontal, 28).foregroundStyle(NookColors.espresso)
  }
}

private struct NookChoiceCelebration: View {
  let shopName: String
  @State private var appeared = false
  @State private var premiumGlow = false
  @State private var burst = false
  var body: some View {
    ZStack {
      VStack(spacing: 18) {
        ZStack {
          ForEach(0..<12) { index in
            CoffeeBean().frame(width: 10, height: 16)
              .rotationEffect(.degrees(Double(index * 31) + (burst ? 150 : 0)))
              .offset(y: burst ? -112 : -28)
              .rotationEffect(.degrees(Double(index * 30)))
              .scaleEffect(burst ? 0.72 : 0.16)
              .opacity(burst ? 0 : 0.9)
              .animation(.easeOut(duration: 1.18).delay(Double(index) * 0.018), value: burst)
          }
          Circle().fill(NookColors.offWhite).frame(width: 82, height: 82)
            .shadow(color: NookColors.nookGold.opacity(premiumGlow ? 0.48 : 0.20), radius: premiumGlow ? 24 : 9)
          Image(systemName: "cup.and.saucer.fill").font(.system(size: 29, weight: .medium))
            .foregroundStyle(NookColors.espresso)
        }
        .scaleEffect(appeared ? (premiumGlow ? 1.04 : 1) : 0.30)
        .rotationEffect(.degrees(appeared ? 0 : -24))
        VStack(spacing: 7) {
          Text("¡Buena elección!").font(NookTypography.display(38)).tracking(-0.4)
          HStack(spacing: 7) {
            Image(systemName: "sparkles")
              .symbolEffect(.pulse, options: .repeating.speed(0.55), value: premiumGlow)
            Text("ELECCIÓN NOOK").tracking(1.5)
            Image(systemName: "sparkles")
              .symbolEffect(.pulse, options: .repeating.speed(0.55), value: premiumGlow)
          }
          .font(NookTypography.business(11, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 15).frame(height: 34)
          .background(.white.opacity(0.12), in: Capsule())
          .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
          .scaleEffect(premiumGlow ? 1.025 : 1)
          Text(shopName).font(.system(size: 15, weight: .medium, design: .default))
            .foregroundStyle(.white.opacity(0.76))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
      }
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 30)
      .padding(.vertical, 28)
      .frame(maxWidth: 340)
      .background {
        RadialGradient(
          colors: [
            NookColors.warmBlack,
            NookColors.warmBlack.opacity(0.92),
            NookColors.primaryCoffeePressed.opacity(0.72),
            NookColors.warmBlack.opacity(0.34),
            .clear,
          ],
          center: .center, startRadius: 24, endRadius: 350)
          .frame(width: 720, height: 620)
          .blur(radius: 44)
          .allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .contentShape(Rectangle())
    .onAppear {
      withAnimation(NookMotion.spring) { appeared = true }
      withAnimation(.easeOut(duration: 1.15).delay(0.18)) { burst = true }
      withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
        premiumGlow = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { Haptics.success() }
    }
  }
}

private extension CoffeeShop {
  var nookPhraseIndex: Int {
    name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 97 }
  }

  var meetingHeadline: String {
    if let rating, rating >= 4.6, (reviewCount ?? 0) >= 100 {
      return "Muy bien valorado para conoceros"
    }
    if let category, !category.isEmpty {
      return "\(category) para vuestro primer café"
    }
    return "Un café para empezar a conoceros"
  }

  var nookEditorialFallback: String {
    var facts: [String] = []
    if let category, !category.isEmpty { facts.append(category) }
    facts.append(distanceKm < 1 ? "a \(Int(distanceKm * 1000)) m" : "a \(distanceKm.formatted()) km")
    if let rating {
      let reviews = reviewCount.map { " en \($0) reseñas" } ?? ""
      facts.append("\(rating.formatted(.number.precision(.fractionLength(1)))) de valoración\(reviews)")
    }
    if openNow == true { facts.append("abierto ahora") }
    else if openNow == false { facts.append("cerrado ahora") }
    return facts.joined(separator: " · ") + "."
  }

  var todayHoursText: String? {
    guard let openingHours, !openingHours.isEmpty else { return nil }
    let weekday = Calendar.autoupdatingCurrent.component(.weekday, from: Date())
    let names: [Int: [String]] = [
      1: ["domingo", "sunday"], 2: ["lunes", "monday"],
      3: ["martes", "tuesday"], 4: ["miércoles", "miercoles", "wednesday"],
      5: ["jueves", "thursday"], 6: ["viernes", "friday"],
      7: ["sábado", "sabado", "saturday"],
    ]
    let entries = openingHours.components(separatedBy: " · ")
    if let entry = entries.first(where: { value in
      let normalized = value.folding(options: .diacriticInsensitive, locale: .current).lowercased()
      return (names[weekday] ?? []).contains { normalized.hasPrefix($0.folding(options: .diacriticInsensitive, locale: .current)) }
    }) {
      guard let separator = entry.firstIndex(of: ":") else { return entry }
      let value = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      return value.lowercased().contains("cerrado") || value.lowercased().contains("closed")
        ? "Cerrado hoy" : "Hoy · \(value)"
    }
    return entries.count == 1 ? openingHours : nil
  }
}

private struct InlineCoffeeShopDetail: View {
  @Environment(\.openURL) private var openURL
  let shop: CoffeeShop
  let recommended: Bool
  let choose: () -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text(recommended ? "POR QUÉ ES ELECCIÓN NOOK" : "POR QUÉ PUEDE ENCAJAR")
            .font(.system(size: 10, weight: .bold, design: .default)).tracking(1.4)
            .foregroundStyle(NookColors.mocha)
          Text(recommended ? "Buena elección: \(shop.meetingHeadline.lowercased())" : shop.meetingHeadline)
            .font(NookTypography.display(22)).tracking(-0.2)
        }
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            .frame(width: 32, height: 32).background(NookColors.espresso.opacity(0.07), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Cerrar detalle")
      }.padding(.bottom, 13)

      Text(shop.description ?? shop.nookEditorialFallback)
        .font(.system(size: 15, weight: .medium, design: .default))
        .foregroundStyle(NookColors.espresso.opacity(0.72)).lineSpacing(4).lineLimit(3)
        .padding(.bottom, 17)

      HStack(spacing: 8) {
        compactFact(icon: "clock", text: shortHours)
        compactFact(icon: "figure.walk", text: distanceText)
        compactFact(icon: "sparkles", text: shop.vibeLabel.replacingOccurrences(of: "😌 ", with: "").replacingOccurrences(of: "🎵 ", with: "").replacingOccurrences(of: "🙂 ", with: ""))
      }.padding(.bottom, 17)

      Button(action: openMaps) {
        HStack(spacing: 9) {
          Image(systemName: "location").foregroundStyle(NookColors.mocha)
          Text(shop.address).lineLimit(1)
          Spacer(minLength: 6)
          Image(systemName: "arrow.up.right").font(.caption.bold())
        }.font(.system(size: 12, weight: .medium, design: .default))
          .foregroundStyle(NookColors.espresso.opacity(0.62)).padding(.vertical, 14)
      }.buttonStyle(.plain)

      Button(action: choose) {
        HStack(spacing: 13) {
          Image(systemName: "cup.and.saucer.fill").font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38).background(NookColors.inverseText.opacity(0.08), in: Circle())
          VStack(alignment: .leading, spacing: 1) {
            Text("Elegir").font(.system(size: 16, weight: .bold, design: .default))
            Text("Continuar con el día y la hora").font(.system(size: 11, weight: .medium, design: .default)).opacity(0.62)
          }
          Spacer()
          Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
        }.foregroundStyle(NookColors.inverseText).padding(.horizontal, 13).frame(height: 62)
          .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
      }.buttonStyle(.plain).accessibilityHint("Continúa para proponer el día y la hora")
    }
    .foregroundStyle(NookColors.espresso)
    .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 17)
    .background(
      LinearGradient(colors: [NookColors.offWhite, NookColors.cream], startPoint: .top, endPoint: .bottom),
      in: UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
    .overlay(alignment: .top) { Rectangle().fill(NookColors.mocha.opacity(0.16)).frame(height: 0.7) }
    .padding(.horizontal, 3).offset(y: -5).padding(.bottom, -5)
  }

  private func compactFact(icon: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(NookColors.mocha)
      Text(text).lineLimit(1).minimumScaleFactor(0.72)
    }.font(.system(size: 10, weight: .semibold, design: .default))
      .padding(.horizontal, 10).frame(height: 32)
      .background(NookColors.espresso.opacity(0.055), in: Capsule())
  }
  private var shortHours: String { shop.openingHours?.components(separatedBy: " · ").first ?? "Horario pendiente" }

  private var distanceText: String {
    shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km"
  }
  private func openMaps() {
    let query = shop.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shop.address
    if let url = URL(string: "https://maps.apple.com/?q=\(query)") { openURL(url) }
  }
}

private struct MidpointPeopleRoute: View {
  let ownName: String
  let ownPhoto: String?
  let otherName: String
  let otherPhoto: String?
  @State private var dashPhase: CGFloat = 0
  @State private var pulse = false

  var body: some View {
    HStack(spacing: 1) {
      avatar(name: ownName, photo: ownPhoto)
      routeLine
      ZStack {
        Circle()
          .fill(NookColors.mocha.opacity(0.2))
          .frame(width: pulse ? 88 : 72, height: pulse ? 88 : 72)
        Circle().stroke(.white.opacity(0.22), lineWidth: 3).frame(width: 70, height: 70)
        Image(systemName: "location.fill")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(NookColors.inverseText)
          .frame(width: 58, height: 58)
          .background(NookColors.mocha, in: Circle())
      }
      .frame(width: 76, height: 88)
      .shadow(color: NookColors.mocha.opacity(0.5), radius: 22)
      routeLine
      avatar(name: otherName, photo: otherPhoto)
    }
      .frame(maxWidth: 310)
    .onAppear {
      withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
        dashPhase = -18
      }
      withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
  }

  private var routeLine: some View {
    GeometryReader { proxy in
      Path { path in
        path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
      }
      .stroke(
        NookColors.caramelSoft.opacity(0.95),
        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 7], dashPhase: dashPhase)
      )
    }
      .frame(maxWidth: 22, minHeight: 12, maxHeight: 12)
      .shadow(color: NookColors.mocha.opacity(0.35), radius: 4)
  }

  private func avatar(name: String, photo: String?) -> some View {
    ProfileImage(url: photo, name: name)
      .frame(width: 78, height: 78)
      .clipShape(Circle())
      .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 2.5))
      .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
      .accessibilityLabel(name)
  }
}

private struct SmartCoffeeSearch: View {
  let person: DiscoverProfile?
  let ownName: String?
  let ownCity: String?
  let ownPhoto: String?
  let meetingArea: String?
  var otherName: String? = nil
  var otherPhoto: String? = nil
  let title: String
  var minimal = false
  @State private var active = false
  @State private var focus = 0
  @State private var minimalRing = false
  @State private var minimalRingRotation = false
  private let photos = [
    "https://images.unsplash.com/photo-1445116572660-236099ec97a0?auto=format&fit=crop&w=700&q=75",
    "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=700&q=75",
    "https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=700&q=75",
    "https://images.unsplash.com/photo-1559925393-8be0ec4767c8?auto=format&fit=crop&w=700&q=75",
    "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=700&q=75",
    "https://images.unsplash.com/photo-1442512595331-e89e73853f31?auto=format&fit=crop&w=700&q=75"
  ]
  var body: some View {
    GeometryReader { proxy in
      let gap: CGFloat = 12
      let galleryWidth = proxy.size.width * 1.42
      let tileWidth = (galleryWidth - gap * 2) / 3
      let tileHeight = max(142, proxy.size.height / 4.75)
      ZStack {
        if minimal {
          NookColors.warmBlack.ignoresSafeArea()
        }
        HStack(alignment: .center, spacing: gap) {
          ForEach(0..<3, id: \.self) { column in
            VStack(spacing: gap) {
              ForEach(0..<6, id: \.self) { row in
                let index = row * 3 + column
                galleryTile(index: index, width: tileWidth, height: tileHeight)
              }
            }
            .offset(y: CGFloat(column - 1) * 28)
          }
        }
        .frame(width: galleryWidth)
        .rotationEffect(.degrees(-7.5))
        .offset(x: active ? 0 : -18, y: active ? 0 : 20)
        .animation(.easeOut(duration: 1.1), value: active)
        .frame(width: proxy.size.width, height: proxy.size.height).clipped()

        if !minimal {
          LinearGradient(
            colors: [NookColors.warmBlack.opacity(0.74), .clear, NookColors.warmBlack.opacity(0.82)],
            startPoint: .top, endPoint: .bottom).ignoresSafeArea()
          RadialGradient(
            colors: [NookColors.warmBlack.opacity(0.84), NookColors.warmBlack.opacity(0.26), .clear],
            center: .center, startRadius: 20, endRadius: 235).ignoresSafeArea()
        }

        VStack(spacing: 0) {
          Spacer()
          VStack(spacing: 9) {
            if minimal {
              MidpointPeopleRoute(
                ownName: ownName ?? "Tú", ownPhoto: ownPhoto,
                otherName: otherName ?? person?.name ?? "Tu café",
                otherPhoto: otherPhoto ?? person?.photos.first?.url)
            } else {
              NookAILogo()
            }
            Text(title)
              .font(NookTypography.display(minimal ? 36 : 41)).tracking(-0.7).multilineTextAlignment(.center)
              .foregroundStyle(.white)
            if !minimal {
              Text(meetingArea ?? midpointLabel)
                .font(.system(size: 16, weight: .semibold, design: .default)).foregroundStyle(.white.opacity(0.72))
              NookInlineLoading(
                text: "Comparando cafeterías",
                foreground: .white.opacity(0.7),
                accent: NookColors.mocha
              ).padding(.top, 5)
            }
          }
          .padding(.horizontal, minimal ? 28 : 0)
          .padding(.vertical, minimal ? 26 : 0)
          .background {
            if minimal {
              RadialGradient(
                colors: [
                  NookColors.warmBlack.opacity(0.94),
                  NookColors.primaryCoffeePressed.opacity(0.72),
                  NookColors.primaryCoffee.opacity(0.34),
                  .clear,
                ],
                center: .center, startRadius: 18, endRadius: 178)
                .frame(width: 360, height: 250)
                .blur(radius: 16)
                .allowsHitTesting(false)
            }
          }
          Spacer()
          if !minimal {
            Text("Buscando el lugar que mejor os encaje")
              .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.56))
              .padding(.bottom, max(74, proxy.safeAreaInsets.bottom + 58))
          }
        }.padding(.horizontal, 28)
      }.frame(width: proxy.size.width, height: proxy.size.height)
    }.onAppear {
      NookSoundManager.shared.play(.searching)
      withAnimation(NookMotion.spring) { active = true }
      if minimal {
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
          minimalRing = true
        }
        withAnimation(.linear(duration: 5.2).repeatForever(autoreverses: false)) {
          minimalRingRotation = true
        }
      }
      Task {
        var index = 1
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(360))
          guard !Task.isCancelled else { break }
          withAnimation(.easeInOut(duration: 0.55)) { focus = index % 18 }
          index += 1
        }
      }
    }
  }

  private func galleryTile(index: Int, width: CGFloat, height: CGFloat) -> some View {
    NookRemoteImage(url: URL(string: photos[index % photos.count])) {
      (minimal ? NookColors.warmBlack : NookColors.offWhite).overlay(
        Image(systemName: "cup.and.saucer")
          .foregroundStyle(minimal ? NookColors.caramelSoft : NookColors.mocha))
    }
    .frame(width: width, height: height).clipped()
    .overlay {
      RoundedRectangle(cornerRadius: 17).stroke(
        index == focus ? NookColors.mocha : .white.opacity(0.1),
        lineWidth: index == focus ? 2 : 0.6)
    }
    .overlay(alignment: .bottomTrailing) {
      if index == focus {
        Circle().fill(NookColors.mocha).frame(width: 8, height: 8).padding(10)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    .brightness(index == focus ? 0.08 : 0)
    .saturation(minimal ? 1 : (index == focus ? 1 : 0.72))
    .opacity(active ? (minimal ? 1 : (index == focus ? 1 : 0.62)) : 0)
    .animation(NookMotion.spring.delay(Double(index) * 0.035), value: active)
    .animation(NookMotion.spring, value: focus)
  }

  private var midpointLabel: String {
    let mine = ownCity ?? "tu zona"
    let theirs = person?.city ?? mine
    return mine == theirs ? mine : "Punto medio"
  }

}

private struct NookAILogo: View {
  @State private var thinking = false
  var body: some View {
    HStack(spacing: 8) {
      NookCoffeeLogo(size: 34, animated: true)
      VStack(alignment: .leading, spacing: 0) {
        Text("NOOK").font(.system(size: 11, weight: .heavy, design: .default)).tracking(1.4)
        Text("IA").font(.system(size: 10, weight: .heavy, design: .default)).tracking(2.4)
          .foregroundStyle(NookColors.mocha)
      }
      Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
        .foregroundStyle(NookColors.mocha)
        .symbolEffect(.pulse, options: .repeating, value: thinking)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(NookColors.warmBlack.opacity(0.58), in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8))
    .onAppear { thinking = true }
  }
}

struct NookCoffeeShopCard: View {
  let shop: CoffeeShop
  let namespace: Namespace.ID
  var recommended = false
  let choose: () -> Void
  let details: () -> Void
  @State private var selectedPhoto = 0
  private var gallery: [String] {
    var values = shop.photoUrls ?? []
    if let cover = shop.photoUrl, !values.contains(cover) { values.insert(cover, at: 0) }
    return values.isEmpty ? [""] : values
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        TabView(selection: $selectedPhoto) {
          ForEach(Array(gallery.enumerated()), id: \.offset) { index, photo in
            ShopImage(url: photo.isEmpty ? nil : photo, seed: "\(shop.name)-\(index)")
              .frame(maxWidth: .infinity).frame(height: 198)
              .tag(index)
          }
        }
        .frame(height: 198)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .matchedGeometryEffect(id: "image-\(shop.id)", in: namespace)
        if gallery.count > 1 {
          HStack(spacing: 5) {
              ForEach(gallery.indices, id: \.self) { index in
                Capsule()
                  .fill(.white.opacity(index == selectedPhoto ? 0.95 : 0.38))
                  .frame(width: index == selectedPhoto ? 14 : 5, height: 5)
              }
          }
          .padding(12)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          .animation(.snappy(duration: 0.22), value: selectedPhoto)
          .allowsHitTesting(false)
        }
        if recommended {
          Label("ELECCIÓN NOOK", systemImage: "sparkles")
            .font(.system(size: 10, weight: .bold, design: .default)).tracking(0.9)
            .foregroundStyle(NookColors.inverseText)
            .padding(.horizontal, 11).frame(height: 30)
            .background(NookColors.espresso.opacity(0.92), in: Capsule())
            .padding(12)
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(shop.name).font(NookTypography.business(22, weight: .bold)).tracking(-0.25)
            .foregroundStyle(NookColors.primaryCoffeePressed)
            .lineLimit(1).minimumScaleFactor(0.78)
          Spacer(minLength: 4)
          if let openNow = shop.openNow {
            Text(openNow ? "Abierto" : "Cerrado")
              .font(.system(size: 11, weight: .bold, design: .default))
              .foregroundStyle(openNow ? Color.green.opacity(0.82) : NookColors.error)
          }
        }

        HStack(spacing: 8) {
          if let rating = shop.rating {
            HStack(spacing: 4) {
              Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
              Text(rating.formatted(.number.precision(.fractionLength(1))))
              if let reviews = shop.reviewCount { Text("(\(reviews))").foregroundStyle(NookColors.warmGray) }
            }.foregroundStyle(NookColors.mocha)
            metadataDot
          }
          Label(distanceText, systemImage: "location.fill")
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
        .foregroundStyle(NookColors.espresso.opacity(0.68))
        .lineLimit(1)

        HStack(spacing: 8) {
          Image(systemName: "mappin.and.ellipse").foregroundStyle(NookColors.mocha)
          Text(shop.neighborhood ?? shop.address).lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium, design: .default))
        .foregroundStyle(NookColors.espresso.opacity(0.64))

        Label(shop.todayHoursText ?? "Horario no disponible", systemImage: "clock")
          .font(.system(size: 12, weight: .semibold, design: .default))
          .foregroundStyle(NookColors.espresso.opacity(0.72)).lineLimit(1)

        Text(shop.description ?? shop.nookEditorialFallback)
          .font(.system(size: 13, weight: .regular, design: .default))
          .foregroundStyle(NookColors.espresso.opacity(0.62)).lineLimit(2).lineSpacing(2)

        HStack {
          Button("Más información", action: details)
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(NookColors.espresso.opacity(0.62))
          Spacer()
          Button(action: choose) {
            Text("Elegir").font(.system(size: 14, weight: .bold, design: .default))
              .foregroundStyle(NookColors.inverseText)
              .padding(.horizontal, 20).frame(height: 38)
              .background(NookColors.espresso, in: Capsule())
          }.buttonStyle(.plain)
        }
        .padding(.top, 2)
      }
      .padding(15)
      .frame(height: 194, alignment: .top)
    }
    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .shadow(color: NookColors.espresso.opacity(0.09), radius: 18, y: 7)
  }

  private var metadataDot: some View {
    Circle().fill(NookColors.espresso.opacity(0.22)).frame(width: 3, height: 3)
  }
  private var distanceText: String {
    shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km"
  }
}

private struct CoffeePlaceCardSkeleton: View {
  @State private var pulse = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      skeleton(radius: 0).frame(height: 198)
      VStack(alignment: .leading, spacing: 11) {
        skeleton().frame(width: 210, height: 22)
        skeleton().frame(width: 155, height: 12)
        skeleton().frame(maxWidth: .infinity).frame(height: 12)
        HStack {
          skeleton().frame(width: 98, height: 12)
          Spacer()
          skeleton(radius: 19).frame(width: 78, height: 38)
        }.padding(.top, 8)
      }.padding(15).frame(height: 194, alignment: .top)
    }
    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .shadow(color: NookColors.espresso.opacity(0.07), radius: 14, y: 6)
    .opacity(pulse ? 0.58 : 1)
    .onAppear {
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
    }
  }
  private func skeleton(radius: CGFloat = 7) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(NookColors.espresso.opacity(0.09))
  }
}

struct ShopImage: View {
  let url: String?
  let seed: String
  var body: some View {
    NookRemoteImage(url: resolvedURL) {
      NookImageFallback()
    }.clipped()
  }
  private var resolvedURL: URL? {
    guard let url, !url.isEmpty else { return nil }
    if url.hasPrefix("/") {
      guard var components = URLComponents(
        url: AppConfiguration.apiURL, resolvingAgainstBaseURL: false) else { return nil }
      components.path = url
      components.query = nil
      return components.url
    }
    return URL(string: url)
  }
}

struct CoffeeShopDetail: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  let shop: CoffeeShop
  let matches: [Match]
  let namespace: Namespace.ID
  @State private var propose = false
  @State private var mapPosition: MapCameraPosition = .automatic
  @State private var coordinate: CLLocationCoordinate2D?
  var body: some View {
    ZStack {
      NookInteriorBackdrop()
      ScrollView {
        VStack(spacing: 0) {
          ZStack(alignment: .topLeading) {
            ShopImage(url: shop.photoUrl, seed: shop.name).frame(height: 270)
            LinearGradient(colors: [NookColors.warmBlack.opacity(0.38), .clear], startPoint: .top, endPoint: .center)
            Button { dismiss() } label: {
              Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).padding(16)
          }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 14).padding(.top, 8)
          VStack(alignment: .center, spacing: 18) {
            VStack(spacing: 11) {
              Text(shop.name).font(NookTypography.business(30, weight: .bold)).tracking(-0.3)
                .multilineTextAlignment(.center)
              HStack(spacing: 15) {
                if let rating = shop.rating { Label(rating.formatted(), systemImage: "star.fill") }
                Label(distanceLabel, systemImage: "location")
                Text(shop.vibeLabel)
              }.font(.caption.weight(.semibold)).foregroundStyle(NookColors.espresso.opacity(0.6))
            }
            Button { propose = true } label: {
              Text("Elegir").font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(NookColors.inverseText).frame(width: 148, height: 46)
                .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.plain)
            Rectangle().fill(NookColors.espresso.opacity(0.09)).frame(height: 1)
            Text(editorialDescription).font(.system(size: 17, weight: .regular, design: .default))
              .foregroundStyle(NookColors.espresso.opacity(0.76)).lineSpacing(5).multilineTextAlignment(.center)
            HStack(spacing: 20) {
              if let hours = shop.openingHours { fact("clock", hours) }
              fact("location", shop.neighborhood ?? distanceLabel)
            }
            ZStack(alignment: .bottomTrailing) {
              Map(position: $mapPosition) { if let coordinate { Marker(shop.name, coordinate: coordinate) } }
                .frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 22))
              Button { openMaps() } label: {
                Label("Mapas", systemImage: "arrow.up.right").font(.caption.weight(.semibold))
                  .padding(.horizontal, 12).frame(height: 38).background(.ultraThinMaterial, in: Capsule())
              }.buttonStyle(.plain).padding(10)
            }
            Text(shop.address).font(.caption).foregroundStyle(NookColors.espresso.opacity(0.5)).multilineTextAlignment(.center)
          }.foregroundStyle(NookColors.espresso).padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 38)
            .background(NookColors.cream, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
            .offset(y: -28).padding(.bottom, -28)
        }
      }
    }.onAppear {
      Task { await locateShop() }
    }.sheet(isPresented: $propose) { ProposalSheet(shop: shop, matches: matches) }
  }
  private var editorialDescription: String {
    shop.description ?? shop.nookEditorialFallback
  }
  private var distanceLabel: String { shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km" }
  private func openMaps() {
    let query = shop.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shop.address
    if let url = URL(string: "https://maps.apple.com/?q=\(query)") { openURL(url) }
  }
  private func info(_ icon: String, _ value: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(NookColors.mocha).frame(width: 22)
      Text(value).font(.system(size: 16, weight: .medium, design: .default))
      Spacer()
    }.padding(.vertical, 14).overlay(alignment: .bottom) { Rectangle().fill(NookColors.espresso.opacity(0.08)).frame(height: 1) }
  }
  private func centeredInfo(_ icon: String, _ value: String) -> some View {
    Label(value, systemImage: icon).font(.subheadline.weight(.medium))
      .foregroundStyle(NookColors.espresso.opacity(0.68)).multilineTextAlignment(.center)
  }
  private func fact(_ icon: String, _ value: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(NookColors.mocha)
      Text(value).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
  }
  private func locateShop() async {
    guard let place = try? await CLGeocoder().geocodeAddressString(shop.address).first,
      let value = place.location?.coordinate else { return }
    coordinate = value
    mapPosition = .region(MKCoordinateRegion(center: value, latitudinalMeters: 900, longitudinalMeters: 900))
  }
}

struct ProposalSheet: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let shop: CoffeeShop
  let matches: [Match]
  var isNookChoice = false
  var existingProposal: CoffeeDate? = nil
  @State private var step = 0
  @State private var selectedMatch: UUID?
  @State private var payment = PaymentPreference.split
  @State private var date = Date().addingTimeInterval(86_400)
  @State private var selectedSlot: Date?
  @State private var confirmed = false
  @State private var sending = false
  @State private var submitError: String?
  @State private var availabilityError: String?
  @State private var idempotencyKey = UUID()
  var body: some View {
    NavigationStack {
      ZStack {
        Color.white.ignoresSafeArea()
        if confirmed {
          proposalSent
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        } else {
          VStack(spacing: 12) {
          proposalTopBar
          stepProgress
          ScrollView {
            if needsPersonChoice && step == 0 {
              choiceStep("¿Con quién?", "Elige tu compañero de café") {
                if matches.isEmpty {
                  NookEmptyState(icon: "person.2", title: "Aún no hay personas", text: "Cuando tengáis café, podrás proponer un lugar desde aquí.")
                }
                ForEach(matches) { match in
                  Button {
                    Haptics.selection()
                    withAnimation(NookMotion.spring) { selectedMatch = match.id }
                  } label: {
                    HStack(spacing: 13) {
                      ProfileImage(url: match.person.photos.first?.url, name: match.person.name)
                        .frame(width: 50, height: 50).clipShape(Circle())
                      VStack(alignment: .leading, spacing: 3) {
                        Text(match.person.name).font(.headline)
                        Text(match.person.bio).font(.caption).foregroundStyle(NookColors.warmGray).lineLimit(1)
                      }
                      Spacer()
                      Image(systemName: selectedMatch == match.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(NookColors.mocha)
                    }.foregroundStyle(NookColors.espresso).padding(.vertical, 11)
                      .overlay(alignment: .bottom) {
                        Rectangle().fill(NookColors.espresso.opacity(0.09)).frame(height: 0.7)
                      }
                  }.buttonStyle(.plain)
                }
              }
            } else if flowStep == 0 {
              choiceStep("¿Qué día os va bien?", "Un día para parar y tomar café") {
                DatePicker("Fecha", selection: $date, in: Date()..., displayedComponents: .date)
                  .datePickerStyle(.graphical).tint(NookColors.mocha)
                  .padding(.horizontal, -6)
                if let hours = shop.openingHours {
                  Label(hours, systemImage: "clock").font(.caption.weight(.semibold))
                    .foregroundStyle(NookColors.mocha)
                } else {
                  Label("Confirma el horario con la cafetería", systemImage: "info.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(NookColors.warmGray)
                }
              }
            } else if flowStep == 1 {
              choiceStep("¿A qué hora?", shop.openingHours == nil ? "Elige vuestro momento" : "Estas horas encajan con el café") {
                if let slots = shop.availableTimes(on: date) {
                  if slots.isEmpty {
                    NookEmptyState(icon: "clock.badge.xmark", title: "Cerrado este día", text: "Elige otro día para ver sus franjas disponibles.")
                  } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                      ForEach(slots, id: \.self) { slot in
                        Button {
                          selectedSlot = slot
                          date = slot
                        } label: {
                          Text(slot.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 14, weight: .bold, design: .default))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .foregroundStyle(selectedSlot == slot ? NookColors.inverseText : NookColors.espresso)
                            .background(selectedSlot == slot ? NookColors.mocha : NookColors.espresso.opacity(0.06), in: Capsule())
                            .overlay(Capsule().stroke(NookColors.espresso.opacity(selectedSlot == slot ? 0 : 0.10)))
                        }.buttonStyle(.plain)
                      }
                    }
                  }
                } else {
                  DatePicker("Hora", selection: $date, in: Date().addingTimeInterval(15 * 60)..., displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                }
              }
            } else if flowStep == 2 {
              choiceStep("¿Quién invita?", "Dejadlo claro antes de pedir el primer café") {
                VStack(spacing: 11) {
                  paymentChoice(
                    .split, icon: "person.2.fill", title: "Cada uno paga lo suyo",
                    subtitle: "Fácil, natural y sin cuentas pendientes")
                  paymentChoice(
                    .iInvite, icon: "gift.fill", title: "Invito yo",
                    subtitle: "Este primer café corre de mi cuenta")
                  paymentChoice(
                    .theyInvite, icon: "cup.and.saucer.fill", title: "Invitas tú",
                    subtitle: "La otra persona se encarga del café")
                }
              }
            } else {
              choiceStep("¿Listos para el café?", "Esto es lo que recibirá \(selectedPersonName)") {
                  VStack(alignment: .leading, spacing: 0) {
                    if isNookChoice {
                      Label("ELECCIÓN NOOK", systemImage: "sparkles")
                        .font(.caption.bold()).tracking(1).foregroundStyle(NookColors.mocha)
                        .padding(.bottom, 12)
                    }
                    reviewRow("person.crop.circle.fill", selectedPersonName)
                    reviewRow("cup.and.saucer.fill", shop.name)
                    reviewRow("calendar", date.formatted(date: .abbreviated, time: .shortened))
                    reviewRow("eurosign.circle.fill", paymentDisplayTitle)
                  }
                  .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          .contentMargins(.horizontal, 10, for: .scrollContent)
          .scrollIndicators(.hidden)
          .frame(maxHeight: .infinity)
            NookButton(
              title: sending ? "PREPARANDO EL CAFÉ…" : (isReview ? "ENVIAR PROPUESTA" : "SIGUIENTE"),
              icon: isReview ? "paperplane" : "arrow.right", isLoading: sending
            ) {
              guard !sending else { return }
              if !isReview {
                advanceToNextStep()
              } else if let match = selectedMatch {
                Task {
                  sending = true
                  do {
                    let persisted: CoffeeDate
                    if let existingProposal {
                      persisted = try await app.repository.counterDate(
                        existingProposal.id, shop: shop.id, date: date, payment: payment)
                    } else {
                      persisted = try await app.repository.propose(
                        match: match, shop: shop.id, date: date, payment: payment,
                        nookChoice: isNookChoice, idempotencyKey: idempotencyKey)
                    }
                    app.coffeeProposalPersisted(persisted)
                    Haptics.success()
                    NookSoundManager.shared.play(.proposal)
                    try? await Task.sleep(for: .milliseconds(850))
                    withAnimation(NookMotion.spring) { confirmed = true; sending = false }
                  } catch {
                    sending = false
                    submitError = NookErrorCopy.message(
                      for: error, fallback: "No hemos podido enviar la propuesta. Revisa los datos e inténtalo de nuevo.")
                  }
                }
              }
            }.disabled(!canContinue)
          }
          .padding(14)
          // The custom full-bleed backdrop makes the sheet content extend beneath
          // the translucent navigation bar. Reserve its visual height so the step
          // indicator and first heading never collide with the toolbar.
          .safeAreaPadding(.top, 0)
          .safeAreaPadding(.bottom, 10)
          .toolbar(.hidden, for: .navigationBar)
        }
        if sending { CoffeeBeanTransition().allowsHitTesting(false).transition(.opacity) }
      }
    }
    .preferredColorScheme(.light)
    .alert("No hemos podido enviarlo", isPresented: Binding(
      get: { submitError != nil }, set: { if !$0 { submitError = nil } }
    )) { Button("Entendido") { submitError = nil } } message: { Text(submitError ?? "") }
    .alert("Cafetería cerrada", isPresented: Binding(
      get: { availabilityError != nil }, set: { if !$0 { availabilityError = nil } }
    )) {
      Button("Elegir otro día") { availabilityError = nil }
    } message: { Text(availabilityError ?? "") }
    .onChange(of: date) { _, _ in
      if flowStep == 0 { selectedSlot = nil }
    }
    .onAppear {
      selectedMatch = existingProposal?.matchId ?? app.selectedCoffeeMatch
      if let existingProposal,
        let proposedDate = ISO8601DateFormatter.nook.date(from: existingProposal.proposedAt)
      {
        date = proposedDate
        payment = existingProposal.paymentPreference
      }
    }
  }
  private var needsPersonChoice: Bool { app.selectedCoffeeMatch == nil }

  private var proposalTopBar: some View {
    HStack(spacing: 12) {
      Button {
        if step == 0 { dismiss() }
        else { withAnimation(NookMotion.spring) { step -= 1 } }
      } label: {
        Image(systemName: step == 0 ? "xmark" : "chevron.left")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(NookColors.espresso)
          .frame(width: 36, height: 36)
          .background(NookColors.espresso.opacity(0.06), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(step == 0 ? "Cerrar" : "Volver")

      Text(shop.name)
        .font(NookTypography.business(21, weight: .bold))
        .foregroundStyle(NookColors.primaryCoffeePressed)
        .lineLimit(2)
        .minimumScaleFactor(0.76)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 44)
  }

  private var flowStep: Int { step - (needsPersonChoice ? 1 : 0) }
  private var totalSteps: Int { needsPersonChoice ? 5 : 4 }
  private var isReview: Bool { step == totalSteps - 1 }
  private var stepIcons: [String] {
    needsPersonChoice
      ? ["person.fill", "calendar", "clock.fill", "eurosign", "paperplane.fill"]
      : ["calendar", "clock.fill", "eurosign", "paperplane.fill"]
  }
  private var stepProgress: some View {
    HStack(spacing: 7) {
      ForEach(0..<totalSteps, id: \.self) { index in
        ZStack {
          Circle()
            .fill(index <= step ? NookColors.espresso : NookColors.espresso.opacity(0.07))
          Image(systemName: index < step ? "checkmark" : stepIcons[index])
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(index <= step ? NookColors.inverseText : NookColors.espresso.opacity(0.38))
        }
        .frame(width: index == step ? 34 : 28, height: index == step ? 34 : 28)
        .shadow(color: index == step ? NookColors.espresso.opacity(0.16) : .clear, radius: 8, y: 4)
        if index < totalSteps - 1 {
          Capsule()
            .fill(index < step ? NookColors.mocha : NookColors.espresso.opacity(0.10))
            .frame(height: 2)
        }
      }
    }
    .padding(.horizontal, 4).frame(height: 38)
    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: step)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Paso \(step + 1) de \(totalSteps)")
  }
  private var canContinue: Bool {
    if needsPersonChoice && step == 0 { return selectedMatch != nil }
    if flowStep == 1, shop.availableTimes(on: date) != nil { return selectedSlot != nil }
    return date.timeIntervalSinceNow > 15 * 60
  }
  private func advanceToNextStep() {
    if flowStep == 0, let slots = shop.availableTimes(on: date), slots.isEmpty {
      selectedSlot = nil
      availabilityError = "Ese día el establecimiento está cerrado. Selecciona otro día para continuar."
      return
    }
    if flowStep == 1, let slots = shop.availableTimes(on: date),
      selectedSlot.map({ !slots.contains($0) }) ?? true
    {
      selectedSlot = nil
      availabilityError = "La hora elegida ya no está disponible. Vuelve a seleccionar el día y la hora."
      withAnimation(NookMotion.spring) { step = max(0, step - 1) }
      return
    }
    withAnimation(NookMotion.spring) { step += 1 }
  }
  private var proposalSent: some View {
    GeometryReader { proxy in
    ScrollView {
    VStack(spacing: 16) {
      VStack(spacing: 7) {
        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
          .foregroundStyle(NookColors.inverseText).frame(width: 34, height: 34)
          .background(NookColors.espresso, in: Circle())
        Text("Propuesta enviada").font(NookTypography.display(38))
          .tracking(-1)
        Text("Ahora toca esperar a que \(selectedPersonName) confirme.")
          .font(.subheadline).foregroundStyle(NookColors.warmGray).multilineTextAlignment(.center)
      }

      if let person = selectedPerson {
        ProposalRecipientCard(person: person)
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      ZStack(alignment: .bottomLeading) {
        ShopImage(url: shop.photoUrl, seed: shop.name).frame(height: 174)
        LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.82)], startPoint: .top, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 5) {
          if isNookChoice {
            Label("ELECCIÓN NOOK", systemImage: "sparkles")
              .font(.caption2.bold()).tracking(1).padding(.horizontal, 9).padding(.vertical, 6)
              .foregroundStyle(NookColors.inverseText).background(NookColors.mocha, in: Capsule())
          }
          PreparingCoffeeLabel()
          Text(shop.name).font(.system(size: 23, weight: .bold, design: .default)).lineLimit(1)
          Label(shop.address, systemImage: "location").font(.caption.weight(.medium)).lineLimit(1)
        }.foregroundStyle(.white).padding(16)
      }
      .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
      .shadow(color: NookColors.espresso.opacity(0.13), radius: 18, y: 9)

      VStack(alignment: .leading, spacing: 11) {
          Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
          Label(payment.title, systemImage: "cup.and.saucer.fill")
          Divider()
          WaitingConfirmationStatus()
      }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
      Spacer(minLength: 18)
      NookButton(title: "VER MIS CAFÉS", icon: "calendar.badge.clock") {
        dismiss()
        Task { @MainActor in
          await Task.yield()
          app.selectedCoffeeMatch = nil
          app.selectedTab = 1
          app.coffeeProposalPersisted()
        }
      }
      NookButton(title: "VOLVER A DESCUBRIR", icon: "person.2", secondary: true) {
        app.selectedTab = 0
        dismiss()
      }
    }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 18)
      .frame(minHeight: proxy.size.height, alignment: .top)
    }.scrollIndicators(.hidden)
    }
  }
  private var selectedPersonName: String {
    selectedPerson?.name ?? "la otra persona"
  }
  private var selectedPerson: DiscoverProfile? {
    matches.first(where: { $0.id == selectedMatch })?.person
  }
  private func choiceStep<C: View>(
    _ title: String, _ subtitle: String, @ViewBuilder content: () -> C
  ) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text("PASO \(step + 1) DE \(totalSteps)")
          .font(.system(size: 9, weight: .bold, design: .default)).tracking(1.5)
          .foregroundStyle(NookColors.mocha)
        Text(title).font(NookTypography.business(31, weight: .bold)).tracking(-0.45)
        Text(subtitle).font(NookTypography.secondary).foregroundStyle(NookColors.textSecondary)
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).transition(
      .move(edge: .trailing).combined(with: .opacity))
  }
  private func reviewRow(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 13) {
      Image(systemName: icon).font(.system(size: 15, weight: .semibold))
        .foregroundStyle(NookColors.mocha).frame(width: 24)
      Text(text).lineLimit(2)
      Spacer()
    }
    .padding(.vertical, 15)
    .overlay(alignment: .bottom) {
      Rectangle().fill(NookColors.espresso.opacity(0.09)).frame(height: 0.7)
    }
  }
  private var paymentDisplayTitle: String {
    switch payment {
    case .split: "Cada uno paga lo suyo"
    case .iInvite: "Invito yo"
    case .theyInvite: "Invitas tú"
    case .decideThere: "Lo decidimos allí"
    }
  }
  private func paymentChoice(
    _ value: PaymentPreference, icon: String, title: String, subtitle: String
  ) -> some View {
    let selected = payment == value
    return Button {
      Haptics.selection()
      withAnimation(NookMotion.spring) { payment = value }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(selected ? NookColors.inverseText : NookColors.mocha)
          .frame(width: 44, height: 44)
          .background(selected ? NookColors.mocha : NookColors.primaryCoffeeSoft.opacity(0.55), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(NookColors.primaryCoffeePressed)
          Text(subtitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NookColors.textSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(selected ? NookColors.mocha : NookColors.border)
      }
      .padding(.horizontal, 15)
      .frame(minHeight: 76)
      .background(
        selected ? NookColors.primaryCoffeeSoft.opacity(0.34) : Color.white,
        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .stroke(selected ? NookColors.mocha.opacity(0.72) : NookColors.border.opacity(0.7), lineWidth: selected ? 1.5 : 1)
      }
      .shadow(color: selected ? NookColors.mocha.opacity(0.12) : NookColors.espresso.opacity(0.035), radius: 12, y: 5)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptics.selection()
      withAnimation(NookMotion.playful) { action() }
    } label: {
      HStack {
        Text(title).font(.title3.bold())
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2)
      }.foregroundStyle(selected ? NookColors.offWhite : NookColors.espresso).padding(20)
        .background(
          selected ? NookColors.espresso : NookColors.offWhite,
          in: RoundedRectangle(cornerRadius: NookRadius.medium)
        ).scaleEffect(selected ? 1.02 : 1)
    }
  }
}

private struct ProposalRecipientCard: View {
  let person: DiscoverProfile
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      GeometryReader { proxy in
        ProfileImage(url: person.photos.first?.url, name: person.name, alignment: .center)
          .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
          .clipped()
      }
      LinearGradient(
        colors: [NookColors.warmBlack.opacity(0.20), .clear, NookColors.warmBlack.opacity(0.92)],
        startPoint: .top, endPoint: .bottom)

      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("DESTINATARIO").font(.system(size: 9, weight: .bold, design: .default)).tracking(1.4)
            .foregroundStyle(.white.opacity(0.76))
          Spacer()
          Label("ENVIADA", systemImage: "checkmark")
            .font(.system(size: 9, weight: .bold, design: .default)).tracking(0.8)
            .foregroundStyle(NookColors.inverseText).padding(.horizontal, 9).frame(height: 27)
            .background(NookColors.mocha, in: Capsule())
        }
        Spacer()
        Text(person.name).font(NookTypography.display(32)).tracking(-0.45).lineLimit(1)
        Label("Ahora espera su respuesta", systemImage: "cup.and.saucer")
          .font(.system(size: 12, weight: .semibold, design: .default))
          .foregroundStyle(.white.opacity(0.78)).padding(.top, 3)
      }.foregroundStyle(.white).padding(15)
    }
    .frame(maxWidth: .infinity).frame(height: 174)
    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.14), lineWidth: 0.8))
    .shadow(color: NookColors.warmBlack.opacity(0.18), radius: 16, y: 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Propuesta enviada a \(person.name). Esperando su respuesta")
  }
}

private struct WaitingConfirmationStatus: View {
  @State private var breathing = false
  var body: some View {
    HStack(spacing: 13) {
      ZStack {
        Circle().stroke(NookColors.amber.opacity(0.26), lineWidth: 2)
          .scaleEffect(breathing ? 1.28 : 0.82).opacity(breathing ? 0 : 1)
        Circle().fill(NookColors.amber.opacity(0.12))
        Image(systemName: "hourglass").font(.system(size: 13, weight: .bold))
          .foregroundStyle(NookColors.amber)
          .symbolEffect(.pulse, options: .repeating)
      }.frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text("Esperando confirmación").font(.subheadline.bold())
          .foregroundStyle(NookColors.espresso)
        Text("Te avisaremos cuando responda").font(.caption.weight(.medium))
          .foregroundStyle(NookColors.warmGray)
      }
      Spacer(minLength: 4)
      HStack(spacing: 3) {
        ForEach(0..<3, id: \.self) { index in
          Circle().fill(NookColors.amber).frame(width: 4, height: 4)
            .opacity(breathing ? 1 : 0.22)
            .animation(
              .easeInOut(duration: 0.72).repeatForever().delay(Double(index) * 0.16),
              value: breathing)
        }
      }
    }
    .padding(.horizontal, 12).frame(minHeight: 52)
    .background(NookColors.amber.opacity(0.065), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NookColors.amber.opacity(0.16), lineWidth: 0.8))
    .onAppear {
      withAnimation(.easeOut(duration: 1.25).repeatForever(autoreverses: false)) {
        breathing = true
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct PreparingCoffeeLabel: View {
  @State private var active = false
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "cup.and.saucer.fill").font(.system(size: 11, weight: .semibold))
      Text("PREPARANDO CAFÉ").font(.system(size: 10, weight: .bold, design: .default)).tracking(1.2)
      HStack(spacing: 3) {
        ForEach(0..<3) { index in
          Circle().fill(.white).frame(width: 3, height: 3)
            .opacity(active ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.65).repeatForever().delay(Double(index) * 0.18), value: active)
        }
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(.ultraThinMaterial, in: Capsule())
    .onAppear { active = true }
  }
}

struct CoffeeBeanTransition: View {
  @State private var burst = false
  private let offsets: [CGSize] = [
    .init(width: -145, height: -220), .init(width: -72, height: -260),
    .init(width: 40, height: -245), .init(width: 138, height: -190),
    .init(width: -165, height: -70), .init(width: 158, height: -25),
    .init(width: -128, height: 130), .init(width: -45, height: 215),
    .init(width: 62, height: 225), .init(width: 142, height: 120),
  ]
  var body: some View {
    ZStack {
      NookColors.cream.opacity(burst ? 0.92 : 0).ignoresSafeArea()
      ForEach(offsets.indices, id: \.self) { index in
        CoffeeBean()
          .frame(width: 24, height: 36)
          .rotationEffect(.degrees(Double(index * 37) + (burst ? 120 : 0)))
          .offset(burst ? offsets[index] : .zero)
          .scaleEffect(burst ? 0.75 : 0.15)
          .opacity(burst ? 0 : 1)
          .animation(.easeOut(duration: 0.75).delay(Double(index) * 0.025), value: burst)
      }
      Image(systemName: "paperplane")
        .font(.system(size: 29, weight: .medium)).foregroundStyle(NookColors.espresso)
        .scaleEffect(burst ? 1.18 : 0.72).opacity(burst ? 0 : 1)
        .animation(.easeOut(duration: 0.65), value: burst)
    }.onAppear { burst = true }
  }
}

struct CoffeeBean: View {
  var body: some View {
    ZStack {
      Capsule().fill(NookColors.mocha)
      Capsule().stroke(NookColors.latte.opacity(0.75), lineWidth: 1.5)
        .frame(width: 3, height: 23).rotationEffect(.degrees(12))
    }.shadow(color: NookColors.warmBlack.opacity(0.14), radius: 3, y: 2)
  }
}

struct WaitingCoffeeAnimation: View {
  @State private var orbit = false
  @State private var pulse = false
  var body: some View {
    ZStack {
      Circle().stroke(NookColors.espresso.opacity(0.09), lineWidth: 1).frame(width: 122, height: 122)
      ForEach(0..<5) { index in
        CoffeeBean().frame(width: 10, height: 16).offset(y: -61)
          .rotationEffect(.degrees(Double(index) * 72 + (orbit ? 360 : 0)))
      }
      Image(systemName: "cup.and.saucer").font(.system(size: 38, weight: .light)).foregroundStyle(NookColors.espresso)
        .scaleEffect(pulse ? 1.04 : 0.96)
    }.frame(width: 150, height: 150)
      .onAppear {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { orbit = true }
        withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }
      }
  }
}
