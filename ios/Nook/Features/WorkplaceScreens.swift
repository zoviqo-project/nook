import EventKit
import MapKit
import SwiftUI

@MainActor final class ChatsVM: ObservableObject {
  enum State: Equatable { case idle, loading, loaded, empty, error(String) }
  @Published var chats: [Conversation] = []
  @Published var dates: [CoffeeDate] = []
  @Published var matches: [Match] = []
  @Published var items: [MyCafeItem] = []
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
    apply(snapshot.items)
  }
  func load(_ repo: any NookRepository, showLoader: Bool = true) async {
    let startedAt = Date()
    if showLoader && state == .idle { state = .loading }
    do {
      let cafes = try await repo.myCafes()
      let matches = (try? await repo.matches()) ?? []
      apply(hydrated(cafes, with: matches))
    } catch {
      state = dates.isEmpty
        ? .error("No hemos podido cargar tus cafés. Comprueba la conexión y vuelve a intentarlo.")
        : .loaded
    }
    #if DEBUG
      print("[PERF] MyCafes parallel API + decode: \(Int(Date().timeIntervalSince(startedAt) * 1_000))ms")
    #endif
  }
  private func apply(_ values: [MyCafeItem]) {
    var seen = Set<UUID>()
    items = values.filter { seen.insert($0.matchId).inserted }
    dates = items.compactMap(\.proposal)
    matches = items.map {
      Match(id: $0.matchId, person: $0.person, matchedAt: $0.matchedAt, conversationId: $0.conversationId)
    }
    chats = items.map {
      Conversation(id: $0.conversationId, matchId: $0.matchId, person: $0.person, lastMessage: "", updatedAt: $0.matchedAt)
    }
    state = items.isEmpty ? .empty : .loaded
  }
  private func hydrated(_ values: [MyCafeItem], with matches: [Match]) -> [MyCafeItem] {
    let matchesByID = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
    return values.map { item in
      guard let match = matchesByID[item.matchId],
            match.person.photos.count > item.person.photos.count else { return item }
      return MyCafeItem(
        matchId: item.matchId, person: match.person, matchedAt: item.matchedAt,
        conversationId: item.conversationId, proposal: item.proposal,
        availableActions: item.availableActions)
    }
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
      if let index = items.firstIndex(where: { $0.matchId == updated.matchId }) {
        items[index].proposal = updated
        switch updated.status {
        case .accepted: items[index].availableActions = ["DETAIL", "CHAT", "CANCEL", "COMPLETE"]
        case .cancelled, .declined, .expired: items[index].availableActions = ["PROPOSE", "CHAT"]
        case .completed: items[index].availableActions = ["DETAIL", "CHAT"]
        case .pending, .counterProposed: break
        }
      }
      state = .loaded
      return updated
    } catch {
      state = .error(NookErrorCopy.message(
        for: error, fallback: "No hemos podido actualizar este café. Inténtalo de nuevo."))
      return nil
    }
  }
  func deleteMatch(_ id: UUID, repo: any NookRepository) async -> Bool {
    guard updating.insert(id).inserted else { return false }
    defer { updating.remove(id) }
    do {
      try await repo.deleteMatch(id)
      apply(items.filter { $0.matchId != id })
      return true
    } catch {
      state = .error("No hemos podido deshacer el match. Inténtalo de nuevo.")
      return false
    }
  }
}

struct ChatsView: View {
  private enum QuickFilter { case matches, pending, confirmed, closed }
  @EnvironmentObject var app: AppSession
  @StateObject private var vm = ChatsVM()
  var close: (() -> Void)? = nil
  @State private var section = 2
  @State private var quickFilter: QuickFilter?
  var body: some View {
    VStack(spacing: 0) {
      myCafesHeader
      Group {
        if vm.loading && vm.items.isEmpty {
          MyCafesSkeletonView()
        } else if let error = vm.error {
          NookErrorView(message: error) { Task { await vm.load(app.repository) } }
        } else {
          MyCafesUnifiedList(
            items: filteredItems, updating: vm.updating, filteredEmptyText: filteredEmptyText
          ) { id, status in
            Task {
              if let updated = await vm.transition(id, to: status, repo: app.repository) {
                app.upsertCachedCoffeeDate(updated)
                app.coffeeProposalPersisted(updated)
              }
            }
          } removeMatch: { id in
            Task {
              if await vm.deleteMatch(id, repo: app.repository) { app.matchesChanged() }
              app.cacheMyCafes(vm.items)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.white)
    .background { Color.white.ignoresSafeArea() }
    .preferredColorScheme(.light)
    .toolbar(.hidden, for: .navigationBar)
    .task {
      if let cache = app.myCafesCache { vm.seed(cache) }
      vm.seed(app.recentlyPersistedCoffeeDates)
      await vm.load(app.repository, showLoader: app.myCafesCache == nil && vm.items.isEmpty)
      app.cacheMyCafes(vm.items)
    }.refreshable {
      await vm.load(app.repository, showLoader: false)
      app.cacheMyCafes(vm.items)
    }
      .onChange(of: app.coffeeDataRevision) { _, _ in
        vm.seed(app.recentlyPersistedCoffeeDates)
        Task {
          await vm.load(app.repository, showLoader: false)
          app.cacheMyCafes(vm.items)
        }
      }
      .onChange(of: vm.dates.count) { _, _ in prefetchImages() }
  }
  private var myCafesHeader: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .bottomLeading) {
        myCafesHeroImage

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.08), location: 0),
            .init(color: .clear, location: 0.34),
            .init(color: NookColors.espresso.opacity(0.76), location: 1),
          ],
          startPoint: .top, endPoint: .bottom)

        VStack(alignment: .leading, spacing: 5) {
          Label("TU AGENDA DE CAFÉ", systemImage: "cup.and.saucer.fill")
            .font(.system(size: 10, weight: .bold))
            .tracking(1.35)
            .foregroundStyle(.white.opacity(0.78))
          Text("Mis cafés")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .tracking(-1)
            .foregroundStyle(.white)
          Text(headerSummary)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)

