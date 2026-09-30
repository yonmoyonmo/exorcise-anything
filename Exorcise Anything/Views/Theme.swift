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
  static let ivory = Color(red: 1, green: 0.99, blue: 0.97)
  static func font(_ size: CGFloat) -> Font {
    .custom(
      Locale.preferredLanguages.first?.hasPrefix("ja") == true
        ? "PixelMplus12-Regular" : "Sam3KRFont", size: size, relativeTo: .body)
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
    }.buttonStyle(.plain).foregroundStyle(Palette.ink)
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
          }.buttonStyle(.plain)
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
      }.disabled(value == 0)
      Text(verbatim: "\(value)").font(.system(.subheadline, design: .monospaced)).frame(
        maxWidth: .infinity)
      Button {
        value = min(maximum, value + 1)
      } label: {
        Image(systemName: "plus").frame(minWidth: 36, minHeight: 44)
      }.disabled(value >= maximum)
    }.buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityLabel(
      L(tool.key) + " " + L("quantity"))
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
          Image(uiImage: photo).resizable().scaledToFill()
        } else {
          Rectangle().fill(Palette.paper).overlay(
            Image(systemName: "photo").foregroundStyle(Palette.ink).animation(
              .easeInOut(duration: 0.35), value: card.kind))
        }
      }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipped().overlay(
        blessed ? Color.clear : Palette.purple.opacity(0.28)
      ).clipShape(RoundedRectangle(cornerRadius: 8))
      if blessed {
        HStack(spacing: 5) {
          Image("stat_holiness").resizable().scaledToFit().frame(
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
      .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(
        RoundedRectangle(cornerRadius: 18).stroke(
          blessed ? Palette.gold : Palette.purple, lineWidth: 4)
      )
      .foregroundStyle(Palette.ink).animation(.easeInOut(duration: 0.35), value: card.kind)
  }
}
