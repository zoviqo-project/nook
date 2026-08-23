import AudioToolbox
import SwiftUI
import UIKit
import Vision

enum NookColors {
  static let cream = Color(red: 0.105, green: 0.057, blue: 0.035)
  static let oat = Color(red: 0.78, green: 0.65, blue: 0.50)
  static let latte = Color(red: 0.72, green: 0.54, blue: 0.37)
  static let mocha = Color(red: 0.89, green: 0.67, blue: 0.43)
  static let espresso = Color(red: 0.96, green: 0.90, blue: 0.80)
  static let warmBlack = Color(red: 0.075, green: 0.035, blue: 0.021)
  static let offWhite = Color(red: 0.17, green: 0.095, blue: 0.058)
  static let inverseText = Color(red: 0.10, green: 0.052, blue: 0.031)
  static let warmGray = Color(red: 0.73, green: 0.65, blue: 0.57)
  static let success = Color(red: 0.31, green: 0.48, blue: 0.36)
  static let amber = Color(red: 0.79, green: 0.47, blue: 0.22)
}

extension Color {
  static let nookCream = NookColors.cream
  static let nookInk = NookColors.espresso
  static let nookCoffee = NookColors.espresso
  static let nookCoral = NookColors.mocha
  static let nookMint = NookColors.oat
}

enum NookSpacing {
  static let xs: CGFloat = 6
  static let sm: CGFloat = 10
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
  static let xl: CGFloat = 34
  static let xxl: CGFloat = 48
}
enum NookRadius {
  static let small: CGFloat = 14
  static let medium: CGFloat = 22
  static let large: CGFloat = 28
  static let hero: CGFloat = 34
  static let pill: CGFloat = 999
}
enum NookMotion {
  static let fast = Animation.easeOut(duration: 0.18)
  static let normal = Animation.easeInOut(duration: 0.34)
  static let slow = Animation.easeInOut(duration: 0.62)
  static let spring = Animation.spring(response: 0.48, dampingFraction: 0.78)
  static let playful = Animation.spring(response: 0.55, dampingFraction: 0.62)
}

enum NookShadow {
  static let subtle = Color.black.opacity(0.06)
  static let card = NookColors.warmBlack.opacity(0.11)
  static let floating = NookColors.warmBlack.opacity(0.19)
}

enum NookTypography {
  static func display(_ size: CGFloat) -> Font { .custom("Fraunces", size: size, relativeTo: .title).weight(.semibold) }
  static func displayItalic(_ size: CGFloat) -> Font { .custom("Fraunces", size: size, relativeTo: .title).weight(.semibold).italic() }
  static func business(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    .custom(weight == .bold || weight == .semibold ? "Avenir Next Demi Bold" : "Avenir Next Medium", size: size)
  }
  static let hero = display(44)
  static let title = display(34)
  static let subtitle = business(20, weight: .semibold)
  static let body = business(17)
  static let caption = business(12, weight: .bold)
}

struct NookBackground: View {
  var body: some View {
    NookColors.warmBlack.ignoresSafeArea()
  }
}

/// A quieter, more ceremonial coffee surface for focused screens such as filters and settings.
struct NookRegalCoffeeBackground: View {
  var body: some View {
    NookBackground()
  }
}

struct NookButton: View {
  enum Kind { case primary, secondary, quiet }
  let title: String
  var icon: String?
  var secondary = false
  var kind: Kind?
  var isLoading = false
  let action: () -> Void
  @State private var pressed = false
  private var style: Kind { kind ?? (secondary ? .secondary : .primary) }
  var body: some View {
    Button {
      guard !isLoading else { return }
      Haptics.selection()
      action()
    } label: {
      HStack(spacing: 10) {
        if isLoading {
          ProgressView().controlSize(.small)
            .tint(style == .primary ? NookColors.inverseText : NookColors.espresso)
        } else if let icon { Image(systemName: icon) }
        Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
      }
      .frame(maxWidth: .infinity).frame(minHeight: 54)
      .foregroundStyle(style == .primary ? NookColors.inverseText : NookColors.espresso)
      .background(backgroundColor, in: Capsule())
      .overlay(
        Capsule().stroke(NookColors.latte.opacity(style == .secondary ? 0.35 : 0), lineWidth: 1)
      )
      .shadow(
        color: style == .primary ? NookColors.espresso.opacity(0.22) : .clear, radius: 18, y: 9
      )
      .scaleEffect(pressed ? 0.97 : 1)
    }.buttonStyle(PressTrackingStyle(isPressed: $pressed))
      .disabled(isLoading)
      .accessibilityValue(isLoading ? "Procesando" : "")
  }
  private var backgroundColor: Color {
    style == .primary
      ? NookColors.espresso : (style == .secondary ? NookColors.offWhite.opacity(0.9) : .clear)
  }
}

