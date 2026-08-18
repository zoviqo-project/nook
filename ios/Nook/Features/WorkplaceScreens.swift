import EventKit
import MapKit
import SwiftUI

@MainActor final class ChatsVM: ObservableObject {
  enum State: Equatable { case idle, loading, loaded, empty, error(String) }
  @Published var chats: [Conversation] = []
  @Published var dates: [CoffeeDate] = []
  @Published var matches: [Match] = []
  @Published private(set) var state: State = .idle
  @Published private(set) var updating: Set<UUID> = []
  var loading: Bool { state == .loading }
  var error: String? { if case .error(let message) = state { message } else { nil } }
  func seed(_ persisted: [CoffeeDate]) {
    guard !persisted.isEmpty else { return }
    dates = merged(server: dates, recent: persisted)
    state = .loaded
  }
  func seed(_ snapshot: MyCafesSnapshot) {
    chats = snapshot.chats
    dates = snapshot.dates
    matches = snapshot.matches
    state = dates.isEmpty && matches.isEmpty && chats.isEmpty ? .empty : .loaded
  }
  func load(_ repo: any NookRepository, showLoader: Bool = true) async {
    let startedAt = Date()
    if showLoader && state == .idle { state = .loading }
    do {
      // Coffee dates are the source of truth for this screen. A temporary failure
      // loading chats or matches must never hide a proposal already persisted.
      async let d = repo.dates()
      async let c = try? repo.conversations()
      async let m = try? repo.matches()
      dates = unique(try await d)
      if let loadedChats = await c { chats = loadedChats }
      if let loadedMatches = await m { matches = loadedMatches }
      state = dates.isEmpty && matches.isEmpty && chats.isEmpty ? .empty : .loaded
    } catch {
      state = dates.isEmpty
        ? .error("No hemos podido cargar tus cafés. Comprueba la conexión y vuelve a intentarlo.")
        : .loaded
    }
    #if DEBUG
      print("[PERF] MyCafes parallel API + decode: \(Int(Date().timeIntervalSince(startedAt) * 1_000))ms")
    #endif
  }
  private func merged(server: [CoffeeDate], recent: [CoffeeDate]) -> [CoffeeDate] {
    var result = server
    for date in recent where !result.contains(where: { $0.id == date.id }) { result.insert(date, at: 0) }
    return result
  }
  private func unique(_ values: [CoffeeDate]) -> [CoffeeDate] {
    var seen = Set<UUID>()
    return values.filter { seen.insert($0.id).inserted }
  }
  func transition(
    _ id: UUID, to status: CoffeeDateStatus, repo: any NookRepository
  ) async -> CoffeeDate? {
    guard updating.insert(id).inserted else { return nil }
    defer { updating.remove(id) }
    do {
      let updated = try await repo.updateDate(id, status: status)
      if let index = dates.firstIndex(where: { $0.id == id }) { dates[index] = updated }
      else { dates.insert(updated, at: 0) }
      state = .loaded
      return updated
    } catch {
      state = .error(error.localizedDescription)
      return nil
    }
  }
}