        if close == nil {
          Button {
            Haptics.selection()
            app.tabBarHidden = true
            app.selectedCoffeeMatch = nil
            app.selectedTab = 0
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 40, height: 40)
              .background(.ultraThinMaterial, in: Circle())
              .environment(\.colorScheme, .dark)
              .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 0.8))
              .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
          }
          .buttonStyle(.plain)
          .padding(.leading, 16)
          .padding(.top, 12)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .accessibilityLabel("Volver a descubrir perfiles")
        }

        if close != nil {
          sheetGrabber
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
        }
      }
      .frame(height: 218)
      .background {
        NookColors.espresso
          .ignoresSafeArea(edges: .top)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          headerFilterButton(icon: "square.grid.2x2", label: "Todos", count: vm.items.count, filter: nil)
          headerFilterButton(icon: "heart.fill", label: "Matches", count: matchCount, filter: .matches)
          headerFilterButton(icon: "hourglass", label: "Pendientes", count: pendingCount, filter: .pending)
          headerFilterButton(icon: "checkmark.circle.fill", label: "Próximos", count: confirmedCount, filter: .confirmed)
          headerFilterButton(icon: "clock.arrow.circlepath", label: "Historial", count: closedCount, filter: .closed)
        }
        .padding(.horizontal, 20)
      }
      .scrollIndicators(.hidden)
      .contentMargins(.trailing, 20, for: .scrollContent)
      .padding(.vertical, 12)
      .background(Color.white)
    }
    .frame(maxWidth: .infinity)
    .background(Color.white)
    .transaction { transaction in transaction.animation = nil }
    .zIndex(10)
  }
  private var sheetGrabber: some View {
    Capsule()
      .fill(Color.white.opacity(0.96))
      .frame(width: 38, height: 5)
      .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
      .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
      .accessibilityHidden(true)
  }
  private var myCafesHeroImage: some View {
    GeometryReader { proxy in
      // The source is portrait-oriented. Positioning its overflow explicitly keeps
      // both cups in the horizontal header instead of centring on the empty wall.
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
  private func headerFilterButton(
    icon: String, label: String, count: Int, filter: QuickFilter?
  ) -> some View {
    let active = quickFilter == filter
    return Button {
      if let filter { toggleFilter(filter) }
      else { Haptics.selection(); quickFilter = nil }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 10, weight: .medium))
        Text(label).font(.system(size: 12, weight: .medium))
        Text("\(count)")
          .font(.system(size: 9, weight: .semibold))
          .padding(.horizontal, 5)
          .frame(minHeight: 18)
          .background(active ? Color.white.opacity(0.18) : NookColors.espresso.opacity(0.05), in: Capsule())
      }
      .foregroundStyle(active ? Color.white : NookColors.espresso.opacity(0.68))
      .padding(.horizontal, 11)
      .frame(height: 34)
      .background(active ? NookColors.espresso : NookColors.offWhite, in: Capsule())
      .overlay(Capsule().stroke(NookColors.espresso.opacity(active ? 0 : 0.055), lineWidth: 0.7))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Filtrar por \(label)")
  }
  private var headerSummary: String {
    if vm.items.isEmpty { return "Tus conexiones y próximas citas" }
    let pending = vm.items.filter {
      $0.proposal?.status == .pending || $0.proposal?.status == .counterProposed
    }.count
    return pending == 0
      ? "\(vm.items.count) conexiones"
      : "\(vm.items.count) conexiones · \(pending) pendientes"
  }
  private var matchCount: Int { vm.items.filter { $0.proposal == nil }.count }
  private var pendingCount: Int {
    vm.items.filter { $0.proposal?.status == .pending || $0.proposal?.status == .counterProposed }.count
  }
  private var confirmedCount: Int { vm.items.filter { $0.proposal?.status == .accepted }.count }
  private var closedCount: Int {
    vm.items.filter {
      guard let status = $0.proposal?.status else { return false }
      return [.completed, .cancelled, .declined, .expired].contains(status)
    }.count
  }
  private var filteredItems: [MyCafeItem] {
    #if DEBUG
      if ProcessInfo.processInfo.environment["NOOK_PREVIEW_EMPTY_CAFES"] == "1" { return [] }
    #endif
    switch quickFilter {
    case .matches: return vm.items.filter { $0.proposal == nil }
    case .pending: return vm.items.filter {
      guard let status = $0.proposal?.status else { return false }
      return status == .pending || status == .counterProposed
    }
    case .confirmed: return vm.items.filter { $0.proposal?.status == .accepted }
    case .closed: return vm.items.filter {
      guard let status = $0.proposal?.status else { return false }
      return [.completed, .cancelled, .declined, .expired].contains(status)
    }
    case nil: return vm.items
    }
  }
  private var hasPendingMatch: Bool { vm.items.contains { $0.proposal == nil } }
  private func toggleFilter(_ filter: QuickFilter) {
    Haptics.selection()
    quickFilter = quickFilter == filter ? nil : filter
  }
  private var filteredEmptyText: String? {
    guard let quickFilter, !vm.items.isEmpty else { return nil }
    switch quickFilter {
    case .matches: return "No tienes matches pendientes de proponer un café."
    case .pending: return "No tienes propuestas esperando respuesta."
    case .confirmed: return "No tienes citas confirmadas."
    case .closed: return "Todavía no hay citas cerradas."
    }
  }
  private func prefetchImages() {
    NookImagePrefetch.schedule(vm.dates.compactMap { $0.coffeeShop.photoUrl })
    NookImagePrefetch.schedule(vm.matches.prefix(8).flatMap { $0.person.photos.map(\.url) })
  }
  private var connections: some View {
    ScrollView {
      LazyVStack(spacing: 11) {
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
            .containerRelativeFrame(.vertical, alignment: .center)
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

struct ConversationsView: View {
  @EnvironmentObject var app: AppSession
  @State private var conversations: [Conversation] = []
  @State private var cafeItems: [MyCafeItem] = []
  @State private var loading = true
  @State private var error: String?

  var body: some View {
    NookScreenContainer(eyebrow: "CONVERSACIONES", title: "Chats") {
      Group {
        if loading && conversations.isEmpty {
          NookSkeletonScreen(layout: .conversations(rows: 6))
        } else if let error, conversations.isEmpty {
          NookErrorView(message: error) { Task { await load() } }
        } else if conversations.isEmpty {
          NookEmptyState(
            icon: "bubble.left.and.bubble.right", title: "Aún no hay chats",
            text: "Cuando hagáis match, vuestra conversación aparecerá aquí.")
            .containerRelativeFrame(.vertical, alignment: .center)
        } else {
          VStack(spacing: 0) {
            if !selectedCafes.isEmpty { selectedCafesRail }
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(conversations) { conversation in
                  NavigationLink { ChatDetail(conversation: conversation) } label: {
                    conversationRow(conversation)
                  }
                }
            }.padding(.horizontal, NookSpacing.screen).padding(.bottom, NookSpacing.xs)
            }.refreshable { await load(showLoader: false) }
          }
        }
      }
    }
    .task {
      await load()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { break }
        await load(showLoader: false)
      }
    }
  }

  private var selectedCafes: [CoffeeShop] {
    var seen = Set<UUID>()
    return cafeItems.compactMap(\.proposal).map(\.coffeeShop).filter { seen.insert($0.id).inserted }
  }

  private var selectedCafesRail: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("VUESTROS CAFÉS")
        .font(NookTypography.sectionLabel).tracking(1.4)
        .foregroundStyle(NookColors.mocha)
      ScrollView(.horizontal) {
        LazyHStack(spacing: 15) {
          ForEach(selectedCafes) { shop in
            ShopImage(url: shop.photoUrl, seed: shop.name)
              .frame(width: 54, height: 54).clipShape(Circle())
              .overlay { AnimatedCafeRailRing(premium: isNookChoice(shop)) }
              .frame(width: 72, height: 72)
              .accessibilityLabel(shop.name)
          }
        }
        .padding(.vertical, 3)
      }.scrollIndicators(.hidden).frame(height: 78)
    }
    .padding(.horizontal, NookSpacing.screen).padding(.top, 0).padding(.bottom, 10)
  }

  private func isNookChoice(_ shop: CoffeeShop) -> Bool {
    cafeItems.contains {
      $0.proposal?.coffeeShop.id == shop.id && $0.proposal?.nookChoice == true
    }
  }

  private func conversationRow(_ conversation: Conversation) -> some View {
    HStack(spacing: 14) {
      ZStack(alignment: .bottomTrailing) {
        ProfileImage(url: conversation.person.photos.first?.url, name: conversation.person.name)
          .frame(width: 56, height: 56).clipShape(Circle())
        Circle().fill(NookColors.mocha).frame(width: 11, height: 11)
          .overlay(Circle().stroke(NookColors.cream, lineWidth: 2))
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(conversation.person.name)
            .font(NookTypography.chatName)
            .foregroundStyle(NookColors.espresso).lineLimit(1)
          Spacer(minLength: 6)
          Text(relativeDate(conversation.updatedAt))
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundStyle(NookColors.espresso.opacity(0.42))
        }
        Text(conversation.lastMessage.isEmpty ? "Da el primer paso y saluda ☕" : conversation.lastMessage)
          .font(NookTypography.chatPreview)
          .foregroundStyle(NookColors.espresso.opacity(conversation.lastMessage.isEmpty ? 0.62 : 0.7))
          .lineLimit(1)
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(NookColors.espresso.opacity(0.25))
    }
    .padding(.vertical, 9)
    .contentShape(Rectangle())
  }

  private func relativeDate(_ value: String) -> String {
    guard let date = ISO8601DateFormatter.nook.date(from: value) else { return "" }
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if Calendar.current.isDateInYesterday(date) { return "Ayer" }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }

  @MainActor private func load(showLoader: Bool = true) async {
    if showLoader && conversations.isEmpty { loading = true }
    defer { loading = false }
    do {
      async let conversationsRequest = app.repository.conversations()
      async let cafesRequest = app.repository.myCafes()
      let (loadedConversations, loadedCafes) = try await (conversationsRequest, cafesRequest)
      conversations = loadedConversations
      cafeItems = loadedCafes
      error = nil
      NookImagePrefetch.schedule(conversations.prefix(12).flatMap { $0.person.photos.map(\.url) })
      NookImagePrefetch.schedule(selectedCafes.compactMap(\.photoUrl))
    } catch {
      if conversations.isEmpty {
        self.error = "No hemos podido cargar tus conversaciones. Comprueba la conexión y reintenta."
      }
    }
  }
}

