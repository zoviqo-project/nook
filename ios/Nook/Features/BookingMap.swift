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
  @Published var shops: [CoffeeShop] = []
  @Published var matches: [Match] = []
  @Published var loading = false
  @Published var meetingArea: String?
  @Published var error: String?
  @Published var mapLoading = false
  @Published private(set) var origin: CafeSearchOrigin?
  @Published var selectedCafe: CoffeeShop?
  @Published var radiusKm = 2.0
  private var searchTask: Task<Void, Never>?

  var searchPoint: GeoPoint? { origin?.point }

  func prepare(_ repo: any NookRepository) async {
    if matches.isEmpty { matches = (try? await repo.matches()) ?? [] }
  }

  func useCurrentLocation(_ location: CLLocation, repo: any NookRepository) async {
    try? await repo.updateLocation(latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy,
      capturedAt: location.timestamp)
    let point = GeoPoint(location.coordinate)
    origin = .currentLocation(point)
    meetingArea = await locality(for: point.coordinate, fallback: "Tu ubicación")
    await search(repo, showMainLoader: shops.isEmpty)
  }

  func useMidpoint(
    matchID: UUID, currentLocation: CLLocation, repo: any NookRepository
  ) async {
    await prepare(repo)
    try? await repo.updateLocation(latitude: currentLocation.coordinate.latitude,
      longitude: currentLocation.coordinate.longitude, accuracy: currentLocation.horizontalAccuracy,
      capturedAt: currentLocation.timestamp)
    let point: GeoPoint
    do {
      point = try await repo.meetingPoint(matchID: matchID)
    } catch {
      guard let city = matches.first(where: { $0.id == matchID })?.person.city,
        let place = try? await CLGeocoder().geocodeAddressString(city).first,
        let other = place.location?.coordinate else {
        await useCurrentLocation(currentLocation, repo: repo)
        return
      }
      point = GeographicMath.midpoint(GeoPoint(currentLocation.coordinate), GeoPoint(other))
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
      error = "Necesitamos una ubicación válida para buscar cafeterías."
      return
    }
    if showMainLoader { loading = true } else { mapLoading = true }
    defer { loading = false; mapLoading = false }
    error = nil
    do {
      let point = origin.point
      let found = try await repo.shops(
        latitude: point.latitude, longitude: point.longitude, radiusKm: radiusKm)
      shops = found.sorted(by: usefulOrder)
      #if DEBUG
        print("[NOOK CAFE SEARCH] Origin: \(origin.logName) latitude=\(point.latitude) longitude=\(point.longitude) radius=\(GeographicMath.meters(fromKilometers: radiusKm))m results=\(shops.count)")
      #endif
    } catch {
      shops = []
      self.error = "No hemos podido obtener cafeterías reales. Comprueba la conexión y vuelve a intentarlo."
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
  var body: some View {
    ZStack(alignment: .top) {
      NookBackground()
      if searching && app.selectedCoffeeMatch != nil {
        SmartCoffeeSearch(
          person: targetPerson, ownName: app.me?.name, ownCity: app.me?.city,
          ownPhoto: app.me?.photos.first?.url,
          meetingArea: searchLabel ?? vm.meetingArea,
          title: searchTitle
        ).frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
      } else if location.denied && app.selectedCoffeeMatch == nil && !otherPlaceMode {
        LocationPermissionState(openSettings: location.openSettings)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.bottom, 66)
      } else {
        VStack(spacing: 8) {
          placesHeader
          placeModeSelector
            .padding(.horizontal, 12)
          Group {
            if showMap { mapView } else { listView }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, showMap ? 66 : 82)
        .transition(.opacity)
      }
      if let shop = celebratedShop {
        NookChoiceCelebration(shopName: shop.name)
          .transition(.opacity.combined(with: .scale(scale: 0.94))).zIndex(10)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      let midpointMode = app.selectedCoffeeMatch != nil
      if midpointMode { withAnimation(NookMotion.fast) { app.tabBarHidden = true } }
      location.request()
      for _ in 0..<50 where location.location == nil && !location.denied {
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard let current = location.location, !location.denied else {
        searching = false
        if !location.denied { vm.error = location.locationError ?? "Seguimos buscando tu ubicación…" }
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
      withAnimation(.easeInOut(duration: 0.62)) { searching = false }
      withAnimation(NookMotion.fast) { app.tabBarHidden = false }
      withAnimation(NookMotion.spring) { appeared = true }
    }.sheet(item: $proposalShop) { shop in
      ProposalSheet(shop: shop, matches: vm.matches, isNookChoice: shop.id == vm.shops.first?.id)
    }
    .sheet(isPresented: $showAreaPicker) { areaPicker }
    .onDisappear { app.tabBarHidden = false }
    .onChange(of: location.location?.timestamp) { _, timestamp in
      guard timestamp != nil, !locationHandled, vm.origin == nil, let current = location.location else { return }
      locationHandled = true
      Task {
        if let matchID = app.selectedCoffeeMatch {
          await vm.useMidpoint(matchID: matchID, currentLocation: current, repo: app.repository)
        } else {
          await vm.useCurrentLocation(current, repo: app.repository)
        }
        withAnimation(.easeInOut(duration: 0.35)) { searching = false }
        withAnimation(NookMotion.fast) { app.tabBarHidden = false }
        withAnimation(NookMotion.spring) { appeared = true }
      }
    }
  }
  private var targetPerson: DiscoverProfile? {
    guard let selected = app.selectedCoffeeMatch else { return nil }
    return vm.matches.first(where: { $0.id == selected })?.person
  }
  private var placesHeader: some View {
    NookHeader(
      eyebrow: otherPlaceMode ? "OTRO LUGAR" : (targetPerson == nil ? "CERCA DE TI" : "PUNTO MEDIO"),
      title: "Elige el lugar",
      actionIcon: showMap ? "rectangle.grid.1x2.fill" : "map.fill",
      actionLabel: showMap ? "Ver lista" : "Ver mapa"
    ) { withAnimation(NookMotion.spring) { showMap.toggle() } }
  }
  private var listView: some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(targetPerson == nil ? "CERCA DE TI" : "PUNTO MEDIO")
              .font(.caption2.bold()).tracking(1.4).foregroundStyle(NookColors.mocha)
            Text(selectedArea)
              .font(.system(size: 19, weight: .bold, design: .rounded))
              .foregroundStyle(NookColors.espresso)
          }
          Spacer()
          if vm.loading {
            NookInlineLoading(text: "Buscando cafeterías…")
          }
        }.padding(.horizontal, 6).padding(.bottom, 2)
        if let error = vm.error, !vm.loading {
          NookErrorView(message: error) {
            Task { await vm.retry(app.repository) }
          }.frame(maxWidth: .infinity).padding(.top, 28)
        } else if vm.shops.isEmpty && !vm.loading {
          NookEmptyState(
            icon: location.denied ? "location.slash" : "cup.and.saucer",
            title: location.denied ? "Necesitamos tu zona" : "No encontramos cafeterías",
            text: location.denied
              ? "Activa la ubicación para descubrir cafeterías cercanas."
              : "No hay resultados disponibles en esta zona por ahora.")
            .frame(maxWidth: .infinity).padding(.top, 36)
        }
        ForEach(Array(vm.shops.enumerated()), id: \.element.id) { index, shop in
          VStack(spacing: 0) {
            Button {
              withAnimation(NookMotion.spring) { selected = selected?.id == shop.id ? nil : shop }
            } label: {
              NookCoffeeShopCard(shop: shop, namespace: namespace, recommended: index == 0)
            }.buttonStyle(.plain)
            if selected?.id == shop.id {
              InlineCoffeeShopDetail(shop: shop, recommended: index == 0) {
                if index == 0 { celebrateAndContinue(with: shop) }
                else { proposalShop = shop }
              } close: {
                withAnimation(NookMotion.spring) { selected = nil }
              }.transition(.move(edge: .top).combined(with: .opacity))
            }
          }.opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 35).animation(
            NookMotion.spring.delay(Double(index) * 0.06), value: appeared)
        }
      }.padding(.horizontal, 12).padding(.top, 4)
    }.scrollIndicators(.hidden)
  }
  private func celebrateAndContinue(with shop: CoffeeShop) {
    Haptics.success()
    withAnimation(NookMotion.spring) { celebratedShop = shop }
    Task {
      try? await Task.sleep(for: .milliseconds(1_250))
      withAnimation(.easeOut(duration: 0.22)) { celebratedShop = nil }
      try? await Task.sleep(for: .milliseconds(220))
      proposalShop = shop
    }
  }
  private var selectedArea: String {
    vm.meetingArea ?? app.me?.city ?? "Tu zona"
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
        Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
      }
      .foregroundStyle(selected ? NookColors.inverseText : NookColors.espresso.opacity(0.64))
      .frame(maxWidth: .infinity).frame(height: 42)
      .background(selected ? NookColors.espresso : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }.buttonStyle(.plain)
  }
  private var areaPicker: some View {
    NavigationStack {
      ZStack {
        NookBackground()
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
        vm.error = "Todavía no tenemos una ubicación válida."
        searching = false
        return
      }
      if area == nil, let matchID = app.selectedCoffeeMatch {
        await vm.useMidpoint(matchID: matchID, currentLocation: current, repo: app.repository)
      } else {
        await vm.useCurrentLocation(current, repo: app.repository)
      }
      withAnimation(.easeInOut(duration: 0.55)) { searching = false }
      withAnimation(NookMotion.fast) { app.tabBarHidden = false }
      withAnimation(NookMotion.spring) { appeared = true }
    }
  }
  private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) async {
    do {
      let (point, name) = try await locationSearch.resolve(suggestion)
      await selectResolvedArea(point, name: name)
    } catch { vm.error = "No hemos podido localizar ese lugar." }
  }
  private func selectArea(query: String) async {
    do {
      let (point, name) = try await locationSearch.resolve(query: query)
      await selectResolvedArea(point, name: name)
    } catch { vm.error = "No hemos podido localizar ese lugar." }
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
      shops: vm.shops, areaName: selectedArea, searchPoint: vm.searchPoint,
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
      .overlay(NookColors.mocha.opacity(0.035).allowsHitTesting(false))
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 26).stroke(NookColors.espresso.opacity(0.09), lineWidth: 0.8))

      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Button(action: changeArea) {
            HStack(spacing: 10) {
            Image(systemName: "location.fill").font(.system(size: 12, weight: .bold))
              .foregroundStyle(NookColors.mocha)
            VStack(alignment: .leading, spacing: 1) {
              Text("BUSCANDO EN").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1)
                .foregroundStyle(NookColors.warmGray)
              Text(areaName).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
            }
            Spacer()
            Text("Cambiar").font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundStyle(NookColors.mocha)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
          }
          .foregroundStyle(NookColors.espresso).padding(.horizontal, 14).frame(height: 52)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(NookColors.espresso.opacity(0.08)))
          }.buttonStyle(.plain).accessibilityLabel("Cambiar zona, ahora \(areaName)")
          Button {
            Task {
              await useCurrentLocation()
              positionCameraIfNeeded(force: true)
            }
          } label: {
            Image(systemName: "location.circle.fill").font(.system(size: 20, weight: .semibold))
              .frame(width: 52, height: 52).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
          }.buttonStyle(.plain).foregroundStyle(NookColors.espresso)
            .disabled(currentLocation == nil).accessibilityLabel("Mi ubicación")
        }

        Spacer()

        if loading {
          HStack(spacing: 10) {
            NookCoffeeLogo(size: 28, animated: true)
            VStack(alignment: .leading, spacing: 1) {
              Text("NOOK ESTÁ BUSCANDO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1)
              Text("Nuevos cafés por aquí…").font(.system(size: 13, weight: .bold, design: .rounded))
            }
          }
          .foregroundStyle(NookColors.espresso).padding(.horizontal, 14).padding(.vertical, 10)
          .background(.ultraThinMaterial, in: Capsule())
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
              .font(.system(size: 13, weight: .bold, design: .rounded))
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
                Text(shop.name).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
                Text("\(shop.vibeLabel)  ·  \(String(format: "%.1f", shop.distanceKm)) km")
                  .font(.caption.weight(.medium)).foregroundStyle(NookColors.warmGray).lineLimit(1)
              }
              Spacer()
              Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                .frame(width: 38, height: 38).background(NookColors.espresso, in: Circle())
                .foregroundStyle(NookColors.inverseText)
            }.padding(9).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 21).stroke(NookColors.espresso.opacity(0.08)))
          }.buttonStyle(.plain).foregroundStyle(NookColors.espresso)
        } else {
          Label("Toca una taza", systemImage: "cup.and.saucer.fill")
            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(NookColors.espresso.opacity(0.72))
            .padding(.horizontal, 15).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
        }

        VStack(spacing: 7) {
          HStack {
            Text("RADIO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
            Spacer()
            Text("\(Int(radiusKm)) km").font(.system(size: 13, weight: .bold, design: .rounded))
              .foregroundStyle(NookColors.mocha)
          }
          Slider(value: $radiusKm, in: 1...30, step: 1) { editing in
            if !editing { radiusChanged(radiusKm) }
          }.tint(NookColors.mocha)
        }.foregroundStyle(NookColors.espresso).padding(.horizontal, 14).padding(.vertical, 10)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 17).stroke(NookColors.espresso.opacity(0.08)))
      }
      .padding(.horizontal, 14)
      .padding(.top, 14)
      .padding(.bottom, 14)
    }
    .padding(.horizontal, 12)
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
          .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(NookColors.warmGray)
          .multilineTextAlignment(.center).lineSpacing(3)
      }
      Button(action: openSettings) {
        Label("Abrir Ajustes", systemImage: "gearshape.fill")
          .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(NookColors.inverseText)
          .frame(maxWidth: .infinity).frame(height: 54).background(NookColors.espresso, in: Capsule())
      }.buttonStyle(.plain)
      Spacer()
    }.padding(.horizontal, 28).foregroundStyle(NookColors.espresso)
  }
}