struct ChatsView: View {
  @EnvironmentObject var app: AppSession
  @StateObject private var vm = ChatsVM()
  @State private var section = 2
  var body: some View {
    NookScreenContainer(eyebrow: "TODO EMPIEZA AQUÍ", title: "Mis cafés") {
      Group {
        if vm.loading {
          NookSkeletonScreen(layout: .coffeeDates(rows: 3))
        } else if let error = vm.error {
          NookErrorView(message: error) { Task { await vm.load(app.repository) } }
        } else {
          CoffeeDatesList(
            dates: vm.dates, matches: vm.matches, conversations: vm.chats,
            updating: vm.updating
          ) { id, status in
            Task {
              if let updated = await vm.transition(id, to: status, repo: app.repository) {
                app.upsertCachedCoffeeDate(updated)
                app.coffeeProposalPersisted(updated)
              }
            }
          }
        }
      }
    }.task {
      if let cache = app.myCafesCache { vm.seed(cache) }
      vm.seed(app.recentlyPersistedCoffeeDates)
      await vm.load(app.repository, showLoader: app.myCafesCache == nil)
      app.cacheMyCafes(chats: vm.chats, dates: vm.dates, matches: vm.matches)
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else { break }
        await vm.load(app.repository, showLoader: false)
        app.cacheMyCafes(chats: vm.chats, dates: vm.dates, matches: vm.matches)
      }
    }.refreshable {
      await vm.load(app.repository, showLoader: false)
      app.cacheMyCafes(chats: vm.chats, dates: vm.dates, matches: vm.matches)
    }
      .onChange(of: app.coffeeDataRevision) { _, _ in
        vm.seed(app.recentlyPersistedCoffeeDates)
        Task {
          await vm.load(app.repository, showLoader: false)
          app.cacheMyCafes(chats: vm.chats, dates: vm.dates, matches: vm.matches)
        }
      }
      .onChange(of: vm.dates.count) { _, _ in prefetchImages() }
  }
  private func prefetchImages() {
    NookImagePrefetch.schedule(vm.dates.compactMap { $0.coffeeShop.photoUrl })
    NookImagePrefetch.schedule(vm.matches.prefix(8).flatMap { $0.person.photos.map(\.url) })
  }
  private var connections: some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        if vm.matches.isEmpty { NookEmptyState(icon: "person.2", title: "Aún no hay conexiones", text: "Cuando alguien también quiera compartir un café contigo, aparecerá aquí.") }
        ForEach(vm.matches) { match in
          NavigationLink {
            if let conversation = vm.chats.first(where: { $0.matchId == match.id }) { ChatDetail(conversation: conversation) }
            else { PersonProfileView(person: match.person) }
          } label: {
            HStack(spacing: 14) {
              ProfileImage(url: match.person.photos.first?.url, name: match.person.name).frame(width: 72, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18))
              VStack(alignment: .leading, spacing: 7) {
                Text("\(match.person.name), \(match.person.age)").font(.title3.bold()).foregroundStyle(NookColors.espresso)
                Text(match.person.bio).font(.subheadline).foregroundStyle(NookColors.espresso.opacity(0.7)).lineLimit(2)
                connectionStatus(match)
              }
              Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(NookColors.espresso.opacity(0.42))
            }.padding(12).minimalListCard()
          }
        }
      }.padding(.horizontal, 16)
    }
  }
  @ViewBuilder private func connectionStatus(_ match: Match) -> some View {
    if let date = vm.dates.first(where: { $0.matchId == match.id && [.accepted, .pending, .counterProposed].contains($0.status) }) {
      if date.status == .accepted {
        NookStatusBadge(icon: "checkmark.circle.fill", text: "Aceptado", color: NookColors.success)
      } else if date.status == .counterProposed {
        NookStatusBadge(icon: "bubble.left.and.bubble.right.fill", text: "\(match.person.name) quiere chatear contigo antes", color: NookColors.mocha)
      } else {
        NookStatusBadge(icon: "hourglass", text: "Esperando respuesta", color: NookColors.amber)
      }
    } else { NookStatusBadge(icon: "mappin", text: "Proponer lugar") }
  }
  private func segment(_ title: String, _ index: Int) -> some View {
    Button {
      Haptics.selection()
      withAnimation(NookMotion.spring) { section = index }
    } label: {
      VStack(spacing: 7) {
        Text(title).font(.subheadline.weight(section == index ? .bold : .medium))
        Capsule().frame(height: 2).opacity(section == index ? 1 : 0)
      }.foregroundStyle(section == index ? NookColors.espresso : NookColors.espresso.opacity(0.52))
        .frame(maxWidth: .infinity).frame(height: 36)
    }
  }
  private var conversations: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        if vm.chats.isEmpty {
          NookEmptyState(
            icon: "bubble.left.and.bubble.right", title: "Aún no hay chats",
            text: "Cuando tengáis café, la conversación empieza aquí.")
        }
        ForEach(vm.chats) { chat in
          NavigationLink {
            ChatDetail(conversation: chat)
          } label: {
            HStack(spacing: 13) {
              ProfileImage(url: chat.person.photos.first?.url, name: chat.person.name).frame(
                width: 66, height: 66
              ).clipShape(Circle())
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(chat.person.name).font(.title3.bold()).foregroundStyle(NookColors.espresso)
                  Spacer()
                  Text("AHORA").font(.caption2.bold()).foregroundStyle(NookColors.espresso.opacity(0.5))
                }
                Text(chat.lastMessage.isEmpty ? "Decid hola ☕" : chat.lastMessage).foregroundStyle(
                  NookColors.espresso.opacity(0.7)
                ).lineLimit(1)
                Label("Café pendiente", systemImage: "cup.and.saucer")
                  .font(.caption.weight(.semibold)).foregroundStyle(NookColors.espresso.opacity(0.78))
              }
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(NookColors.espresso.opacity(0.4))
            }.padding(13).minimalListCard()
          }
        }
      }.padding(.horizontal, 16)
    }
  }
}