struct ChatDetail: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let conversation: Conversation
  @State private var messages: [ChatMessage] = []
  @State private var dates: [CoffeeDate] = []
  @State private var text = ""
  @State private var sending = false
  @State private var pendingMessageID: UUID?
  @State private var proposing = false
  @State private var proposalToChange: CoffeeDate?
  @State private var error: String?
  @State private var initialLoading = true
  @State private var updatingDates: Set<UUID> = []
  @FocusState private var focused: Bool
  var body: some View {
    VStack(spacing: 0) {
      chatHeader
      if let date = visibleCoffeeDates.first {
        NookChatCoffeeBanner(
          date: date, canAccept: date.receiverId == app.me?.id,
          updating: updatingDates.contains(date.id), accept: { accept(date) },
          change: { proposalToChange = date; proposing = true })
        .padding(.horizontal, NookSpacing.screen)
        .padding(.vertical, NookSpacing.xs)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            if initialLoading {
              NookSkeletonScreen(layout: .messages(rows: 6))
            } else if messages.isEmpty {
              Text("Rompe el hielo con un café ☕").font(NookTypography.secondary.weight(.semibold))
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
            Color.clear.frame(height: 1).id("chat-bottom")
          }.padding(.horizontal, 12).padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom)
        .onChange(of: messages.count) { _, _ in
          withAnimation(NookMotion.spring) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
        .onChange(of: focused) { _, value in
          if value {
            Task { @MainActor in
              await Task.yield()
              withAnimation(NookMotion.spring) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
          }
        }
      }
    }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { NookInteriorBackdrop().ignoresSafeArea() }
      .safeAreaInset(edge: .bottom, spacing: 0) { composer }
      .toolbar(.hidden, for: .navigationBar)
      .task {
        await refreshConversation()
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(10))
          guard !Task.isCancelled else { break }
          await refreshConversation(silent: true)
        }
      }.sheet(isPresented: $proposing, onDismiss: { proposalToChange = nil }) {
        ChatCoffeePicker(conversation: conversation, proposal: proposalToChange)
      }
        .alert("No hemos podido continuar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
          Button("Entendido") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
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
      NookImagePrefetch.schedule(
        refreshedDates.filter { $0.matchId == conversation.matchId }
          .compactMap { $0.coffeeShop.photoUrl })
      initialLoading = false
      if !silent { error = nil }
    } catch {
      initialLoading = false
      if !silent {
        self.error = NookErrorCopy.message(
          for: error, fallback: "No hemos podido actualizar la conversación. Inténtalo de nuevo.")
      }
    }
  }

  private var chatHeader: some View {
    HStack(spacing: 9) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 34, height: 40)
      }
      .buttonStyle(.plain)
      .foregroundStyle(NookColors.espresso)
      .accessibilityLabel("Volver")

      ProfileImage(url: conversation.person.photos.first?.url, name: conversation.person.name)
        .frame(width: 36, height: 36)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(conversation.person.name)
          .font(NookTypography.business(17, weight: .semibold))
          .foregroundStyle(NookColors.espresso)
          .lineLimit(1)
        Text(chatStatus.0)
          .font(NookTypography.business(11, weight: .semibold))
          .foregroundStyle(chatStatus.1)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(NookColors.surface.opacity(0.96))
    .overlay(alignment: .bottom) { Divider().opacity(0.45) }
  }
  private var chatStatus: (String, Color) {
    let related = dates.filter { $0.matchId == conversation.matchId }
    if related.contains(where: { $0.status == .accepted }) { return ("✓ Café confirmado", NookColors.success) }
    if related.contains(where: { $0.status == .pending || $0.status == .counterProposed }) { return ("☕ Esperando confirmación", NookColors.amber) }
    return ("Conexión Nook", .secondary)
  }
  private var visibleCoffeeDates: [CoffeeDate] {
    dates.filter {
      $0.matchId == conversation.matchId && [.pending, .counterProposed, .accepted].contains($0.status)
    }
    .sorted { $0.proposedAt > $1.proposedAt }
    .prefix(1).map { $0 }
  }
  private var composer: some View {
    HStack(spacing: 9) {
      Button {
        focused = false
        proposalToChange = nil
        proposing = true
        Haptics.selection()
      } label: {
        Image(systemName: "cup.and.saucer.fill").font(.system(size: 18, weight: .semibold))
          .foregroundStyle(NookColors.primaryCoffee).frame(width: 44, height: 44)
          .background(NookColors.oat.opacity(0.34), in: Circle())
      }.accessibilityLabel("Proponer café")
      TextField("Escribe un mensaje…", text: $text, axis: .vertical)
        .font(NookTypography.business(16)).lineLimit(1...5)
        .focused($focused).padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
        .background(NookColors.offWhite, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
      Button {
        send()
      } label: {
        Group {
          if sending { ProgressView().tint(NookColors.inverseText) }
          else { Image(systemName: "arrow.up").font(.headline.bold()) }
        }.foregroundStyle(NookColors.inverseText)
          .frame(width: 44, height: 44).background(NookColors.primaryCoffee, in: Circle())
      }.scaleEffect(text.isEmpty ? 0.9 : 1).animation(NookMotion.spring, value: text.isEmpty)
      .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
    }.padding(.horizontal, 12).padding(.vertical, 7)
      .background(NookColors.surface.opacity(0.98))
      .shadow(color: NookShadow.subtle, radius: 8, y: -2)
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
      } catch {
        self.error = NookErrorCopy.message(
          for: error, fallback: "El mensaje no se ha enviado. Toca para volver a intentarlo.")
      }
    }
  }
  private func accept(_ date: CoffeeDate) {
    Task {
      guard updatingDates.insert(date.id).inserted else { return }
      defer { updatingDates.remove(date.id) }
      do {
        _ = try await app.repository.updateDate(date.id, status: .accepted)
        dates = try await app.repository.dates()
        app.coffeeProposalPersisted()
        Haptics.success()
        NookSoundManager.shared.play(.confirmed)
      } catch {
        self.error = NookErrorCopy.message(
          for: error, fallback: "No hemos podido confirmar el café. Inténtalo de nuevo.")
      }
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

private struct AnimatedCafeRailRing: View {
  let premium: Bool
  @State private var rotating = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().stroke(
        NookColors.oat.opacity(0.22),
        lineWidth: premium ? 4 : 3)
      Circle()
        .trim(from: 0.06, to: 0.72)
        .stroke(
          AngularGradient(
            colors: [NookColors.mocha, NookColors.mocha.opacity(0.72),
                     NookColors.primaryCoffeeSoft, NookColors.mocha],
            center: .center),
          style: StrokeStyle(lineWidth: premium ? 4 : 3, lineCap: .round))
        .rotationEffect(.degrees(rotating ? 360 : 0))
        .shadow(
          color: NookColors.mocha.opacity(0.16),
          radius: 4)
    }
    .frame(width: 64, height: 64)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: premium ? 5.2 : 6.4).repeatForever(autoreverses: false)) {
        rotating = true
      }
    }
  }
}

private struct NookChatCoffeeBanner: View {
  let date: CoffeeDate
  let canAccept: Bool
  let updating: Bool
  let accept: () -> Void
  let change: () -> Void