struct NookHeader: View {
  let eyebrow: String
  let title: String
  var branded = false
  var actionIcon: String? = nil
  var actionLabel: String = "Acción"
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      if branded {
        HStack(spacing: 10) {
          NookCoffeeLogo(size: 34)
          Text(title).font(NookTypography.display(28)).tracking(-0.35)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(NookColors.espresso)
      } else {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Circle().fill(NookColors.mocha).frame(width: 5, height: 5)
            Text(eyebrow.uppercased())
              .font(.system(size: 10, weight: .bold, design: .rounded))
              .tracking(1.7).foregroundStyle(NookColors.mocha)
          }
          Text(title).font(NookTypography.display(30))
            .tracking(-0.65).lineLimit(1).minimumScaleFactor(0.76)
        }
      }
      Spacer(minLength: 10)
      if let actionIcon, let action {
        Button(action: action) {
          Image(systemName: actionIcon).font(.system(size: 15, weight: .semibold))
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(NookColors.espresso.opacity(0.18), lineWidth: 1))
        }.foregroundStyle(NookColors.espresso).accessibilityLabel(actionLabel)
      }
    }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
  }
}

/// Structural shell for tab screens. The system safe area owns the status-bar spacing,
/// the header is outside the scrolling content, and the tab bar is inserted by MainTabView.
struct NookScreenContainer<Content: View>: View {
  let eyebrow: String
  let title: String
  var solidBackground: Color? = nil
  var brandedHeader = false
  var actionIcon: String? = nil
  var actionLabel = "Acción"
  var action: (() -> Void)? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    ZStack {
      if let solidBackground {
        solidBackground.ignoresSafeArea()
      } else {
        NookBackground()
      }
      VStack(spacing: 0) {
        NookHeader(
          eyebrow: eyebrow, title: title, branded: brandedHeader, actionIcon: actionIcon,
          actionLabel: actionLabel, action: action)
          .zIndex(1)
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

struct NookScrollableScreen<Content: View>: View {
  let eyebrow: String
  let title: String
  var actionIcon: String? = nil
  var actionLabel = "Acción"
  var action: (() -> Void)? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    NookScreenContainer(
      eyebrow: eyebrow, title: title, actionIcon: actionIcon,
      actionLabel: actionLabel, action: action
    ) {
      ScrollView { content().frame(maxWidth: .infinity, alignment: .topLeading) }
        .scrollIndicators(.hidden)
    }
  }
}

struct NookInlineLoading: View {
  var text = "Preparando…"
  var foreground = NookColors.warmGray
  var accent = NookColors.mocha
  @State private var turning = false
  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().stroke(NookColors.oat.opacity(0.28), lineWidth: 3)
        Circle().trim(from: 0.08, to: 0.72).stroke(
          accent,
          style: StrokeStyle(lineWidth: 3, lineCap: .round)
        ).rotationEffect(.degrees(turning ? 360 : 0))
        Image(systemName: "cup.and.saucer.fill").font(.system(size: 9, weight: .bold))
          .foregroundStyle(foreground)
      }.frame(width: 27, height: 27)
      Text(text).font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(foreground)
    }.onAppear {
      withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) { turning = true }
    }
  }
}

enum NookSkeletonLayout {
  case profileCard
  case list(rows: Int)
  case coffeeCards(rows: Int)
  case coffeeDates(rows: Int)
}

struct NookSkeletonScreen: View {
  let layout: NookSkeletonLayout
  @State private var shimmering = false