private struct NookChoiceCelebration: View {
  let shopName: String
  @State private var appeared = false
  var body: some View {
    ZStack {
      NookColors.cream.opacity(0.96).ignoresSafeArea()
      VStack(spacing: 18) {
        ZStack {
          ForEach(0..<8) { index in
            CoffeeBean().frame(width: 10, height: 16)
              .rotationEffect(.degrees(Double(index * 45)))
              .offset(y: appeared ? -70 : -42)
              .rotationEffect(.degrees(Double(index * 45)))
              .opacity(appeared ? 0.28 : 0)
              .animation(.easeOut(duration: 0.75).delay(Double(index) * 0.025), value: appeared)
          }
          Circle().fill(NookColors.espresso).frame(width: 76, height: 76)
          Image(systemName: "cup.and.saucer.fill").font(.system(size: 27, weight: .medium))
            .foregroundStyle(NookColors.inverseText)
        }.scaleEffect(appeared ? 1 : 0.72)
        VStack(spacing: 7) {
          Text("¡Buena elección!").font(NookTypography.display(38)).tracking(-0.4)
          Label("ELECCIÓN NOOK", systemImage: "sparkles")
            .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.3)
            .foregroundStyle(NookColors.mocha)
          Text(shopName).font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(NookColors.espresso.opacity(0.58))
        }
      }.foregroundStyle(NookColors.espresso).multilineTextAlignment(.center)
    }.onAppear { withAnimation(NookMotion.spring) { appeared = true } }
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
            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4)
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
        .font(.system(size: 15, weight: .medium, design: .rounded))
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
        }.font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(NookColors.espresso.opacity(0.62)).padding(.vertical, 14)
      }.buttonStyle(.plain)

      Button(action: choose) {
        HStack(spacing: 13) {
          Image(systemName: "cup.and.saucer.fill").font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38).background(NookColors.inverseText.opacity(0.08), in: Circle())
          VStack(alignment: .leading, spacing: 1) {
            Text("Elegir").font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Continuar con el día y la hora").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.62)
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
    }.font(.system(size: 10, weight: .semibold, design: .rounded))
      .padding(.horizontal, 10).frame(height: 32)
      .background(NookColors.espresso.opacity(0.055), in: Capsule())
  }
  private var shortHours: String { shop.openingHours?.components(separatedBy: " · ").first ?? "Horario pendiente" }

  private var distanceText: String {
    shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km"
  }
  private func openMaps() {
    let query = shop.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shop.address
    if let url = URL(string: "http://maps.apple.com/?q=\(query)") { openURL(url) }
  }
}