  var body: some View {
    HStack(spacing: NookSpacing.sm) {
      ShopImage(url: date.coffeeShop.photoUrl, seed: date.coffeeShop.name)
        .frame(width: 50, height: 50)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(date.status == .accepted ? "CAFÉ CONFIRMADO" : "CAFÉ PENDIENTE")
          .font(NookTypography.caption).tracking(1.1).foregroundStyle(NookColors.primaryCoffee)
        Text(date.coffeeShop.name).font(NookTypography.headline).lineLimit(1)
        Text(date.formattedProposedAt())
          .font(NookTypography.caption).foregroundStyle(NookColors.textSecondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      if date.status == .pending || date.status == .counterProposed {
        if canAccept {
          Button(action: accept) {
            Group { if updating { ProgressView() } else { Image(systemName: "checkmark") } }
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain).foregroundStyle(NookColors.inverseText)
          .background(NookColors.primaryCoffee, in: Circle()).disabled(updating)
          .accessibilityLabel("Aceptar propuesta")
        }
        Button(action: change) {
          Image(systemName: "calendar").frame(width: 36, height: 36)
        }
        .buttonStyle(.plain).foregroundStyle(NookColors.primaryCoffee)
        .background(NookColors.primaryCoffeeSoft, in: Circle())
        .accessibilityLabel("Cambiar propuesta")
      } else {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(NookColors.success)
      }
    }
    .padding(NookSpacing.sm)
    .background(NookColors.caramelSoft.opacity(0.52), in: RoundedRectangle(cornerRadius: NookRadius.medium))
  }
}

struct NookCoffeeProposalBubble: View {
  let date: CoffeeDate
  let canAccept: Bool
  let updating: Bool
  let accept: () -> Void
  let change: () -> Void
  var body: some View {
    ZStack {
      ShopImage(url: date.coffeeShop.photoUrl, seed: date.coffeeShop.name)
        .frame(maxWidth: .infinity)
        .frame(height: 246)
      LinearGradient(
        colors: [.clear, NookColors.warmBlack.opacity(0.34), NookColors.warmBlack.opacity(0.96)],
        startPoint: .top, endPoint: .bottom)
        .frame(height: 246)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 246)
    .overlay(alignment: .topLeading) {
      Label("PROPUESTA DE CAFÉ", systemImage: "cup.and.saucer.fill")
        .font(NookTypography.business(10, weight: .bold)).tracking(1)
        .foregroundStyle(NookColors.inverseText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NookColors.mocha, in: Capsule())
        .padding(16)
    }
    .overlay(alignment: .bottomLeading) {
      VStack(alignment: .leading, spacing: 8) {
        Text(date.coffeeShop.name).font(NookTypography.display(25)).lineLimit(2)
          .foregroundStyle(.white)
        Text(formatted).font(NookTypography.business(15, weight: .bold))
          .foregroundStyle(.white)
        HStack(spacing: 7) {
          Text(date.coffeeShop.vibeLabel)
          Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
          Text(date.paymentPreference.title)
        }
        .font(NookTypography.business(12)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
        actionRow
      }.padding(16)
    }
    .clipShape(RoundedRectangle(cornerRadius: NookRadius.medium, style: .continuous))
    .padding(.vertical, 4)
  }
  @ViewBuilder private var actionRow: some View {
    if date.status == .pending || date.status == .counterProposed {
      HStack(spacing: 8) {
        if canAccept {
          proposalButton(updating ? "Aceptando…" : "Aceptar", primary: true, action: accept)
        } else {
          Text("Esperando respuesta").font(NookTypography.business(12, weight: .bold))
            .foregroundStyle(.white.opacity(0.78)).frame(maxWidth: .infinity, alignment: .leading)
        }
        proposalButton("Cambiar", primary: false, action: change)
      }
    } else {
      Text(date.status == .accepted ? "ACEPTADO" : date.status.rawValue)
        .font(NookTypography.business(11, weight: .bold)).tracking(0.8)
        .foregroundStyle(NookColors.mocha)
    }
  }
  private func proposalButton(
    _ title: String, primary: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title).font(NookTypography.business(12, weight: .bold))
        .frame(maxWidth: .infinity).frame(height: 38)
        .foregroundStyle(primary ? NookColors.inverseText : .white)
        .background(primary ? NookColors.espresso : .white.opacity(0.14), in: Capsule())
    }.buttonStyle(.plain).disabled(updating)
  }
  private var formatted: String { date.formattedProposedAt() }
}

struct ChatCoffeePicker: View {
  @EnvironmentObject var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let conversation: Conversation
  let proposal: CoffeeDate?
  @StateObject private var location = LocationManager()
  @State private var shops: [CoffeeShop] = []
  @State private var selected: CoffeeShop?
  @State private var locationMessage: String?
  @State private var loading = true
  var body: some View {
    NavigationStack {
      ZStack {
        NookInteriorBackdrop()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            Text("Elige vuestro café").font(NookTypography.title).padding(.bottom, 8)
            if loading {
              NookSkeletonScreen(layout: .list(rows: 5))
            } else if shops.isEmpty && locationMessage == nil {
              NookEmptyState(icon: "cup.and.saucer", title: "No encontramos cafeterías",
                text: "Prueba de nuevo desde otra zona.")
                .containerRelativeFrame(.vertical, alignment: .center)
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
          ProposalSheet(
            shop: shop,
            matches: [Match(
              id: conversation.matchId, person: conversation.person,
              matchedAt: conversation.updatedAt, conversationId: conversation.id)],
            existingProposal: proposal)
        }
        .onDisappear { location.stop() }
    }
  }
}

struct MyCafesUnifiedList: View {
  @EnvironmentObject private var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let items: [MyCafeItem]
  let updating: Set<UUID>
  let filteredEmptyText: String?
  let action: (UUID, CoffeeDateStatus) -> Void
  let removeMatch: (UUID) -> Void
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if items.isEmpty {
          VStack(spacing: 16) {
            if let filteredEmptyText {
              compactEmptyState(
                icon: "line.3.horizontal.decrease", title: "Nada en este filtro",
                text: filteredEmptyText)
            } else {
              compactEmptyState(
                icon: "cup.and.saucer", title: "Tu primer café te espera",
                text: "Conecta con alguien y vuestra próxima cita aparecerá aquí.")
              Button {
                app.selectedTab = 0
                dismiss()
              } label: {
                Text("Descubrir personas")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(.white)
                  .padding(.horizontal, 20).frame(height: 44)
                  .background(NookColors.espresso, in: Capsule())
              }.buttonStyle(.plain)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 72)
        } else {
          cafeSection("Matches", icon: "heart", items: connectionItems)
          cafeSection("Requieren tu atención", icon: "bell", items: attentionItems)
          cafeSection("Próximos cafés", icon: "calendar", items: upcomingItems)
          cafeSection("Historial", icon: "clock", items: historyItems)
        }
      }
      .containerRelativeFrame(.horizontal)
      .padding(.top, 2)
      .padding(.bottom, 32)
    }
    .contentMargins(.horizontal, 20, for: .scrollContent)
    .scrollIndicators(.hidden)
    .transaction { transaction in transaction.animation = nil }
  }
  @ViewBuilder private func cafeSection(
    _ title: String, icon: String, items values: [MyCafeItem]
  ) -> some View {
    if !values.isEmpty {
      HStack(spacing: 8) {
        Label(title, systemImage: icon)
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .tracking(-0.15)
        Spacer()
        Text("\(values.count)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(NookColors.warmGray)
      }
      .foregroundStyle(NookColors.espresso)
      .padding(.top, 16)
      .padding(.bottom, 10)

      ForEach(values) { item in
        MyCafeUnifiedCard(
          item: item, isUpdating: updating.contains(item.proposal?.id ?? item.matchId),
          action: action, removeMatch: removeMatch)
          .padding(.bottom, 9)
      }
    }
  }
  private func compactEmptyState(icon: String, title: String, text: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 23, weight: .medium))
        .foregroundStyle(NookColors.mocha)
        .frame(width: 54, height: 54)
        .background(NookColors.offWhite, in: Circle())
      Text(title)
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(NookColors.espresso)
      Text(text)
        .font(.system(size: 14))
        .foregroundStyle(NookColors.warmGray)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .frame(maxWidth: 280)
    }
  }
  private var attentionItems: [MyCafeItem] {
    items.filter {
      guard let proposal = $0.proposal else { return false }
      return proposal.status == .pending || proposal.status == .counterProposed
    }
  }
  private var upcomingItems: [MyCafeItem] {
    items.filter { $0.proposal?.status == .accepted }
  }
  private var connectionItems: [MyCafeItem] {
    items.filter { $0.proposal == nil }
  }
  private var historyItems: [MyCafeItem] {
    items.filter {
      guard let status = $0.proposal?.status else { return false }
      return [.completed, .cancelled, .declined, .expired].contains(status)
    }
  }
}