  var body: some View {
    Group {
      switch layout {
      case .profileCard:
        profileCard
      case .list(let rows):
        list(rows: rows)
      case .coffeeCards(let rows):
        coffeeCards(rows: rows)
      case .coffeeDates(let rows):
        coffeeDates(rows: rows)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Cargando contenido")
    .onAppear {
      withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
        shimmering = true
      }
    }
  }

  private var profileCard: some View {
    GeometryReader { proxy in
      VStack(spacing: 0) {
        skeletonBlock(radius: 30)
          .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 11) {
              skeletonBlock(width: proxy.size.width * 0.52, height: 30, radius: 10)
              skeletonBlock(width: proxy.size.width * 0.72, height: 14, radius: 7)
              HStack(spacing: 8) {
                skeletonBlock(width: 76, height: 28, radius: 14)
                skeletonBlock(width: 96, height: 28, radius: 14)
              }
            }.padding(22)
          }
      }
    }
    .padding(.horizontal, 10).padding(.bottom, 8)
  }

  private func list(rows: Int) -> some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        ForEach(0..<rows, id: \.self) { index in
          HStack(spacing: 14) {
            skeletonBlock(width: 82, height: 92, radius: 19)
            VStack(alignment: .leading, spacing: 10) {
              skeletonBlock(width: index.isMultiple(of: 2) ? 154 : 188, height: 19, radius: 7)
              skeletonBlock(height: 13, radius: 6)
              skeletonBlock(width: 118, height: 13, radius: 6)
              skeletonBlock(width: 92, height: 25, radius: 13)
            }
            Spacer(minLength: 0)
          }
          .padding(12)
          .background(NookColors.offWhite.opacity(0.46), in: RoundedRectangle(cornerRadius: 23))
          .overlay(RoundedRectangle(cornerRadius: 23).stroke(NookColors.espresso.opacity(0.05)))
        }
      }.padding(.horizontal, 16).padding(.top, 6)
    }.scrollIndicators(.hidden)
  }

  private func coffeeCards(rows: Int) -> some View {
    LazyVStack(spacing: 14) {
      ForEach(0..<rows, id: \.self) { index in
        skeletonBlock(height: 242, radius: 26)
          .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 9) {
              skeletonBlock(width: index.isMultiple(of: 2) ? 190 : 225, height: 23, radius: 8)
              HStack(spacing: 8) {
                skeletonBlock(width: 82, height: 25, radius: 13)
                skeletonBlock(width: 108, height: 25, radius: 13)
              }
              skeletonBlock(width: 156, height: 13, radius: 6)
            }.padding(18)
          }
      }
    }.padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 14)
  }

  /// Mirrors CoffeeDatesList: 38pt filters, section caption and 242pt tickets.
  /// Keeping these dimensions shared prevents a layout jump when data arrives.
  private func coffeeDates(rows: Int) -> some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        skeletonBlock(width: 91, height: 38, radius: 19)
        skeletonBlock(width: 82, height: 38, radius: 19)
        skeletonBlock(width: 68, height: 38, radius: 19)
        skeletonBlock(width: 96, height: 38, radius: 19)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          skeletonBlock(width: 142, height: 13, radius: 6)
            .padding(.top, 12).padding(.leading, 4)
          ForEach(0..<rows, id: \.self) { index in
            skeletonBlock(height: 242, radius: 25)
              .overlay(alignment: .top) {
                HStack {
                  if index.isMultiple(of: 2) {
                    skeletonBlock(width: 102, height: 28, radius: 14)
                  }
                  Spacer()
                  skeletonBlock(width: 112, height: 28, radius: 14)
                }.padding(14)
              }
              .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 9) {
                  HStack(spacing: 11) {
                    skeletonBlock(width: 45, height: 45, radius: 23)
                    skeletonBlock(width: index.isMultiple(of: 2) ? 142 : 176, height: 30, radius: 10)
                  }
                  skeletonBlock(width: 184, height: 17, radius: 7)
                  skeletonBlock(width: 226, height: 13, radius: 6)
                  skeletonBlock(width: 138, height: 34, radius: 17)
                }.padding(14)
              }
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 18)
      }.scrollIndicators(.hidden)
    }
  }

  private func skeletonBlock(
    width: CGFloat? = nil, height: CGFloat? = nil, radius: CGFloat
  ) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(NookColors.espresso.opacity(0.09))
      .frame(width: width, height: height)
      .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height == nil ? .infinity : nil)
      .overlay {
        GeometryReader { proxy in
          LinearGradient(
            colors: [.clear, NookColors.mocha.opacity(0.17), .clear],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: max(90, proxy.size.width * 0.58))
          .offset(x: shimmering ? proxy.size.width : -max(90, proxy.size.width * 0.58))
        }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      }
  }
}