struct ChatDetail: View {
  @EnvironmentObject var app: AppSession
  let conversation: Conversation
  @State private var messages: [ChatMessage] = []
  @State private var dates: [CoffeeDate] = []
  @State private var text = ""
  @State private var sending = false
  @State private var pendingMessageID: UUID?
  @State private var proposing = false
  @State private var error: String?
  @State private var initialLoading = true
  @State private var updatingDates: Set<UUID> = []
  @FocusState private var focused: Bool
  var body: some View {
    ZStack {
      NookBackground()
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 10) {
              if initialLoading {
                NookSkeletonScreen(layout: .list(rows: 3)).frame(height: 360)
              } else if messages.isEmpty {
                Text("Rompe el hielo con un café ☕").font(.callout.weight(.semibold))
                  .foregroundStyle(NookColors.warmGray).padding(.top, 30)
              }
              ForEach(messages) { message in
                Group {
                  if message.senderId == nil || message.type != "TEXT" {
                    NookSystemMessageBubble(title: message.body, detail: systemDetail(for: message.type))
                  } else {
                    NookChatBubble(text: message.body, outgoing: message.senderId == app.me?.id)
                  }
                }.id(message.id).transition(.move(edge: .bottom).combined(with: .opacity))
              }
              ForEach(dates.filter { $0.matchId == conversation.matchId }) { date in
                NookCoffeeProposalBubble(date: date, canAccept: date.receiverId == app.me?.id,
                  updating: updatingDates.contains(date.id)) {
                  Task {
                    guard updatingDates.insert(date.id).inserted else { return }
                    defer { updatingDates.remove(date.id) }
                    do {
                      _ = try await app.repository.updateDate(date.id, status: .accepted)
                      dates = try await app.repository.dates()
                      app.coffeeProposalPersisted()
                      NookSoundManager.shared.play(.confirmed)
                    } catch { self.error = error.localizedDescription }
                  }
                } change: { proposing = true }
              }
              Color.clear.frame(height: 1).id("chat-bottom")
            }.padding(16)
          }.scrollDismissesKeyboard(.interactively).defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in withAnimation(NookMotion.spring) { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
            .onChange(of: focused) { _, value in if value { withAnimation(NookMotion.spring) { proxy.scrollTo("chat-bottom", anchor: .bottom) } } }
        }
      }.safeAreaInset(edge: .bottom, spacing: 0) { composer }.toolbar {
        ToolbarItem(placement: .principal) {
          HStack(spacing: 9) {
            ProfileImage(url: conversation.person.photos.first?.url, name: conversation.person.name).frame(width: 34, height: 34).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
              Text(conversation.person.name).font(.headline)
              Text(chatStatus.0).font(.caption2.weight(.bold)).foregroundStyle(chatStatus.1)
            }
          }
        }
      }.navigationBarTitleDisplayMode(.inline).task {
        await refreshConversation()
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(10))
          guard !Task.isCancelled else { break }
          await refreshConversation(silent: true)
        }
      }.sheet(isPresented: $proposing) { ChatCoffeePicker(conversation: conversation) }
        .alert("No hemos podido continuar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
          Button("Entendido") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear { withAnimation(NookMotion.spring) { app.tabBarHidden = true } }
        .onDisappear { withAnimation(NookMotion.spring) { app.tabBarHidden = false } }
    }
  }
  @MainActor private func refreshConversation(silent: Bool = false) async {
    do {
      async let messageCall = app.repository.messages(conversation.id)
      async let dateCall = app.repository.dates()
      let refreshedMessages = try await messageCall
      let refreshedDates = try await dateCall
      if refreshedMessages.map(\.id) != messages.map(\.id) {
        withAnimation(NookMotion.spring) { messages = refreshedMessages }
      }
      dates = refreshedDates
      initialLoading = false
      if !silent { error = nil }
    } catch {
      initialLoading = false
      if !silent { self.error = error.localizedDescription }
    }
  }
  private var chatStatus: (String, Color) {
    let related = dates.filter { $0.matchId == conversation.matchId }
    if related.contains(where: { $0.status == .accepted }) { return ("✓ Café confirmado", NookColors.success) }
    if related.contains(where: { $0.status == .pending || $0.status == .counterProposed }) { return ("☕ Esperando confirmación", NookColors.amber) }
    return ("Conexión Nook", .secondary)
  }
  private var composer: some View {
    HStack(spacing: 9) {
      Button {
        focused = false
        proposing = true
        Haptics.selection()
      } label: {
        Image(systemName: "cup.and.saucer.fill").font(.system(size: 18, weight: .semibold))
          .foregroundStyle(NookColors.espresso).frame(width: 44, height: 44)
          .background(NookColors.oat.opacity(0.34), in: Circle())
      }.accessibilityLabel("Proponer café")
      TextField("Escribe un mensaje…", text: $text, axis: .vertical).font(.body.weight(.medium))
        .focused($focused).padding(.horizontal, 17).frame(minHeight: 48).background(
          NookColors.offWhite, in: Capsule())
      Button {
        send()
      } label: {
        Group {
          if sending { ProgressView().tint(NookColors.inverseText) }
          else { Image(systemName: "arrow.up").font(.headline.bold()) }
        }.foregroundStyle(NookColors.inverseText)
          .frame(width: 48, height: 48).background(NookColors.espresso, in: Circle())
      }.scaleEffect(text.isEmpty ? 0.9 : 1).animation(NookMotion.spring, value: text.isEmpty)
      .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
    }.padding(.horizontal, 12).padding(.vertical, 8)
      .background(NookColors.cream)
      .overlay(alignment: .top) { Divider().opacity(0.18) }
      .animation(NookMotion.fast, value: focused)
  }
  private func send() {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !sending else { return }
    sending = true
    let clientMessageID = pendingMessageID ?? UUID()
    pendingMessageID = clientMessageID
    Haptics.selection()
    Task {
      defer { sending = false }
      do {
        let message = try await app.repository.send(
          value, to: conversation.id, clientMessageID: clientMessageID)
        text = ""
        pendingMessageID = nil
        if !messages.contains(where: { $0.id == message.id }) {
          withAnimation(NookMotion.spring) { messages.append(message) }
        }
      } catch { self.error = error.localizedDescription }
    }
  }
  private func systemDetail(for type: String) -> String? {
    switch type {
    case "COFFEE_ACCEPTED": "El café ya aparece en Próximos"
    case "COFFEE_COMPLETED": "Este encuentro está en tu historial"
    case "COFFEE_CANCELLED": "La propuesta ha sido cancelada"
    default: nil
    }
  }
}