private struct SmartCoffeeSearch: View {
  let person: DiscoverProfile?
  let ownName: String?
  let ownCity: String?
  let ownPhoto: String?
  let meetingArea: String?
  let title: String
  @State private var active = false
  @State private var focus = 0
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

        LinearGradient(
          colors: [NookColors.warmBlack.opacity(0.74), .clear, NookColors.warmBlack.opacity(0.82)],
          startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        RadialGradient(
          colors: [NookColors.warmBlack.opacity(0.84), NookColors.warmBlack.opacity(0.26), .clear],
          center: .center, startRadius: 20, endRadius: 235).ignoresSafeArea()

        VStack(spacing: 0) {
          Spacer()
          VStack(spacing: 9) {
            NookAILogo()
            Text(title)
              .font(NookTypography.display(41)).tracking(-0.7).multilineTextAlignment(.center)
              .foregroundStyle(.white)
            Text(meetingArea ?? midpointLabel)
              .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.72))
            NookInlineLoading(
              text: "Comparando cafeterías",
              foreground: .white.opacity(0.7),
              accent: NookColors.mocha
            ).padding(.top, 5)
          }
          Spacer()
          Text("Buscando el lugar que mejor os encaje")
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.56))
            .padding(.bottom, max(74, proxy.safeAreaInsets.bottom + 58))
        }.padding(.horizontal, 28)
      }.frame(width: proxy.size.width, height: proxy.size.height)
    }.onAppear {
      NookSoundManager.shared.play(.searching)
      withAnimation(NookMotion.spring) { active = true }
      Task {
        for index in 1..<19 {
          try? await Task.sleep(for: .milliseconds(140))
          withAnimation(NookMotion.spring) { focus = index % 18 }
        }
      }
    }
  }

  private func galleryTile(index: Int, width: CGFloat, height: CGFloat) -> some View {
    NookRemoteImage(url: URL(string: photos[index % photos.count])) {
      NookColors.offWhite.overlay(
        Image(systemName: "cup.and.saucer").foregroundStyle(NookColors.mocha))
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
    .saturation(index == focus ? 1 : 0.72)
    .opacity(active ? (index == focus ? 1 : 0.62) : 0)
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
        Text("NOOK").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.4)
        Text("IA").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(2.4)
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
  @State private var selectedPhoto = 0
  private var gallery: [String] {
    var values = shop.photoUrls ?? []
    if let cover = shop.photoUrl, !values.contains(cover) { values.insert(cover, at: 0) }
    return values.isEmpty ? [""] : values
  }
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        TabView(selection: $selectedPhoto) {
          ForEach(Array(gallery.enumerated()), id: \.offset) { index, photo in
            ShopImage(url: photo.isEmpty ? nil : photo, seed: "\(shop.name)-\(index)")
              .frame(width: proxy.size.width, height: 250)
              .tag(index)
          }
        }
          .tabViewStyle(.page(indexDisplayMode: .never))
          .matchedGeometryEffect(id: "image-\(shop.id)", in: namespace)
          .visualEffect { content, geometry in content.offset(y: geometry.frame(in: .scrollView).minY * -0.035) }
        LinearGradient(colors: [.clear, NookColors.warmBlack.opacity(0.08), NookColors.warmBlack.opacity(0.88)], startPoint: .top, endPoint: .bottom)
          .allowsHitTesting(false)
        if gallery.count > 1 {
          VStack {
            HStack(spacing: 5) {
              Spacer()
              ForEach(gallery.indices, id: \.self) { index in
                Capsule()
                  .fill(.white.opacity(index == selectedPhoto ? 0.95 : 0.38))
                  .frame(width: index == selectedPhoto ? 14 : 5, height: 5)
              }
            }
            Spacer()
          }
          .padding(16)
          .animation(.snappy(duration: 0.22), value: selectedPhoto)
          .allowsHitTesting(false)
        }
        if recommended {
          VStack {
            HStack {
              Label("ELECCIÓN NOOK", systemImage: "sparkles").font(.caption.bold()).tracking(0.8)
                .padding(.horizontal, 11).padding(.vertical, 7).background(NookColors.espresso.opacity(0.9), in: Capsule())
              Spacer()
            }
            Spacer()
          }.foregroundStyle(NookColors.inverseText).padding(14)
        }
        VStack(alignment: .leading, spacing: 7) {
          if recommended { Text("Pinta genial para los dos").font(.caption.bold()).tracking(0.4).foregroundStyle(.white.opacity(0.78)) }
          Text(shop.name).font(NookTypography.display(29)).tracking(-0.2).lineLimit(1)
          HStack(spacing: 12) {
            if let rating = shop.rating { Label(rating.formatted(), systemImage: "star.fill") }
            Label(shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km", systemImage: "location")
            Text(shop.vibeLabel)
          }.font(.system(size: 13, weight: .semibold, design: .rounded))
        }.foregroundStyle(.white).padding(18)
      }
    }.frame(height: 242).clipShape(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
    ).overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(recommended ? NookColors.mocha : .clear, lineWidth: recommended ? 2 : 0)
    }.shadow(color: recommended ? NookColors.mocha.opacity(0.24) : NookColors.warmBlack.opacity(0.1), radius: recommended ? 18 : 12, y: 5)
  }
}