private struct PressTrackingStyle: ButtonStyle {
  @Binding var isPressed: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.onChange(of: configuration.isPressed) { _, value in
      withAnimation(NookMotion.fast) { isPressed = value }
    }
  }
}

struct NookTextField: View {
  let label: String
  let icon: String
  @Binding var text: String
  var secure = false
  var keyboard: UIKeyboardType = .default
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label.uppercased()).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(
        1.2
      ).foregroundStyle(focused ? NookColors.mocha : .secondary)
      HStack(spacing: 14) {
        Image(systemName: icon).font(.title3).foregroundStyle(
          focused ? NookColors.espresso : NookColors.warmGray)
        Group {
          if secure {
            SecureField(label, text: $text)
          } else {
            TextField(label, text: $text).keyboardType(keyboard)
          }
        }.font(.system(size: 19, weight: .semibold, design: .rounded)).textInputAutocapitalization(
          keyboard == .emailAddress ? .never : .sentences
        ).focused($focused)
      }.padding(.horizontal, 20).frame(minHeight: 66).background(
        NookColors.offWhite.opacity(0.92),
        in: RoundedRectangle(cornerRadius: NookRadius.medium, style: .continuous)
      ).overlay(
        RoundedRectangle(cornerRadius: NookRadius.medium).stroke(
          focused ? NookColors.mocha : NookColors.oat.opacity(0.55), lineWidth: focused ? 2 : 1)
      ).shadow(color: focused ? NookColors.espresso.opacity(0.1) : .clear, radius: 12, y: 5)
        .animation(NookMotion.fast, value: focused)
    }
  }
}

struct NookChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void
  var body: some View {
    Button {
      Haptics.selection()
      withAnimation(NookMotion.playful) { action() }
    } label: {
      Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).padding(.horizontal, 18)
        .frame(minHeight: 50).foregroundStyle(selected ? NookColors.inverseText : NookColors.espresso)
        .background(
          selected ? NookColors.espresso : NookColors.offWhite.opacity(0.9), in: Capsule()
        ).overlay(Capsule().stroke(NookColors.latte.opacity(0.4))).scaleEffect(selected ? 1.04 : 1)
    }.buttonStyle(.plain)
  }
}

struct NookCard<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    content.padding(NookSpacing.lg).background(
      NookColors.offWhite.opacity(0.94),
      in: RoundedRectangle(cornerRadius: NookRadius.large, style: .continuous)
    ).shadow(color: NookColors.espresso.opacity(0.1), radius: 24, y: 12)
  }
}

struct CoffeeLogo: View {
  var size: CGFloat = 70
  var body: some View {
    NookCoffeeLogo(size: size)
  }
}

struct NookCoffeeLogo: View {
  var size: CGFloat = 76
  var animated = true
  @State private var appeared = false
  var body: some View {
    Image("NookBrandMark")
      .resizable().scaledToFit().frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
      .scaleEffect(animated ? (appeared ? 1 : 0.9) : 1)
      .opacity(animated ? (appeared ? 1 : 0) : 1)
      .shadow(color: NookColors.warmBlack.opacity(size > 48 ? 0.16 : 0), radius: 14, y: 7)
      .onAppear {
        guard animated else { return }
        withAnimation(NookMotion.spring) { appeared = true }
      }
      .accessibilityLabel("Nook")
    }
}