struct NookCoffeeProposalBubble: View {
  let date: CoffeeDate
  let canAccept: Bool
  let updating: Bool
  let accept: () -> Void
  let change: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("PROPUESTA DE CAFÉ", systemImage: "cup.and.saucer.fill").font(.caption.bold()).tracking(1)
      Text(date.coffeeShop.name).font(.title3.bold())
      Text(formatted).font(.headline)
      Text(date.coffeeShop.vibeLabel).font(.subheadline.weight(.semibold))
      Text(date.paymentPreference.title).font(.subheadline).foregroundStyle(NookColors.warmGray)
      if date.status == .pending {
        HStack {
          if canAccept {
            Button(updating ? "Aceptando…" : "Aceptar", action: accept)
              .buttonStyle(.borderedProminent).tint(NookColors.espresso).disabled(updating)
          }
          else { Text("Esperando respuesta").font(.caption.bold()).foregroundStyle(NookColors.warmGray) }
          Button("Cambiar", action: change).buttonStyle(.bordered).tint(NookColors.espresso)
            .disabled(updating)
        }
      } else { Text(date.status == .accepted ? "ACEPTADO" : date.status.rawValue).font(.caption.bold()).foregroundStyle(NookColors.warmGray) }
    }.padding(18).foregroundStyle(NookColors.espresso).background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(NookColors.oat.opacity(0.45))).padding(.vertical, 4)
  }
  private var formatted: String { date.formattedProposedAt() }
}

struct ChatCoffeePicker: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let conversation: Conversation
  @StateObject private var location = LocationManager()
  @State private var shops: [CoffeeShop] = []
  @State private var selected: CoffeeShop?
  @State private var locationMessage: String?
  @State private var loading = true
  var body: some View {
    NavigationStack {
      ZStack {
        NookBackground()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            Text("Elige vuestro café").font(NookTypography.title).padding(.bottom, 8)
            if loading {
              NookSkeletonScreen(layout: .list(rows: 4))
            } else if shops.isEmpty && locationMessage == nil {
              NookEmptyState(icon: "cup.and.saucer", title: "No encontramos cafeterías",
                text: "Prueba de nuevo desde otra zona.")
            }
            ForEach(shops) { shop in
              Button { selected = shop } label: {
                HStack(spacing: 14) {
                  ShopImage(url: shop.photoUrl, seed: shop.name).frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 20))
                  VStack(alignment: .leading, spacing: 5) { Text(shop.name).font(.headline); Text("\(shop.neighborhood ?? shop.address) · \(shop.vibeLabel)").font(.subheadline).foregroundStyle(NookColors.warmGray).lineLimit(2) }
                  Spacer(); Image(systemName: "chevron.right")
                }.foregroundStyle(NookColors.espresso).padding(.vertical, 4)
              }.buttonStyle(.plain)
            }
            if let locationMessage { Text(locationMessage).font(.subheadline).foregroundStyle(NookColors.warmGray) }
          }.padding(22)
        }
      }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        .task {
          defer { loading = false }
          location.request()
          for _ in 0..<80 where location.location == nil && !location.denied {
            try? await Task.sleep(for: .milliseconds(100))
          }
          guard let point = location.location?.coordinate else {
            locationMessage = "Necesitamos una ubicación válida para buscar cafeterías reales."
            return
          }
          do { shops = try await app.repository.shops(latitude: point.latitude, longitude: point.longitude, radiusKm: 2) }
          catch { locationMessage = "No hemos podido obtener cafeterías reales." }
        }
        .sheet(item: $selected) { shop in
          ProposalSheet(shop: shop, matches: [Match(id: conversation.matchId, person: conversation.person, matchedAt: conversation.updatedAt, conversationId: conversation.id)])
        }
        .onDisappear { location.stop() }
    }
  }
}