private struct MyCafesSkeletonView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var glowing = false
  @State private var revealed = false

  var body: some View {
    GeometryReader { proxy in
      let cardCount = max(3, Int(ceil(proxy.size.height / 254)) + 1)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<cardCount, id: \.self) { index in
            if index.isMultiple(of: 2) {
              sectionPlaceholder
                .skeletonReveal(revealed, order: index, reduceMotion: reduceMotion)
            }
            ticketPlaceholder
              .padding(.bottom, 9)
              .skeletonReveal(revealed, order: index + 1, reduceMotion: reduceMotion)
          }
        }
        .containerRelativeFrame(.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 32)
      }
      .contentMargins(.horizontal, 20, for: .scrollContent)
      .scrollDisabled(true)
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.white)
    .onAppear {
      revealed = true
      if !reduceMotion {
        withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
          glowing = true
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Cargando tus cafés")
  }

  private var agendaPlaceholder: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          block(width: 92, height: 8, light: true)
          block(width: 188, height: 22, light: true)
        }
        Spacer()
        Circle().fill(Color.white.opacity(0.18)).frame(width: 44, height: 44)
      }
      HStack(spacing: 18) {
        metricPlaceholder
        metricPlaceholder
        metricPlaceholder
      }
    }
    .padding(18)
    .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        .padding(6)
    }
  }

  private var sectionPlaceholder: some View {
    HStack(spacing: 8) {
      Circle().fill(NookColors.espresso.opacity(glowing ? 0.11 : 0.055))
        .frame(width: 17, height: 17)
      block(width: 142, height: 17)
      Spacer()
      block(width: 18, height: 12)
    }
    .padding(.top, 16)
    .padding(.bottom, 10)
  }

  private var ticketPlaceholder: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .center, spacing: 12) {
        Circle().fill(NookColors.espresso.opacity(glowing ? 0.11 : 0.06))
          .frame(width: 56, height: 56)
          .padding(3)
          .background(NookColors.offWhite, in: Circle())
        VStack(alignment: .leading, spacing: 5) {
          block(width: 116, height: 18)
          block(width: 62, height: 10)
        }
        Spacer(minLength: 6)
        block(width: 66, height: 23)
        Circle().fill(NookColors.espresso.opacity(glowing ? 0.09 : 0.045))
          .frame(width: 28, height: 28)
      }

      HStack(spacing: 7) {
        dashedPlaceholder
        Circle().fill(NookColors.mocha.opacity(0.14)).frame(width: 9, height: 9)
        dashedPlaceholder
      }
      .padding(.horizontal, 2)

      VStack(alignment: .leading, spacing: 8) {
        block(width: 196, height: 14)
        block(width: 244, height: 11)
      }

      HStack(spacing: 8) {
        block(width: 118, height: 36)
        block(width: 104, height: 36)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 13)
    .frame(height: 222, alignment: .top)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background { CafePassShape().fill(Color.white) }
    .overlay {
      CafePassShape().stroke(NookColors.espresso.opacity(0.085), lineWidth: 0.8)
    }
    .overlay(alignment: .topLeading) {
      Capsule()
        .fill(NookColors.mocha.opacity(glowing ? 0.34 : 0.18))
        .frame(width: 3, height: 35)
        .offset(x: 7, y: 24)
    }
    .shadow(color: NookColors.espresso.opacity(0.028), radius: 7, y: 3)
  }

  private var dashedPlaceholder: some View {
    Rectangle()
      .stroke(
        NookColors.espresso.opacity(0.10),
        style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
      .frame(height: 1)
  }

  private var metricPlaceholder: some View {
    VStack(alignment: .leading, spacing: 5) {
      block(width: 28, height: 21, light: true)
      block(width: 58, height: 8, light: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func block(width: CGFloat, height: CGFloat, light: Bool = false) -> some View {
    Capsule().fill(NookColors.espresso.opacity(light ? (glowing ? 0.16 : 0.08) : (glowing ? 0.11 : 0.055)))
      .frame(width: width, height: height)
  }
}

private extension View {
  func skeletonReveal(_ visible: Bool, order: Int, reduceMotion: Bool) -> some View {
    opacity(visible ? 1 : 0)
      .offset(y: visible || reduceMotion ? 0 : -16)
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.18).delay(Double(order) * 0.075),
        value: visible)
  }
}

private struct MyCafesAgendaOverview: View {
  let items: [MyCafeItem]
  private var featured: MyCafeItem? {
    items.first { $0.proposal?.status == .accepted }
      ?? items.first { $0.proposal?.status == .pending || $0.proposal?.status == .counterProposed }
  }
  private var upcoming: Int { items.filter { $0.proposal?.status == .accepted }.count }
  private var pending: Int {
    items.filter {
      $0.proposal?.status == .pending || $0.proposal?.status == .counterProposed
    }.count
  }
  var body: some View {
    ZStack(alignment: .topTrailing) {
      NookColors.espresso

      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text(featured?.proposal?.status == .accepted ? "PRÓXIMO CAFÉ" : "TU TARJETERO")
              .font(.system(size: 9, weight: .bold))
              .tracking(1.8)
              .foregroundStyle(NookColors.cream.opacity(0.72))
            if let featured {
              Text(featured.person.name)
                .font(NookTypography.business(24, weight: .bold))
                .foregroundStyle(.white)
            } else {
              Text("Cafés que están por venir")
                .font(NookTypography.business(22, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          Spacer()
          if let featured {
            ProfileImage(url: featured.person.photos.first?.url, name: featured.person.name)
              .frame(width: 44, height: 44)
              .clipShape(Circle())
              .overlay(Circle().stroke(NookColors.cream.opacity(0.50), lineWidth: 1))
          } else {
            Image(systemName: "cup.and.saucer.fill")
              .font(.system(size: 21, weight: .light))
              .foregroundStyle(NookColors.cream.opacity(0.78))
          }
        }

        if let proposal = featured?.proposal {
          HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
            Text(proposal.coffeeShop.name)
            Text("·")
            Text(proposal.formattedProposedAt(dateStyle: .short))
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.72))
          .lineLimit(1)
        }

        HStack(spacing: 0) {
          agendaMetric(value: upcoming, label: "Próximos")
          divider
          agendaMetric(value: pending, label: "Pendientes")
          divider
          agendaMetric(value: items.count, label: "Conexiones")
        }
      }
      .padding(18)
    }
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          NookColors.cream.opacity(0.25),
          style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        .padding(6)
    }
    .shadow(color: NookColors.espresso.opacity(0.10), radius: 8, y: 4)
  }
  private func agendaMetric(value: Int, label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(value)")
        .font(NookTypography.business(24, weight: .bold))
        .foregroundStyle(.white)
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.68))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  private var divider: some View {
    Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 34).padding(.horizontal, 12)
  }
}