struct NookProgressBar: View {
  let step: Int
  let total: Int
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(NookColors.oat.opacity(0.32))
        Capsule().fill(NookColors.espresso).frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(total))
      }
    }.frame(height: 4).animation(NookMotion.spring, value: step)
  }
}

typealias NookPrimaryButton = NookButton
typealias NookLargeTextField = NookTextField
typealias NookAnswerChip = NookChip

struct NookChatBubble: View {
  let text: String
  let outgoing: Bool
  var body: some View {
    HStack {
      if outgoing { Spacer(minLength: 24) }
      Text(text)
        .font(NookTypography.business(16)).lineSpacing(2)
        .foregroundStyle(outgoing ? NookColors.inverseText : NookColors.espresso)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
          outgoing ? NookColors.espresso : NookColors.offWhite,
          in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      if !outgoing { Spacer(minLength: 24) }
    }
  }
}

struct NookSystemMessageBubble: View {
  let title: String
  let detail: String?
  var body: some View {
    VStack(spacing: 7) {
      Image(systemName: "cup.and.saucer.fill").font(.title3).foregroundStyle(NookColors.mocha)
      Text(title).font(NookTypography.business(13, weight: .bold)).tracking(0.35)
        .multilineTextAlignment(.center)
      if let detail { Text(detail).font(NookTypography.business(12)).foregroundStyle(NookColors.warmGray).multilineTextAlignment(.center) }
    }.frame(maxWidth: .infinity).padding(15)
      .background(NookColors.oat.opacity(0.22), in: RoundedRectangle(cornerRadius: NookRadius.medium))
      .overlay(RoundedRectangle(cornerRadius: NookRadius.medium).stroke(NookColors.oat.opacity(0.5)))
      .padding(.vertical, 6)
  }
}

struct NookVibeBadge: View {
  let vibes: [String]
  private var copy: (String, String) {
    switch vibes.first {
    case "CALM": ("😌 Tranquilo", "Perfecto para hablar")
    case "LIVELY": ("🎵 Animado", "Más energía y ruido")
    case "SOCIAL": ("🙂 Con ambiente", "Movimiento, pero se puede conversar")
    default: ("Vibe sin valorar", "La comunidad aún no lo ha valorado")
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(copy.0).font(.system(size: 15, weight: .bold, design: .rounded))
      Text(copy.1).font(.caption)
    }.foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10).background(
      .ultraThinMaterial.opacity(0.82), in: Capsule())
  }
}

extension View {
  func nookFloatingShadow() -> some View {
    shadow(color: NookColors.espresso.opacity(0.18), radius: 25, y: 14)
  }
}

@MainActor final class NookImageStore {
  static let shared = NookImageStore()
  private let cache = NSCache<NSURL, UIImage>()
  private var inFlight = Set<URL>()
  #if DEBUG
    private var hits = 0
    private var misses = 0
  #endif
  func image(for url: URL) -> UIImage? {
    let value = cache.object(forKey: url as NSURL)
    #if DEBUG
      if value == nil { misses += 1 } else { hits += 1 }
      if (hits + misses).isMultiple(of: 20) {
        print("[PERF] Images cache hit: \(hits)/\(hits + misses)")
      }
    #endif
    return value
  }
  func insert(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
  func prefetch(_ urls: [URL]) {
    for url in urls.prefix(12) where cache.object(forKey: url as NSURL) == nil && !inFlight.contains(url) {
      inFlight.insert(url)
      Task {
        defer { inFlight.remove(url) }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode ?? 200 < 300,
          let image = UIImage(data: data) else { return }
        insert(image, for: url)
      }
    }
  }
}

@MainActor enum NookImagePrefetch {
  static func schedule<S: Sequence>(_ values: S) where S.Element == String {
    NookImageStore.shared.prefetch(values.compactMap(resolve))
  }
  private static func resolve(_ value: String) -> URL? {
    guard !value.isEmpty else { return nil }
    guard value.hasPrefix("/") else { return URL(string: value) }
    guard var components = URLComponents(url: AppConfiguration.apiURL, resolvingAgainstBaseURL: false) else { return nil }
    components.path = value
    components.query = nil
    return components.url
  }
}

struct NookRemoteImage<Placeholder: View>: View {
  let url: URL?
  let contentMode: ContentMode
  let alignment: Alignment
  let faceAware: Bool
  @ViewBuilder let placeholder: () -> Placeholder
  @State private var image: UIImage?
  @State private var detectedAlignment: Alignment?
  @State private var loading = false