struct CoffeeDatesList: View {
  @EnvironmentObject var app: AppSession
  private enum Filter: String, CaseIterable, Identifiable {
    case pending = "Pendientes", upcoming = "Próximos", all = "Todos", finished = "Finalizadas"
    var id: String { rawValue }
  }
  let dates: [CoffeeDate]
  let matches: [Match]
  let conversations: [Conversation]
  let updating: Set<UUID>
  let action: (UUID, CoffeeDateStatus) -> Void
  @State private var filter: Filter = .all
  private var upcoming: [CoffeeDate] { dates.filter { $0.status == .accepted } }
  private var pending: [CoffeeDate] { dates.filter { $0.status == .pending || $0.status == .counterProposed } }
  private var past: [CoffeeDate] {
    dates.filter { [.completed, .cancelled, .declined, .expired].contains($0.status) }
  }
  var body: some View {
    VStack(spacing: 10) {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(Filter.allCases) { value in
            Button {
              Haptics.selection()
              withAnimation(NookMotion.spring) { filter = value }
            } label: {
              Text(value.rawValue).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(filter == value ? NookColors.inverseText : NookColors.espresso.opacity(0.72))
                .padding(.horizontal, 15).frame(height: 38)
                .background(filter == value ? NookColors.mocha : NookColors.offWhite, in: Capsule())
                .overlay(Capsule().stroke(NookColors.mocha.opacity(filter == value ? 0 : 0.22)))
            }.buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
      }.scrollIndicators(.hidden)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if filteredDates.isEmpty && (filter != .all || unplannedMatches.isEmpty) {
            NookEmptyState(icon: emptyIcon, title: emptyTitle, text: emptyText)
              .frame(maxWidth: .infinity)
          } else if filter == .all {
            section("CITAS CONFIRMADAS", upcoming)
            section("ESPERANDO RESPUESTA", pending)
            section("FINALIZADAS", past)
            matchSection
          } else {
            section(filteredSectionTitle, filteredDates)
          }
        }
        .containerRelativeFrame(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
      }
      .contentMargins(.horizontal, 16, for: .scrollContent)
      .scrollIndicators(.hidden)
    }
  }
  @ViewBuilder private func section(_ title: String, _ values: [CoffeeDate]) -> some View {
    if !values.isEmpty {
      Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.6)
        .foregroundStyle(NookColors.mocha).padding(.top, 12).padding(.leading, 4)
      ForEach(values) { date in
        ticket(date)
      }
    }
  }
  @ViewBuilder private var matchSection: some View {
    if !unplannedMatches.isEmpty {
      Text("MATCHES SIN PROPUESTA").font(.system(size: 11, weight: .bold, design: .rounded))
        .tracking(1.6).foregroundStyle(NookColors.mocha).padding(.top, 12).padding(.leading, 4)
      ForEach(unplannedMatches) { match in
        Button {
          app.selectedCoffeeMatch = match.id
          app.placesReloadID = UUID()
          app.selectedTab = 1
        } label: {
          HStack(spacing: 12) {
            ProfileImage(url: match.person.photos.first?.url, name: match.person.name)
              .frame(width: 52, height: 52).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
              Text(match.person.name).font(.headline).lineLimit(1).truncationMode(.tail)
              Text("Elegid una cafetería y proponed un día")
                .font(.caption).foregroundStyle(NookColors.warmGray).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").font(.caption.bold())
          }
          .foregroundStyle(NookColors.espresso)
          .padding(12)
          .frame(maxWidth: .infinity)
          .frame(height: 78)
          .minimalListCard()
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
      }
    }
  }
  private func ticket(_ date: CoffeeDate) -> some View {
    CoffeeTicket(
      date: date, person: matches.first(where: { $0.id == date.matchId })?.person,
      conversation: conversations.first(where: { $0.matchId == date.matchId }),
      isUpdating: updating.contains(date.id), action: action)
      .frame(maxWidth: .infinity).frame(height: 242)
  }
  private var unplannedMatches: [Match] {
    matches.filter { match in !dates.contains(where: { $0.matchId == match.id && ![.declined, .cancelled, .expired, .completed].contains($0.status) }) }
  }
  private var filteredDates: [CoffeeDate] {
    switch filter {
    case .all: upcoming + pending + past
    case .pending: pending
    case .upcoming: upcoming
    case .finished: past
    }
  }
  private var filteredSectionTitle: String {
    switch filter {
    case .all: "TODOS TUS CAFÉS"
    case .pending: "CITAS PENDIENTES"
    case .upcoming: "CITAS CONFIRMADAS"
    case .finished: "CAFÉS FINALIZADOS"
    }
  }
  private var emptyIcon: String { filter == .upcoming ? "calendar" : filter == .finished ? "clock.arrow.circlepath" : "cup.and.saucer" }
  private var emptyTitle: String { filter == .all ? "Tu primera cita espera" : "Nada por aquí todavía" }
  private var emptyText: String { filter == .all ? "Elige una cafetería después de hacer match." : "Tus cafés aparecerán aquí cuando cambien de estado." }
}

