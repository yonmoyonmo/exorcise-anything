import SwiftUI

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func F(_ key: String, _ args: CVarArg...) -> String {
  String(format: L(key), locale: Locale.current, arguments: args)
}

extension Color {
  static let skyStrong = Color(red: 5 / 255, green: 99 / 255, blue: 250 / 255)
  static let brandHill = Color(red: 87 / 255, green: 156 / 255, blue: 2 / 255)
  static let brandCloud = Color(red: 234 / 255, green: 243 / 255, blue: 252 / 255)
  /// YCGS brand gradient, bottom to top: hill 0% → cloud 46% → sky-strong 100%.
  static let brandGradient = LinearGradient(
    stops: [
      .init(color: .brandHill, location: 0), .init(color: .brandCloud, location: 0.46),
      .init(color: .skyStrong, location: 1),
    ], startPoint: .bottom, endPoint: .top)
}
enum Palette {
  static let ink = Color(red: 0.13, green: 0.10, blue: 0.18)
  static let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
  static let purple = Color(red: 0.53, green: 0.07, blue: 0.89)
  static let green = Color(red: 0.42, green: 0.89, blue: 0.07)
  static let gold = Color(red: 1, green: 0.80, blue: 0.22)
  static let hauntedPurple = Color(red: 0x88 / 255, green: 0x11 / 255, blue: 0xE4 / 255)  // #8811E4
  static let hauntedGreen = Color(red: 0x6C / 255, green: 0xE4 / 255, blue: 0x11 / 255)  // #6CE411
  static let halo = Color(red: 1, green: 0xFD / 255, blue: 0xF7 / 255)  // #FFFDF7
  static let ivory = Color(red: 1, green: 0.99, blue: 0.97)
  static func font(_ size: CGFloat) -> Font {
    .custom(
      Locale.preferredLanguages.first?.hasPrefix("ja") == true
        ? "PixelMplus12-Regular" : "Sam3KRFont", size: size, relativeTo: .body)
  }
}
extension View {
  /// Light tap feedback for buttons.
  func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
    simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: style).impactOccurred() })
  }
}
struct GameButton: View {
  let key: String
  var symbol: String? = nil
  var color: Color = Palette.green
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol { Image(systemName: symbol) }
        Text(verbatim: L(key)).multilineTextAlignment(.center)
      }
      .font(Palette.font(18)).frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 12)
      .background(color, in: RoundedRectangle(cornerRadius: 14)).overlay(
        RoundedRectangle(cornerRadius: 14).stroke(Palette.ink, lineWidth: 2))
    }.buttonStyle(.plain).haptic().foregroundStyle(Palette.ink)
  }
}
struct GoldBadge: View {
  @Environment(GameStore.self) var store
  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "g.circle.fill")
      Text(verbatim: "\(store.gold)").monospacedDigit()
    }
    .font(Palette.font(16)).padding(.horizontal, 10).padding(.vertical, 6).background(
      Palette.gold, in: Capsule()
    ).foregroundStyle(Palette.ink)
  }
}
/// iOS 26 wraps toolbar items in a glass capsule that would not follow the badge's offset; hide it.
struct GoldToolbar: ToolbarContent {
  var body: some ToolbarContent {
    if #available(iOS 26.0, *) {
      ToolbarItem(placement: .topBarTrailing) { GoldBadge().offset(y: 8) }
        .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .topBarTrailing) { GoldBadge().offset(y: 8) }
    }
  }
}
struct DialogAction: Identifiable {
  let id = UUID()
  let title: String
  var role: ButtonRole? = nil
  var action: () -> Void = {}
}
struct DialogRequest: Identifiable {
  let id = UUID()
  let title: String
  let message: String?
  let actions: [DialogAction]
  let dismiss: () -> Void
}
/// Holds the one dialog currently shown; ContentView draws it above everything, nav bar included.
@MainActor @Observable final class DialogCenter {
  static let shared = DialogCenter()
  var current: DialogRequest?
}
struct GameDialogOverlay: View {
  let request: DialogRequest
  var body: some View {
    ZStack {
      Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { close(nil) }
      VStack(spacing: 14) {
        Text(verbatim: request.title).font(Palette.font(20)).multilineTextAlignment(.center)
        if let message = request.message {
          Text(verbatim: message).font(Palette.font(16)).multilineTextAlignment(.center)
        }
        ForEach(request.actions) { item in
          Button { close(item) } label: {
            Text(verbatim: item.title).font(Palette.font(18)).frame(
              maxWidth: .infinity, minHeight: 48
            ).background(
              item.role == .destructive
                ? Palette.purple : item.role == .cancel ? Palette.ivory : Palette.green,
              in: RoundedRectangle(cornerRadius: 14)
            ).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.ink, lineWidth: 2))
              .foregroundStyle(item.role == .destructive ? Color.white : Palette.ink)
          }.buttonStyle(.plain).haptic()
        }
      }.padding(20).frame(maxWidth: 360).background(
        Palette.paper, in: RoundedRectangle(cornerRadius: 20)
      ).overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.ink, lineWidth: 2)).padding(28)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }.foregroundStyle(Palette.ink)
  }
  private func close(_ item: DialogAction?) {
    request.dismiss()
    guard let item else { return }
    // Let the dialog finish fading out before navigating or presenting an error.
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      item.action()
    }
  }
}
extension View {
  /// Themed replacement for confirmationDialog/alert so the game font applies.
  func gameDialog(
    _ title: String, message: String? = nil, isPresented: Binding<Bool>,
    actions: [DialogAction]
  ) -> some View {
    onChange(of: isPresented.wrappedValue, initial: true) { _, shown in
      let center = DialogCenter.shared
      if shown {
        center.current = DialogRequest(
          title: title, message: message, actions: actions,
          dismiss: { isPresented.wrappedValue = false })
      } else {
        center.current = nil
      }
    }
  }
  func gameScreen(_ title: String) -> some View {
    self.frame(maxWidth: .infinity, maxHeight: .infinity).background(
      Palette.paper.ignoresSafeArea()
    )
    .navigationTitle(L(title)).navigationBarTitleDisplayMode(.inline)
    .toolbar { GoldToolbar() }
  }
  func panel() -> some View {
    self.padding(14).background(Palette.ivory, in: RoundedRectangle(cornerRadius: 16)).overlay(
      RoundedRectangle(cornerRadius: 16).stroke(Palette.ink.opacity(0.15), lineWidth: 1))
  }
}
struct ToolIcon: View {
  let tool: Tool
  var size: CGFloat = 64
  var body: some View {
    Image(tool.asset).resizable().interpolation(.none).scaledToFit().frame(
      width: size, height: size
    ).accessibilityHidden(true)
  }
}
struct ToolTile: View {
  let tool: Tool
  let count: Int
  var body: some View {
    VStack(spacing: 6) {
      ToolIcon(tool: tool)
      Text(verbatim: L(tool.key)).font(Palette.font(15)).multilineTextAlignment(.center)
      Text(verbatim: F("owned", count)).font(.caption).monospacedDigit()
    }.frame(maxWidth: .infinity).padding(.vertical, 12).background(
      Palette.ivory, in: RoundedRectangle(cornerRadius: 14))
  }
}
struct QuantityPicker: View {
  let tool: Tool
  @Binding var value: Int
  var maximum: Int = 999
  var body: some View {
    HStack(spacing: 0) {
      Button {
        value = max(0, value - 1)
      } label: {
        Image(systemName: "minus").frame(minWidth: 36, minHeight: 44)
      }.haptic().disabled(value == 0)
      Text(verbatim: "\(value)").font(.system(.subheadline, design: .monospaced)).frame(
        maxWidth: .infinity)
      Button {
        value = min(maximum, value + 1)
      } label: {
        Image(systemName: "plus").frame(minWidth: 36, minHeight: 44)
      }.haptic().disabled(value >= maximum)
    }.buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityLabel(
      L(tool.key) + " " + L("quantity"))
  }
}
/// Dark purple grade, vignette and flickering green noise laid over a haunted card's photo.
struct HauntedFilter: View {
  var animated: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let noiseGreen = Color(red: 0x6C / 255, green: 0xE4 / 255, blue: 0x11 / 255)
  var body: some View {
    ZStack {
      Color(red: 0.20, green: 0.04, blue: 0.38).opacity(0.50)
      RadialGradient(
        colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 40, endRadius: 260)
      if animated && !reduceMotion {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
          noise(seed: UInt64(context.date.timeIntervalSinceReferenceDate * 8.3))
        }
      } else {
        noise(seed: 7)
      }
    }.allowsHitTesting(false)
  }
  private func noise(seed: UInt64) -> some View {
    Canvas { context, size in
      var state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
      func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
      }
      let dot = max(2, size.width / 140)
      let count = Int(size.width * size.height / (dot * dot * 22))
      for _ in 0..<count {
        let rect = CGRect(x: next() * size.width, y: next() * size.height, width: dot, height: dot)
        context.fill(Path(rect), with: .color(Self.noiseGreen.opacity(0.10 + next() * 0.40)))
      }
      // a couple of thin glitch scanlines
      for _ in 0..<2 {
        let y = next() * size.height
        context.fill(
          Path(CGRect(x: 0, y: y, width: size.width, height: max(1, dot / 2))),
          with: .color(Self.noiseGreen.opacity(0.12)))
      }
    }
  }
}
/// Card border that slowly cycles between two colors with a soft glow. Static under Reduce Motion.
struct GlowingBorder: View {
  let from: Color
  let to: Color
  var glow: Color? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      let phase = (sin(t * 2 * .pi / 3.2) + 1) / 2
      let color = Self.mix(from, to, phase)
      RoundedRectangle(cornerRadius: 18).stroke(color, lineWidth: 4)
        .shadow(color: (glow ?? color).opacity(0.5 + 0.3 * phase), radius: 6 + 6 * phase)
    }
  }
  /// Mixes in HSB so purple → green passes through saturated blue/cyan instead of muddy gray.
  private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    var (ah, asat, abri, bh, bsat, bbri) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
    var alpha: CGFloat = 0
    UIColor(a).getHue(&ah, saturation: &asat, brightness: &abri, alpha: &alpha)
    UIColor(b).getHue(&bh, saturation: &bsat, brightness: &bbri, alpha: &alpha)
    let t = CGFloat(t)
    return Color(
      hue: ah + (bh - ah) * t, saturation: asat + (bsat - asat) * t,
      brightness: abri + (bbri - abri) * t)
  }
}
struct CardFace: View {
  let card: SpiritCard
  let photo: UIImage?
  var compact = false
  private var blessed: Bool { card.kind == .blessed }
  var body: some View {
    VStack(spacing: compact ? 8 : 12) {
      HStack(alignment: .top) {
        Text(verbatim: blessed ? (card.name ?? L("charm_name_placeholder")) : L(card.spiritKey))
          .font(Palette.font(compact ? 15 : 23)).frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(compact ? 2 : 3)
        if !blessed {
          Text(verbatim: F("tier", card.tier)).font(Palette.font(compact ? 11 : 14)).padding(5)
            .background(Palette.green, in: RoundedRectangle(cornerRadius: 5))
        }
      }
      ZStack {
        if let photo {
          // Square layout box first, so a wide or tall photo can never stretch the card.
          Color.clear.aspectRatio(1, contentMode: .fit).overlay(
            Image(uiImage: photo).resizable().scaledToFill())
        } else {
          Rectangle().fill(Palette.paper).overlay(
            Image(systemName: "photo").foregroundStyle(Palette.ink).animation(
              .easeInOut(duration: 0.35), value: card.kind))
        }
      }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipped().overlay {
        if !blessed { HauntedFilter(animated: !compact) }
      }.clipShape(RoundedRectangle(cornerRadius: 8))
      if blessed {
        HStack(spacing: 5) {
          Image("stat_holiness").resizable().interpolation(.none).scaledToFit().frame(
            width: compact ? 22 : 30, height: compact ? 22 : 30)
          Text(verbatim: F("holiness", card.holiness ?? 0)).font(Palette.font(compact ? 13 : 17))
        }
        if !compact {
          Text(verbatim: L(card.blessingKey ?? "")).font(Palette.font(17)).multilineTextAlignment(
            .center
          ).fixedSize(horizontal: false, vertical: true).frame(minHeight: 46)
        }
      } else if compact {
        Text(verbatim: L("requirements") + " · \(card.toolCount)").font(.caption)
      } else {
        HStack(spacing: 8) {
          ForEach(Tool.allCases.filter { card.requirements[$0, default: 0] > 0 }) { tool in
            VStack(spacing: 1) {
              ToolIcon(tool: tool, size: 32)
              Text(verbatim: "×\(card.requirements[tool,default:0])").font(
                .caption.monospacedDigit())
            }.frame(maxWidth: .infinity)
          }
        }
      }
      if !compact { Text(verbatim: L("app_name")).font(Palette.font(11)).opacity(0.6) }
    }.padding(compact ? 10 : 16).background(blessed ? Palette.ivory : Color(white: 0.95))
      .clipShape(RoundedRectangle(cornerRadius: 18)).overlay {
        if compact {
          RoundedRectangle(cornerRadius: 18).stroke(
            blessed ? Palette.gold : Palette.hauntedPurple, lineWidth: 4)
        } else if blessed {
          GlowingBorder(from: Palette.halo, to: Palette.gold, glow: Palette.gold)
        } else {
          GlowingBorder(from: Palette.hauntedPurple, to: Palette.hauntedGreen)
        }
      }
      .foregroundStyle(Palette.ink).animation(.easeInOut(duration: 0.35), value: card.kind)
  }
}