struct ShopImage: View {
  let url: String?
  let seed: String
  var body: some View {
    NookRemoteImage(url: URL(string: url ?? "")) {
      ZStack {
          LinearGradient(
            colors: [NookColors.mocha, NookColors.espresso], startPoint: .topLeading,
            endPoint: .bottomTrailing)
          Image(systemName: "cup.and.saucer.fill").font(.system(size: 80)).foregroundStyle(
            NookColors.latte.opacity(0.65))
      }
    }.clipped()
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
  @State private var visible = false
  @State private var mapPosition: MapCameraPosition = .automatic
  @State private var coordinate: CLLocationCoordinate2D?
  var body: some View {
    ZStack {
      NookBackground()
      ScrollView {
        VStack(spacing: 0) {
          ZStack(alignment: .topLeading) {
            ShopImage(url: shop.photoUrl, seed: shop.name).frame(height: 340)
            LinearGradient(colors: [NookColors.warmBlack.opacity(0.38), .clear], startPoint: .top, endPoint: .center)
            Button { dismiss() } label: {
              Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).padding(16)
          }.clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 14).padding(.top, 8)
          VStack(alignment: .center, spacing: 22) {
            VStack(spacing: 11) {
              Text(shop.name).font(NookTypography.display(40)).tracking(-0.5)
                .multilineTextAlignment(.center)
              HStack(spacing: 15) {
                if let rating = shop.rating { Label(rating.formatted(), systemImage: "star.fill") }
                Label(distanceLabel, systemImage: "location")
                Text(shop.vibeLabel)
              }.font(.caption.weight(.semibold)).foregroundStyle(NookColors.espresso.opacity(0.6))
            }
            Button { propose = true } label: {
              Text("Elegir").font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(NookColors.inverseText).frame(width: 148, height: 46)
                .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.plain)
            Rectangle().fill(NookColors.espresso.opacity(0.09)).frame(height: 1)
            Text(editorialDescription).font(.system(size: 17, weight: .regular, design: .rounded))
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
          .opacity(visible ? 1 : 0).offset(y: visible ? 0 : 20)
      }
    }.onAppear {
      withAnimation(NookMotion.spring.delay(0.2)) { visible = true }
      Task { await locateShop() }
    }.sheet(isPresented: $propose) { ProposalSheet(shop: shop, matches: matches) }
  }
  private var editorialDescription: String {
    shop.description ?? shop.nookEditorialFallback
  }
  private var distanceLabel: String { shop.distanceKm < 1 ? "\(Int(shop.distanceKm * 1000)) m" : "\(shop.distanceKm.formatted()) km" }
  private func openMaps() {
    let query = shop.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shop.address
    if let url = URL(string: "http://maps.apple.com/?q=\(query)") { openURL(url) }
  }
  private func info(_ icon: String, _ value: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(NookColors.mocha).frame(width: 22)
      Text(value).font(.system(size: 16, weight: .medium, design: .rounded))
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
  @State private var step = 0
  @State private var selectedMatch: UUID?
  @State private var payment = PaymentPreference.iInvite
  @State private var date = Date().addingTimeInterval(86_400)
  @State private var confirmed = false
  @State private var sending = false
  @State private var submitError: String?
  var body: some View {
    NavigationStack {
      ZStack {
        NookBackground()
        if confirmed {
          proposalSent
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        } else {
          VStack(spacing: 20) {
          HStack {
            ForEach(0..<totalSteps, id: \.self) { i in
              Capsule().fill(i <= step ? NookColors.espresso : NookColors.oat.opacity(0.5)).frame(
                height: 4)
            }
          }
          Group {
            if needsPersonChoice && step == 0 {
              choiceStep("¿CON QUIÉN?", "Elige la persona para este café") {
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
                    }.foregroundStyle(NookColors.espresso).padding(12)
                      .background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 20))
                  }.buttonStyle(.plain)
                }
              }
            } else if flowStep == 0 {
              choiceStep("¿QUÉ DÍA?", shop.openingHours == nil ? "Horario todavía no disponible" : "Solo mostramos días compatibles") {
                DatePicker("Fecha", selection: $date, in: Date()..., displayedComponents: .date)
                  .datePickerStyle(.graphical).tint(NookColors.espresso).padding(12)
                  .background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: NookRadius.large))
                  .disabled(shop.openingHours == nil).opacity(shop.openingHours == nil ? 0.4 : 1)
                if let hours = shop.openingHours { Label(hours, systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(NookColors.mocha) }
              }
            } else if flowStep == 1 {
              choiceStep("¿A QUÉ HORA?", "Dentro del horario del café") {
                DatePicker("Hora", selection: $date, displayedComponents: .hourAndMinute)
                  .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                  .disabled(shop.openingHours == nil).opacity(shop.openingHours == nil ? 0.4 : 1)
              }
            } else if flowStep == 2 {
              choiceStep("¿QUIÉN INVITA? ☕", "Sin compromisos raros") {
                ForEach(PaymentPreference.allCases) { value in
                  choice(value.title, selected: payment == value) { payment = value }
                }
              }
            } else {
              choiceStep("Se lo enviamos a \(selectedPersonName)", "Revisa el plan antes de enviarlo") {
                NookCard {
                  VStack(alignment: .leading, spacing: 14) {
                    if isNookChoice {
                      Label("ELECCIÓN NOOK", systemImage: "sparkles")
                        .font(.caption.bold()).tracking(1).foregroundStyle(NookColors.mocha)
                    }
                    Label(selectedPersonName, systemImage: "person.crop.circle")
                    Label(shop.name, systemImage: "mappin.and.ellipse")
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(payment.title, systemImage: "cup.and.saucer.fill")
                  }.font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                }
              }
            }
            Spacer()
            NookButton(title: isReview ? "ENVIAR" : "CONTINUAR", icon: isReview ? "paperplane" : "arrow.right") {
              if !isReview {
                withAnimation(NookMotion.spring) { step += 1 }
              } else if let match = selectedMatch {
                Task {
                  sending = true
                  do {
                    _ = try await app.repository.propose(
                      match: match, shop: shop.id, date: date, payment: payment, nookChoice: isNookChoice)
                    sending = true
                    Haptics.success()
                    NookSoundManager.shared.play(.proposal)
                    try? await Task.sleep(for: .milliseconds(850))
                    withAnimation(NookMotion.spring) { confirmed = true; sending = false }
                  } catch { sending = false; submitError = error.localizedDescription }
                }
              }
            }.disabled((needsPersonChoice && step == 0 && selectedMatch == nil) || ((flowStep == 0 || flowStep == 1) && shop.openingHours == nil))
          }.padding(24)
          }.navigationTitle("Nuevo café").navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarLeading) {
                Button { if step == 0 { dismiss() } else { withAnimation(NookMotion.spring) { step -= 1 } } } label: {
                  Image(systemName: step == 0 ? "xmark" : "chevron.left")
                }.accessibilityLabel(step == 0 ? "Cerrar" : "Volver")
              }
            }
        }
        if sending { CoffeeBeanTransition().allowsHitTesting(false).transition(.opacity) }
      }
    }.alert("No hemos podido enviarlo", isPresented: Binding(
      get: { submitError != nil }, set: { if !$0 { submitError = nil } }
    )) { Button("Entendido") { submitError = nil } } message: { Text(submitError ?? "") }
    .onAppear { selectedMatch = app.selectedCoffeeMatch }
  }
  private var needsPersonChoice: Bool { app.selectedCoffeeMatch == nil }
  private var flowStep: Int { step - (needsPersonChoice ? 1 : 0) }
  private var totalSteps: Int { needsPersonChoice ? 5 : 4 }
  private var isReview: Bool { step == totalSteps - 1 }
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
          Text(shop.name).font(.system(size: 23, weight: .bold, design: .rounded)).lineLimit(1)
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
        app.selectedTab = 2
        dismiss()
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
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(NookTypography.display(40))
      Text(subtitle).font(.title3).foregroundStyle(NookColors.warmGray)
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).transition(
      .move(edge: .trailing).combined(with: .opacity))
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
          Text("DESTINATARIO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4)
            .foregroundStyle(.white.opacity(0.76))
          Spacer()
          Label("ENVIADA", systemImage: "checkmark")
            .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8)
            .foregroundStyle(NookColors.inverseText).padding(.horizontal, 9).frame(height: 27)
            .background(NookColors.mocha, in: Capsule())
        }
        Spacer()
        Text(person.name).font(NookTypography.display(32)).tracking(-0.45).lineLimit(1)
        Label("Ahora espera su respuesta", systemImage: "cup.and.saucer")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
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
    .padding(.horizontal, 13).frame(minHeight: 58)
    .background(NookColors.amber.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(NookColors.amber.opacity(0.16), lineWidth: 0.8))
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
      Text("PREPARANDO CAFÉ").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2)
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