struct CoffeeTicket: View {
  @EnvironmentObject var app: AppSession
  let date: CoffeeDate
  let person: DiscoverProfile?
  let conversation: Conversation?
  let isUpdating: Bool
  let action: (UUID, CoffeeDateStatus) -> Void
  @State private var safe = false
  @State private var calendarMessage: String?
  @State private var calendarBusy = false
  @State private var breathing = false
  @State private var celebrating = false
  @State private var showingDetail = false
  var body: some View {
    ZStack {
      ZStack(alignment: .bottomLeading) {
      ShopImage(url: date.coffeeShop.photoUrl, seed: date.coffeeShop.name)
        .frame(maxWidth: .infinity).frame(height: cardHeight).clipped()
      LinearGradient(
        colors: [.clear, NookColors.warmBlack.opacity(0.40), NookColors.warmBlack],
        startPoint: .top, endPoint: .bottom)
        VStack(spacing: 0) {
          HStack(alignment: .top, spacing: 6) {
            if date.nookChoice == true {
              Label("ELECCIÓN NOOK", systemImage: "sparkles")
                .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.9)
                .foregroundStyle(NookColors.inverseText).padding(.horizontal, 10).frame(height: 28)
                .background(NookColors.mocha, in: Capsule())
                .lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
            }
            Spacer(minLength: 2)
            statusLabel.layoutPriority(1)
            Button { showingDetail = true } label: {
              Image(systemName: "ellipsis").font(.caption.bold())
                .frame(width: 28, height: 28).background(.black.opacity(0.28), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Gestionar cita")
          }
          Spacer(minLength: 8)
          VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 11) {
            if let person {
              NavigationLink { PersonProfileView(person: person) } label: {
                ProfileImage(url: person.photos.first?.url, name: person.name)
                  .frame(width: 45, height: 45).clipShape(Circle())
                  .overlay { Circle().stroke(NookColors.mocha, lineWidth: 2) }
              }.buttonStyle(.plain).accessibilityLabel("Ver perfil de \(person.name)")
            }
              Text(person?.name ?? "Tu cita").font(NookTypography.display(30)).tracking(-0.25)
                .lineLimit(1).truncationMode(.tail).minimumScaleFactor(0.72)
              Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
              Image(systemName: "mappin.and.ellipse").foregroundStyle(NookColors.mocha).frame(width: 17)
              Text(date.coffeeShop.name).font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1).truncationMode(.tail)
            }
            HStack(spacing: 7) {
              Image(systemName: "calendar").foregroundStyle(NookColors.mocha).frame(width: 17)
              Text(date.formattedProposedAt(dateStyle: .full)).lineLimit(1).minimumScaleFactor(0.85)
            }.font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundStyle(NookColors.espresso.opacity(0.78))
            controls
          }
        }.padding(14)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .shadow(color: .black.opacity(0.42), radius: 5, y: 2)
      }
      if date.status == .accepted {
        ConfirmedCoffeeBurst(active: celebrating).allowsHitTesting(false)
        CoffeeCheersAnimation(active: celebrating).allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity).frame(height: cardHeight).foregroundStyle(.white)
    .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    .dynamicTypeSize(.xSmall ... .xLarge)
    .overlay {
      RoundedRectangle(cornerRadius: 25, style: .continuous)
        .stroke(.white.opacity(date.status == .accepted ? 0.78 : 0.2), lineWidth: date.status == .accepted ? 1.6 : 0.8)
    }
    .overlay(alignment: .topTrailing) {
      if date.status == .accepted {
        Circle().fill(.white.opacity(breathing ? 0.28 : 0.08)).frame(width: 92, height: 92)
          .blur(radius: 24).offset(x: 22, y: -26).allowsHitTesting(false)
      }
    }
    .overlay {
      if isUpdating {
        ProgressView().tint(.white).padding(12)
          .background(.black.opacity(0.42), in: Circle())
      }
    }
    .shadow(
      color: date.status == .accepted ? NookColors.espresso.opacity(breathing ? 0.22 : 0.12) : NookColors.warmBlack.opacity(0.13),
      radius: date.status == .accepted ? 12 : 10, y: 5)
    .onTapGesture { showingDetail = true }
    .onAppear {
      guard date.status == .accepted else { return }
      Haptics.success()
      NookSoundManager.shared.play(.confirmed)
      withAnimation(.spring(response: 0.58, dampingFraction: 0.58)) { celebrating = true }
      Task {
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { breathing = true }
      }
    }
      .alert("Calendario", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
        Button("OK") { calendarMessage = nil }
      } message: { Text(calendarMessage ?? "") }
      .sheet(isPresented: $safe) {
        SafeCoffeeView {
          action(date.id, .accepted)
          safe = false
        }
      }
      .sheet(isPresented: $showingDetail) {
        CoffeeDateDetail(
          date: date, person: person, conversation: conversation,
          isUpdating: isUpdating, action: action)
      }
  }
  private var cardHeight: CGFloat { 242 }
  private var statusLabel: some View {
    HStack(spacing: 5) {
      Image(systemName: statusIcon)
      Text(statusText)
    }.font(.system(size: 10, weight: .bold, design: .rounded)).lineLimit(1)
      .minimumScaleFactor(0.62).allowsTightening(true)
      .padding(.horizontal, 10).frame(height: 28)
      .background(statusColor, in: Capsule())
      .foregroundStyle(date.status == .accepted ? NookColors.inverseText : NookColors.espresso)
  }
  private var statusIcon: String {
    switch date.status { case .accepted: "checkmark"; case .pending: "hourglass"; case .counterProposed: "bubble.left"; case .completed: "cup.and.saucer.fill"; default: "xmark" }
  }
  private var statusText: String {
    switch date.status {
    case .accepted: "¡CITA CONFIRMADA!"
    case .pending: date.receiverId == app.me?.id ? "TE HAN PROPUESTO UN CAFÉ" : "PROPUESTA ENVIADA"
    case .counterProposed: date.receiverId == app.me?.id ? "NUEVA PROPUESTA" : "ESPERANDO RESPUESTA"
    case .completed: "COMPLETADO"
    default: statusCopy.uppercased()
    }
  }
  private var statusColor: Color {
    switch date.status {
    case .accepted: NookColors.mocha
    case .pending, .counterProposed: NookColors.offWhite.opacity(0.96)
    case .completed: NookColors.success
    default: NookColors.offWhite.opacity(0.94)
    }
  }
  @ViewBuilder private var controls: some View {
    if date.status == .pending {
      if date.receiverId == app.me?.id {
        if isUpdating {
          HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text("Actualizando…").font(.system(size: 12, weight: .semibold, design: .rounded))
          }.frame(height: 34)
        } else {
          HStack {
            Button("Aceptar") { safe = true }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(NookColors.espresso)
            Button("Rechazar") { action(date.id, .declined) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.78))
          }
        }
      } else {
        Text("Esperando respuesta").font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.8)
      }
    } else if date.status == .accepted {
      HStack(spacing: 10) {
        Button {
          guard !calendarBusy else { return }
          calendarBusy = true
          Task { await addToCalendar(); calendarBusy = false }
        } label: {
          Group {
            if calendarBusy { ProgressView().tint(NookColors.inverseText) }
            else { Label("Añadir al calendario", systemImage: "calendar.badge.plus") }
          }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity).frame(height: 42)
            .foregroundStyle(NookColors.inverseText).background(NookColors.espresso, in: Capsule())
        }
        Button { guard !isUpdating else { return }; action(date.id, .completed) } label: {
          Image(systemName: "checkmark").frame(width: 42, height: 42)
            .background(.ultraThinMaterial, in: Circle())
        }.accessibilityLabel("Completar encuentro")
      }.buttonStyle(.plain).disabled(isUpdating || calendarBusy)
    } else if date.status == .counterProposed {
      Text("\(person?.name ?? "La otra persona") quiere chatear contigo antes")
        .font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
        .truncationMode(.tail).opacity(0.86)
    } else {
      Text(statusCopy).font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.8)
    }
  }
  private var statusCopy: String {
    switch date.status {
    case .completed: "Café completado"
    case .cancelled: "Cancelado"
    case .declined: "No confirmado"
    case .expired: "Propuesta caducada"
    case .counterProposed: "Nueva propuesta"
    case .accepted: "Confirmado"
    case .pending: "Esperando confirmación"
    }
  }
  private func countdown(_ raw: String) -> String {
    guard let value = ISO8601DateFormatter.nook.date(from: raw) else { return "" }
    let hours = max(0, Int(value.timeIntervalSinceNow / 3600))
    return hours > 24 ? "Faltan \(hours / 24) días" : "Faltan \(hours) h"
  }
  @MainActor private func addToCalendar() async {
    guard let start = ISO8601DateFormatter.nook.date(from: date.proposedAt) else {
      calendarMessage = "No hemos podido interpretar la fecha del café."
      return
    }
    let store = EKEventStore()
    do {
      let granted = try await store.requestFullAccessToEvents()
      guard granted else { calendarMessage = "Activa el acceso al calendario en Ajustes para guardar el café."; return }
      let event = EKEvent(eventStore: store)
      event.title = "Café con \(person?.name ?? "Nook") ☕"
      event.startDate = start
      event.endDate = start.addingTimeInterval(60 * 60)
      event.location = date.coffeeShop.address
      event.notes = "Café organizado con Nook en \(date.coffeeShop.name)."
      event.calendar = store.defaultCalendarForNewEvents
      try store.save(event, span: .thisEvent)
      Haptics.success()
      calendarMessage = "Café añadido. Si usas Google Calendar en el iPhone, se sincronizará con esa cuenta."
    } catch {
      calendarMessage = "No hemos podido añadir el café al calendario."
    }
  }
}