private struct ArchiveCardShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 12))
    path.addQuadCurve(to: CGPoint(x: 12, y: 0), control: .zero)
    path.addLine(to: CGPoint(x: rect.maxX - 35, y: 0))
    path.addLine(to: CGPoint(x: rect.maxX - 20, y: 12))
    path.addLine(to: CGPoint(x: rect.maxX, y: 12))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 14))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - 14, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: 14, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: 0, y: rect.maxY - 14),
      control: CGPoint(x: 0, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

/// A restrained coffee-ticket silhouette shared by every item in Mis cafés.
/// The cut corner and side notches give the screen its own visual language
/// without changing the information architecture between states.
private struct CafePassShape: Shape {
  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 18
    let notchY = min(88, rect.height * 0.46)
    let notchDepth: CGFloat = 7
    let notchRadius: CGFloat = 9
    var path = Path()

    path.move(to: CGPoint(x: radius, y: 0))
    path.addLine(to: CGPoint(x: rect.maxX - 34, y: 0))
    path.addLine(to: CGPoint(x: rect.maxX - 16, y: 16))
    path.addLine(to: CGPoint(x: rect.maxX, y: 16))
    path.addLine(to: CGPoint(x: rect.maxX, y: notchY - notchRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - notchDepth, y: notchY),
      control: CGPoint(x: rect.maxX - notchDepth, y: notchY - notchRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: notchY + notchRadius),
      control: CGPoint(x: rect.maxX - notchDepth, y: notchY + notchRadius))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: radius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: 0, y: rect.maxY - radius),
      control: CGPoint(x: 0, y: rect.maxY))
    path.addLine(to: CGPoint(x: 0, y: notchY + notchRadius))
    path.addQuadCurve(
      to: CGPoint(x: notchDepth, y: notchY),
      control: CGPoint(x: notchDepth, y: notchY + notchRadius))
    path.addQuadCurve(
      to: CGPoint(x: 0, y: notchY - notchRadius),
      control: CGPoint(x: notchDepth, y: notchY - notchRadius))
    path.addLine(to: CGPoint(x: 0, y: radius))
    path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
    path.closeSubpath()
    return path
  }
}