  init(
    url: URL?, contentMode: ContentMode = .fill, alignment: Alignment = .center,
    faceAware: Bool = false,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.contentMode = contentMode
    self.alignment = alignment
    self.faceAware = faceAware
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: detectedAlignment ?? alignment)
          .transition(.opacity.animation(.easeOut(duration: 0.22)))
      } else {
        placeholder().overlay {
          if loading {
            NookImageLoadingOverlay()
          }
        }
      }
    }.task(id: url) { await load() }
  }

  private func load() async {
    image = nil
    detectedAlignment = nil
    guard let url else { loading = false; return }
    if let cached = NookImageStore.shared.image(for: url) {
      if faceAware { detectedAlignment = faceAlignment(in: cached) }
      image = cached
      loading = false
      return
    }
    loading = true
    defer { loading = false }
    do {
      var request = URLRequest(url: url)
      request.cachePolicy = .returnCacheDataElseLoad
      let (data, response) = try await URLSession.shared.data(for: request)
      guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode ?? 200 < 300,
        let value = UIImage(data: data) else { return }
      NookImageStore.shared.insert(value, for: url)
      if faceAware { detectedAlignment = faceAlignment(in: value) }
      withAnimation(NookMotion.fast) { image = value }
    } catch is CancellationError {} catch {}
  }

  private func faceAlignment(in image: UIImage) -> Alignment? {
    guard let cgImage = image.cgImage else { return nil }
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    guard (try? handler.perform([request])) != nil,
      let face = request.results?.max(by: {
        $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
      }) else { return nil }
    let centerY = face.boundingBox.midY
    if centerY > 0.62 { return .top }
    if centerY < 0.38 { return .bottom }
    return .center
  }
}

private struct NookImageLoadingOverlay: View {
  @State private var moving = false
  var body: some View {
    GeometryReader { proxy in
      LinearGradient(
        colors: [.clear, NookColors.espresso.opacity(0.18), .clear],
        startPoint: .leading, endPoint: .trailing
      )
      .frame(width: max(80, proxy.size.width * 0.55))
      .offset(x: moving ? proxy.size.width : -max(80, proxy.size.width * 0.55))
      .onAppear {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { moving = true }
      }
    }.allowsHitTesting(false).clipped()
  }
}

struct NookStatusBadge: View {
  let icon: String
  let text: String
  var color: Color = NookColors.mocha
  var body: some View {
    Label(text, systemImage: icon).font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(color).padding(.horizontal, 11).padding(.vertical, 7)
      .background(color.opacity(0.11), in: Capsule())
  }
}

struct NookErrorView: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "wifi.exclamationmark").font(.system(size: 34)).foregroundStyle(NookColors.mocha)
      Text("Ese café se nos ha resistido").font(.title3.bold())
      Text(message).font(.callout).foregroundStyle(NookColors.warmGray).multilineTextAlignment(.center)
      Button("Intentarlo otra vez", action: retry).font(.headline).foregroundStyle(NookColors.espresso)
    }.padding(26).frame(maxWidth: .infinity)
  }
}

@MainActor final class NookSoundManager {
  static let shared = NookSoundManager()
  var enabled: Bool {
    get { UserDefaults.standard.object(forKey: "coffeeSoundsEnabled") as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: "coffeeSoundsEnabled") }
  }
  enum Cue { case intro, coffeeLike, match, searching, proposal, confirmed }
  func play(_ cue: Cue) {
    guard enabled else { return }
    let sound: SystemSoundID
    switch cue {
    case .intro: sound = 1104
    case .coffeeLike: sound = 1105
    case .match: sound = 1111
    case .searching: sound = 1103
    case .proposal: sound = 1109
    case .confirmed: sound = 1110
    }
    AudioServicesPlaySystemSound(sound)
  }
}