private struct CoffeeDateDetail: View {
  @EnvironmentObject private var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let date: CoffeeDate
  let person: DiscoverProfile?
  let conversation: Conversation?
  let isUpdating: Bool
  let action: (UUID, CoffeeDateStatus) -> Void
  @State private var confirmingCancellation = false

  var body: some View {
    NavigationStack {
      ZStack {
        NookBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            ShopImage(url: date.coffeeShop.photoUrl, seed: date.coffeeShop.name)
              .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 26))

            HStack(spacing: 12) {
              if let person {
                ProfileImage(url: person.photos.first?.url, name: person.name)
                  .frame(width: 54, height: 54).clipShape(Circle())
              }
              VStack(alignment: .leading, spacing: 4) {
                Text(person?.name ?? "Tu cita").font(.title2.bold())
                NookStatusBadge(icon: statusIcon, text: statusText, color: statusColor)
              }
            }

            VStack(alignment: .leading, spacing: 13) {
              detailRow("Cafetería", date.coffeeShop.name, "cup.and.saucer.fill")
              detailRow("Cuándo", date.formattedProposedAt(dateStyle: .full), "calendar")
              detailRow("Dirección", date.coffeeShop.address, "mappin.and.ellipse")
              detailRow("Estado", statusText, statusIcon)
            }.padding(18).background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 22))

            if let latitude = date.coffeeShop.latitude, let longitude = date.coffeeShop.longitude {
              let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
              Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900
              ))) {
                Marker(date.coffeeShop.name, coordinate: coordinate).tint(NookColors.mocha)
              }
              .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 22))
              .allowsHitTesting(false)
            }

            if let conversation {
              NavigationLink { ChatDetail(conversation: conversation) } label: {
                Label("Abrir conversación", systemImage: "bubble.left.and.bubble.right.fill")
                  .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                  .foregroundStyle(NookColors.espresso)
                  .background(NookColors.offWhite, in: Capsule())
              }.buttonStyle(.plain)
            }

            if date.status == .pending && date.receiverId == app.me?.id {
              HStack(spacing: 10) {
                actionButton("Aceptar", icon: "checkmark", status: .accepted, primary: true)
                actionButton("Rechazar", icon: "xmark", status: .declined, primary: false)
              }
            }

            if canCancel {
              Button(role: .destructive) { confirmingCancellation = true } label: {
                Label("Ya no quiero quedar", systemImage: "calendar.badge.minus")
                  .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
              }.buttonStyle(.bordered).tint(.red).disabled(isUpdating)
            }
          }.padding(20).padding(.bottom, 12)
        }.scrollIndicators(.hidden)
      }
      .navigationTitle("Detalle del café")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
      .alert("¿Cancelar esta cita?", isPresented: $confirmingCancellation) {
        Button("No", role: .cancel) {}
        Button("Sí, cancelar", role: .destructive) {
          action(date.id, cancellationStatus)
          dismiss()
        }
      } message: {
        Text("La otra persona también verá la cita como cancelada.")
      }
    }
  }

  private func detailRow(_ title: String, _ value: String, _ icon: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon).foregroundStyle(NookColors.mocha).frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title.uppercased()).font(.caption2.bold()).tracking(0.8).foregroundStyle(NookColors.warmGray)
        Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(NookColors.espresso)
      }
    }
  }

  private func actionButton(
    _ title: String, icon: String, status: CoffeeDateStatus, primary: Bool
  ) -> some View {
    Button {
      action(date.id, status)
      dismiss()
    } label: {
      Label(title, systemImage: icon).font(.headline)
        .frame(maxWidth: .infinity).frame(height: 50)
        .foregroundStyle(primary ? NookColors.inverseText : NookColors.espresso)
        .background(primary ? NookColors.espresso : NookColors.offWhite, in: Capsule())
    }.buttonStyle(.plain).disabled(isUpdating)
  }

  private var canCancel: Bool {
    [.pending, .counterProposed, .accepted].contains(date.status)
  }
  private var cancellationStatus: CoffeeDateStatus {
    date.status == .pending && date.receiverId == app.me?.id ? .declined : .cancelled
  }
  private var statusText: String {
    switch date.status {
    case .pending: date.receiverId == app.me?.id ? "Te han propuesto un café" : "Propuesta enviada"
    case .counterProposed: date.receiverId == app.me?.id ? "Nueva propuesta" : "Esperando respuesta"
    case .accepted: "Confirmado"
    case .cancelled: "Cancelado"
    case .declined: "Rechazado"
    case .completed: "Completado"
    case .expired: "Caducado"
    }
  }
  private var statusIcon: String {
    switch date.status {
    case .accepted: "checkmark.circle.fill"
    case .pending, .counterProposed: "hourglass"
    case .completed: "cup.and.saucer.fill"
    default: "xmark.circle.fill"
    }
  }
  private var statusColor: Color {
    switch date.status {
    case .accepted: NookColors.success
    case .pending, .counterProposed: NookColors.amber
    case .completed: NookColors.mocha
    default: .red
    }
  }
}