private struct MyCafeUnifiedCard: View {
  @EnvironmentObject private var app: AppSession
  @Environment(\.dismiss) private var dismiss
  let item: MyCafeItem
  let isUpdating: Bool
  let action: (UUID, CoffeeDateStatus) -> Void
  let removeMatch: (UUID) -> Void
  @State private var showingDetail = false
  @State private var confirmingUnmatch = false
  @State private var photoIndex = 0
  @State private var photoSwipeOffset: CGFloat = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .center, spacing: 12) {
        profilePhotoCarousel

        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(item.person.name)
              .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("· \(item.person.age)")
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(NookColors.warmGray)
          }
          .foregroundStyle(NookColors.espresso)
          .lineLimit(1).truncationMode(.tail)
        }

        Spacer(minLength: 6)
        statusBadge
        optionsMenu
      }

      ticketDivider
      appointmentDetails
      actionRow
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 13)
    .frame(height: 222, alignment: .top)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background { CafePassShape().fill(Color.white) }
    .overlay {
      CafePassShape().stroke(NookColors.espresso.opacity(0.085), lineWidth: 0.8)
    }
    .overlay(alignment: .topLeading) {
      Capsule()
        .fill(stateAccent)
        .frame(width: 3, height: 35)
        .offset(x: 7, y: 24)
    }
    .shadow(color: NookColors.espresso.opacity(0.028), radius: 7, y: 3)
    .overlay { if isUpdating { ProgressView().tint(NookColors.espresso).padding(12).background(Color.white.opacity(0.92), in: Circle()) } }
    .contentShape(CafePassShape())
    .sheet(isPresented: $showingDetail) {
      if let proposal = item.proposal {
        CoffeeDateDetail(date: proposal, person: item.person, conversation: conversation, isUpdating: isUpdating, action: action)
      }
    }
    .alert("¿Deshacer este match?", isPresented: $confirmingUnmatch) {
      Button("Conservar match", role: .cancel) {}
      Button("Deshacer match", role: .destructive) { removeMatch(item.matchId) }
    } message: {
      Text("La conexión con \(item.person.name) desaparecerá de Mis cafés.")
    }
    .dynamicTypeSize(.xSmall ... .xLarge)
  }
  @ViewBuilder private var statusEmblemView: some View {
    if let emblem = statusEmblem {
      Image(systemName: emblem.icon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(item.proposal == nil ? NookColors.nookGold : NookColors.espresso)
        .frame(width: 41, height: 41)
        .background(Color.white, in: Circle())
        .overlay(Circle().stroke(NookColors.espresso.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(emblem.accessibilityLabel)
    }
  }
  private var profilePhotoCarousel: some View {
    let photos = item.person.photos
    let safeIndex = photos.isEmpty ? 0 : min(photoIndex, photos.count - 1)
    let nextIndex = photos.isEmpty ? 0 : (safeIndex + 1) % photos.count
    return ZStack(alignment: .bottomTrailing) {
      ZStack {
        if photos.count > 1 {
          ProfileImage(url: photos[nextIndex].url, name: item.person.name)
            .frame(width: 56, height: 56)
        }
        ProfileImage(url: photos.isEmpty ? nil : photos[safeIndex].url, name: item.person.name)
          .frame(width: 56, height: 56)
          .offset(x: min(0, photoSwipeOffset))
      }
      .clipShape(Circle())
      .overlay(Circle().stroke(NookColors.nookGold.opacity(0.92), lineWidth: 1.5))
      .padding(3)
      .background(NookColors.offWhite, in: Circle())

      if photos.count > 1 {
        Text("\(safeIndex + 1)/\(photos.count)")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 5).frame(height: 17)
          .background(.black.opacity(0.38), in: Capsule())
          .padding(5)
      }
    }
    .frame(width: 62, height: 62)
    .contentShape(Rectangle())
    .onTapGesture { advanceProfilePhoto() }
    .gesture(
      DragGesture(minimumDistance: 12)
        .onChanged { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          photoSwipeOffset = min(0, value.translation.width)
        }
        .onEnded { value in
          if value.translation.width < -18 { advanceProfilePhoto() }
          else { withAnimation(.easeOut(duration: 0.18)) { photoSwipeOffset = 0 } }
        }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Foto \(safeIndex + 1) de \(max(1, photos.count)) de \(item.person.name)")
    .accessibilityAddTraits(photos.count > 1 ? .isButton : [])
  }
  private func advanceProfilePhoto() {
    guard item.person.photos.count > 1 else { return }
    Haptics.selection()
    withAnimation(.easeOut(duration: 0.20)) { photoSwipeOffset = -64 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
      photoIndex = (photoIndex + 1) % item.person.photos.count
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { photoSwipeOffset = 0 }
    }
  }
  private var statusEmblem: (icon: String, label: String, accessibilityLabel: String)? {
    guard let proposal = item.proposal else {
      return ("heart.fill", "MATCH", "Match")
    }
    if proposal.status == .pending && proposal.senderId == app.me?.id {
      return ("paperplane.fill", "ENVIADA", "Propuesta enviada")
    }
    if proposal.status == .pending {
      return ("envelope.fill", "RECIBIDA", "Propuesta recibida")
    }
    if proposal.status == .counterProposed {
      return ("arrow.triangle.2.circlepath", "NUEVA", "Nueva propuesta")
    }
    if proposal.status == .accepted {
      return ("checkmark", "CONFIRMADA", "Cita confirmada")
    }
    if proposal.status == .completed {
      return ("cup.and.saucer.fill", "COMPLETADA", "Cita completada")
    }
    if proposal.status == .cancelled {
      return ("xmark.circle.fill", "CANCELADA", "Cita cancelada")
    }
    if proposal.status == .declined {
      return ("hand.thumbsdown.fill", "RECHAZADA", "Propuesta rechazada")
    }
    if proposal.status == .expired {
      return ("clock.badge.exclamationmark", "CADUCADA", "Propuesta caducada")
    }
    return nil
  }
  private var statusBadge: some View {
    Label(statusEmblem?.label.capitalized ?? statusText.capitalized, systemImage: statusIcon)
      .font(.system(size: 9, weight: .semibold))
      .lineLimit(1).minimumScaleFactor(0.72)
      .padding(.horizontal, 8).frame(height: 23)
      .background(statusBadgeBackground, in: Capsule())
      .foregroundStyle(statusBadgeForeground)
  }
  private var ticketDivider: some View {
    HStack(spacing: 7) {
      Rectangle()
        .stroke(
          NookColors.espresso.opacity(0.10),
          style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        .frame(height: 1)
      Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(NookColors.mocha.opacity(0.55))
      Rectangle()
        .stroke(
          NookColors.espresso.opacity(0.10),
          style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        .frame(height: 1)
    }
    .padding(.horizontal, 2)
  }
  private var nookChoiceBadge: some View {
    Label("ELECCIÓN NOOK", systemImage: "sparkles")
      .font(.system(size: 9, weight: .heavy, design: .default))
      .tracking(0.65)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .foregroundStyle(NookColors.inverseText)
      .padding(.horizontal, 10)
      .frame(height: 23)
      .background(NookColors.mocha, in: Capsule())
      .accessibilityLabel("Elección Nook")
  }
  @ViewBuilder private var appointmentDetails: some View {
    if let proposal = item.proposal {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
          Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NookColors.mocha)
            .frame(width: 20)
          Text(proposal.coffeeShop.name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NookColors.espresso)
            .lineLimit(2).truncationMode(.tail)
        }
        HStack(spacing: 9) {
          Image(systemName: "calendar")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 20)
          Text(proposal.formattedProposedAt(dateStyle: .medium))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(NookColors.warmGray)
            .lineLimit(1).minimumScaleFactor(0.82)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack(spacing: 9) {
        Image(systemName: "calendar.badge.plus")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(NookColors.mocha)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 1) {
          Text("Sin fecha todavía")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NookColors.espresso)
          Text("Crea vuestra primera cita")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(NookColors.warmGray)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 2)
    }
  }
  @ViewBuilder private var context: some View {
    if let proposal = item.proposal {
      HStack(spacing: 12) {
        VStack(spacing: 2) {
          Image(systemName: "calendar")
            .font(.system(size: 15, weight: .semibold))
          Text("CITA")
            .font(.system(size: 7.5, weight: .bold))
            .tracking(0.8)
        }
        .foregroundStyle(NookColors.mocha)
        .frame(width: 40, height: 38)
        .background(NookColors.cream.opacity(0.82), in: RoundedRectangle(cornerRadius: 11))

        VStack(alignment: .leading, spacing: 4) {
          Text(proposal.coffeeShop.name)
            .font(.system(size: 14.5, weight: .bold))
            .foregroundStyle(NookColors.espresso)
          Text(proposal.formattedProposedAt(dateStyle: .medium))
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(NookColors.warmGray)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(NookColors.mocha.opacity(0.55))
      }
      .padding(6)
      .background(NookColors.cream.opacity(0.38), in: RoundedRectangle(cornerRadius: 13))
    } else {
      HStack(spacing: 10) {
        Image(systemName: "cup.and.saucer")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(NookColors.mocha)
        VStack(alignment: .leading, spacing: 2) {
          Text("Todavía no hay una cita")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(NookColors.espresso)
          Text("Elegid cafetería, día y hora")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NookColors.warmGray)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(NookColors.cream.opacity(0.44), in: RoundedRectangle(cornerRadius: 13))
    }
  }
  @ViewBuilder private var actionRow: some View {
    if item.availableActions.contains("ACCEPT"), let proposal = item.proposal {
      HStack(spacing: 8) {
        actionButton("Aceptar", icon: "checkmark", primary: true) { action(proposal.id, .accepted) }
        actionButton("Rechazar", icon: "xmark", primary: false) { action(proposal.id, .declined) }
        if item.availableActions.contains("CHAT") { chatButton }
      }
    } else if item.availableActions.contains("PROPOSE") {
      HStack(spacing: 8) {
        proposeCoffeeButton
        if item.availableActions.contains("CHAT") { chatButton }
      }
    } else if item.proposal?.status == .accepted {
      HStack(spacing: 8) {
        actionButton("Ver detalles", icon: "calendar", primary: true) { showingDetail = true }
        if item.availableActions.contains("CHAT") { chatButton }
      }
    } else {
      HStack(spacing: 8) {
        Text(statusDetail)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(NookColors.warmGray)
          .lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 4)
        if item.availableActions.contains("CHAT") { chatButton }
      }
      .frame(minHeight: 32)
    }
  }
  private var proposeCoffeeButton: some View {
    Button { propose() } label: {
      HStack(spacing: 9) {
        Image(systemName: "cup.and.saucer.fill")
          .font(.system(size: 14, weight: .semibold))
        Text("Quedar para un café")
          .font(.system(size: 14, weight: .semibold))
        Spacer(minLength: 8)
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 15)
      .frame(maxWidth: .infinity)
      .frame(height: 40)
      .background(NookColors.espresso, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isUpdating)
    .accessibilityLabel("Quedar para un café. Elige lugar, día y hora")
  }
  private func actionButton(_ title: String, icon: String, primary: Bool, perform: @escaping () -> Void) -> some View {
    Button(action: perform) {
      Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        .minimumScaleFactor(0.72).frame(maxWidth: .infinity).frame(height: 38)
        .foregroundStyle(primary ? NookColors.inverseText : NookColors.espresso)
        .background(primary ? NookColors.espresso : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NookColors.espresso.opacity(primary ? 0 : 0.07)))
    }.buttonStyle(.plain).disabled(isUpdating)
  }
  private var chatButton: some View {
    NavigationLink { ChatDetail(conversation: conversation) } label: {
      Image(systemName: "bubble.left.fill").font(.caption).frame(width: 38, height: 38)
        .background(Color.white, in: Circle())
        .overlay(Circle().stroke(NookColors.espresso.opacity(0.09), lineWidth: 0.8))
    }.buttonStyle(.plain).foregroundStyle(NookColors.espresso).accessibilityLabel("Abrir chat")
  }
  private var optionsMenu: some View {
    Menu {
      if item.proposal != nil {
        Button { showingDetail = true } label: {
          Label("Ver detalle", systemImage: "doc.text.magnifyingglass")
        }
      }
      Button(role: .destructive) { confirmingUnmatch = true } label: {
        Label("Deshacer match", systemImage: "person.crop.circle.badge.xmark")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(NookColors.espresso.opacity(0.62))
    .accessibilityLabel("Más opciones")
  }
  private var conversation: Conversation {
    Conversation(id: item.conversationId, matchId: item.matchId, person: item.person, lastMessage: "", updatedAt: item.matchedAt)
  }
  private var personSummary: String {
    let bio = item.person.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    return bio.isEmpty ? "\(item.person.age) años" : "\(item.person.age) años · \(bio)"
  }
  private var lastInteraction: String {
    let raw = item.proposal?.createdAt ?? item.matchedAt
    guard let date = ISO8601DateFormatter.nook.date(from: raw) else { return "" }
    if Calendar.current.isDateInToday(date) { return "Hoy" }
    if Calendar.current.isDateInYesterday(date) { return "Ayer" }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }
  private func propose() {
    app.selectedCoffeeMatch = item.matchId
    app.placesReloadID = UUID()
    app.selectedTab = 1
    dismiss()
  }
  private var statusText: String {
    guard let proposal = item.proposal else { return "MATCH" }
    switch proposal.status {
    case .pending: return proposal.receiverId == app.me?.id ? "TE HAN PROPUESTO UN CAFÉ" : "PROPUESTA ENVIADA"
    case .counterProposed: return "NUEVA PROPUESTA"
    case .accepted: return "CONFIRMADO"
    case .completed: return "COMPLETADO"
    case .cancelled: return "CANCELADO"
    case .declined: return "RECHAZADO"
    case .expired: return "CADUCADO"
    }
  }
  private var statusDetail: String {
    guard let proposal = item.proposal else { return "Aún no habéis propuesto un café" }
    if proposal.status == .pending && proposal.senderId == app.me?.id { return "Esperando respuesta" }
    return statusText.capitalized
  }
  private var statusIcon: String {
    switch item.proposal?.status { case .accepted: "checkmark"; case .pending, .counterProposed: "hourglass"; case .completed: "cup.and.saucer.fill"; case .cancelled, .declined, .expired: "xmark"; case nil: "heart.fill" }
  }
  private var statusColor: Color {
    switch item.proposal?.status {
    case .accepted: NookColors.mocha
    case .pending, .counterProposed: NookColors.amber.opacity(0.28)
    case .completed: NookColors.success.opacity(0.32)
    case .cancelled, .declined, .expired: NookColors.cream.opacity(0.72)
    case nil: matchGold.opacity(0.82)
    }
  }
  private var statusForeground: Color { NookColors.espresso }
  private var statusBadgeBackground: Color {
    switch item.proposal?.status {
    case .accepted: NookColors.success.opacity(0.13)
    case .pending, .counterProposed: NookColors.amber.opacity(0.14)
    case .completed: NookColors.mocha.opacity(0.11)
    case .cancelled, .declined, .expired: NookColors.espresso.opacity(0.055)
    case nil: NookColors.nookGold.opacity(0.16)
    }
  }
  private var statusBadgeForeground: Color { NookColors.espresso.opacity(0.78) }
  private var stateAccent: Color {
    switch item.proposal?.status {
    case .accepted: NookColors.success.opacity(0.72)
    case .pending, .counterProposed: NookColors.amber.opacity(0.78)
    case .completed: NookColors.mocha.opacity(0.68)
    case .cancelled, .declined, .expired: NookColors.espresso.opacity(0.22)
    case nil: NookColors.nookGold
    }
  }
  private var needsAttention: Bool {
    guard let status = item.proposal?.status else { return true }
    return status == .pending || status == .counterProposed
  }
  private var attentionColor: Color { item.proposal == nil ? matchGold : NookColors.amber }
  private var matchGold: Color { NookColors.nookGold }
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
              Text(value.rawValue).font(.system(size: 13, weight: .bold, design: .default))
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
              .containerRelativeFrame(.vertical, alignment: .center)
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
      Text(title).font(.system(size: 11, weight: .bold, design: .default)).tracking(1.6)
        .foregroundStyle(NookColors.mocha).padding(.top, 12).padding(.leading, 4)
      ForEach(values) { date in
        ticket(date)
      }
    }
  }
  @ViewBuilder private var matchSection: some View {
    if !unplannedMatches.isEmpty {
      Text("MATCHES SIN PROPUESTA").font(.system(size: 11, weight: .bold, design: .default))
        .tracking(1.6).foregroundStyle(NookColors.mocha).padding(.top, 12).padding(.leading, 4)
      ForEach(unplannedMatches) { match in
        MyCafesCardFrame {
          Button {
            app.selectedCoffeeMatch = match.id
            app.placesReloadID = UUID()
            app.selectedTab = 1
          } label: {
            ZStack(alignment: .bottomLeading) {
              ProfileImage(url: match.person.photos.first?.url, name: match.person.name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
              LinearGradient(
                colors: [.clear, NookColors.warmBlack.opacity(0.38), NookColors.warmBlack],
                startPoint: .top, endPoint: .bottom)
              VStack(alignment: .leading, spacing: 8) {
                Label("MATCH", systemImage: "cup.and.saucer.fill")
                  .font(.system(size: 10, weight: .bold, design: .default)).tracking(1)
                  .padding(.horizontal, 10).frame(height: 28)
                  .background(NookColors.mocha, in: Capsule())
                Spacer()
                Text(match.person.name).font(NookTypography.display(30)).lineLimit(1)
                  .truncationMode(.tail).minimumScaleFactor(0.72)
                HStack(spacing: 7) {
                  Image(systemName: "mappin.and.ellipse").foregroundStyle(NookColors.mocha)
                  Text("Elegid una cafetería y proponed un día").lineLimit(1)
                    .truncationMode(.tail)
                  Spacer(minLength: 4)
                  Image(systemName: "arrow.right").font(.caption.bold())
                }.font(.system(size: 13, weight: .semibold, design: .default))
                  .foregroundStyle(.white.opacity(0.86))
              }.padding(14)
            }
            .foregroundStyle(.white)
          }.buttonStyle(.plain).frame(maxWidth: .infinity)
        }
      }
    }
  }
  private func ticket(_ date: CoffeeDate) -> some View {
    MyCafesCardFrame {
      CoffeeTicket(
        date: date, person: matches.first(where: { $0.id == date.matchId })?.person,
        conversation: conversations.first(where: { $0.matchId == date.matchId }),
        isUpdating: updating.contains(date.id), action: action)
    }
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

/// Gives every My Cafes row the exact width proposed by the vertical scroll view.
/// Intrinsic text/button sizes can no longer expand an individual card beyond the screen.
private struct MyCafesCardFrame<Content: View>: View {
  private let height: CGFloat = 208
  @ViewBuilder let content: () -> Content
  var body: some View {
    GeometryReader { proxy in
      content()
        .frame(width: proxy.size.width, height: height)
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    .shadow(color: NookColors.warmBlack.opacity(0.13), radius: 10, y: 5)
  }
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
                .font(.system(size: 9, weight: .bold, design: .default)).tracking(0.9)
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
                  .frame(width: 42, height: 42).clipShape(Circle())
                  .overlay { Circle().stroke(NookColors.mocha, lineWidth: 2) }
              }.buttonStyle(.plain).accessibilityLabel("Ver perfil de \(person.name)")
            }
              Text(person?.name ?? "Tu cita").font(NookTypography.business(27, weight: .bold)).tracking(-0.2)
                .lineLimit(1).truncationMode(.tail).minimumScaleFactor(0.72)
              Spacer(minLength: 0)
            }
            HStack(spacing: 7) {
              Image(systemName: "mappin.and.ellipse").foregroundStyle(NookColors.mocha).frame(width: 17)
              Text(date.coffeeShop.name).font(.system(size: 17, weight: .bold, design: .default))
                .lineLimit(1).truncationMode(.tail)
            }
            HStack(spacing: 7) {
              Image(systemName: "calendar").foregroundStyle(NookColors.mocha).frame(width: 17)
              Text(date.formattedProposedAt(dateStyle: .full)).lineLimit(1).minimumScaleFactor(0.85)
            }.font(.system(size: 12, weight: .semibold, design: .default))
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
  private var cardHeight: CGFloat { 208 }
  private var statusLabel: some View {
    HStack(spacing: 5) {
      Image(systemName: statusIcon)
      Text(statusText)
    }.font(.system(size: 10, weight: .bold, design: .default)).lineLimit(1)
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
            Text("Actualizando…").font(.system(size: 12, weight: .semibold, design: .default))
          }.frame(height: 34)
        } else {
          HStack {
            Button("Aceptar") { safe = true }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(NookColors.espresso)
            Button("Rechazar") { action(date.id, .declined) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.78))
          }
        }
      } else {
        Text("Esperando respuesta").font(.system(size: 12, weight: .semibold, design: .default)).opacity(0.8)
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
            .font(.system(size: 13, weight: .bold, design: .default))
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
        .font(.system(size: 12, weight: .semibold, design: .default)).lineLimit(1)
        .truncationMode(.tail).opacity(0.86)
    } else {
      Text(statusCopy).font(.system(size: 12, weight: .semibold, design: .default)).opacity(0.8)
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
        NookInteriorBackdrop()
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
          }.padding(16).padding(.bottom, 10)
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
      Text(title)
        .font(NookTypography.display(25))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Text(text)
        .font(NookTypography.business(15))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: 330, maxHeight: .infinity, alignment: .center)
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
  }
}