private struct ConfirmedCoffeeBurst: View {
  let active: Bool
  var body: some View {
    ZStack {
      ForEach(0..<3, id: \.self) { index in
        Circle().stroke(NookColors.mocha.opacity(0.42), lineWidth: 2)
          .frame(width: CGFloat(110 + index * 62), height: CGFloat(110 + index * 62))
          .scaleEffect(active ? 1.55 : 0.12).opacity(active ? 0 : 0.9)
          .animation(.easeOut(duration: 0.85).delay(Double(index) * 0.08), value: active)
      }
      ForEach(0..<10, id: \.self) { index in
        Capsule().fill(index.isMultiple(of: 2) ? NookColors.mocha : NookColors.latte)
          .frame(width: 8, height: 15).rotationEffect(.degrees(Double(index) * 47))
          .offset(x: active ? cos(Double(index) * .pi / 5) * 165 : 0,
                  y: active ? sin(Double(index) * .pi / 5) * 150 : 0)
          .opacity(active ? 0 : 1)
          .animation(.easeOut(duration: 0.82).delay(Double(index) * 0.025), value: active)
      }
    }
  }
}

private struct CoffeeCheersAnimation: View {
  let active: Bool
  var body: some View {
    ZStack {
      Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: 24, weight: .medium))
        .rotationEffect(.degrees(active ? 13 : -8))
        .offset(x: active ? -17 : -58, y: active ? 0 : 16)
      Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: 24, weight: .medium))
        .scaleEffect(x: -1, y: 1)
        .rotationEffect(.degrees(active ? 13 : -8))
        .offset(x: active ? 17 : 58, y: active ? 0 : 16)
      Image(systemName: "sparkle")
        .font(.system(size: 13, weight: .bold)).foregroundStyle(NookColors.mocha)
        .scaleEffect(active ? 1.15 : 0.05).opacity(active ? 1 : 0)
        .offset(y: -17)
    }
    .foregroundStyle(.white)
    .frame(width: 118, height: 64)
    .background(.black.opacity(0.2), in: Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.7))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .offset(y: -24)
    .animation(.spring(response: 0.62, dampingFraction: 0.52).delay(0.12), value: active)
    .accessibilityHidden(true)
  }
}

private extension View {
  func minimalListCard() -> some View {
    background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(NookColors.espresso.opacity(0.12), lineWidth: 0.75)
      }
      .shadow(color: NookColors.warmBlack.opacity(0.08), radius: 10, y: 4)
  }
}

struct NookEmptyState: View {
  let icon: String
  let title: String
  let text: String
  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: icon).font(.system(size: 42)).foregroundStyle(NookColors.latte)
      Text(title).font(.title2.bold())
      Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 60)
  }
}
