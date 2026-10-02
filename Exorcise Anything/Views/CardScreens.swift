import Photos
import SwiftUI

struct CardDetailScreen: View {
  let id: UUID
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  @Environment(\.dismiss) var dismiss
  @State private var name = ""
  @State private var leaving = false
  @State private var deleting = false
  @State private var exporting = false
  @FocusState private var naming: Bool
  var body: some View {
    Group {
      if let card = store.card(id) {
        ScrollView {
          VStack(spacing: 18) {
            CardFace(card: card, photo: store.image(card)).padding(.top, 6)
            if card.kind == .haunted { hauntedControls(card) } else { blessedControls(card) }
          }.padding(20).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
        .gameScreen(card.kind == .blessed ? "blessed" : card.collected ? "haunted" : "")
        .navigationBarBackButtonHidden(!card.collected || card.kind == .blessed)
        .toolbar {
          if !card.collected || card.kind == .blessed {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                if card.kind == .blessed { backToCharms() } else { leaving = true }
              } label: {
                Label(L("back"), systemImage: "chevron.left")
              }.haptic()
            }
          }
        }
        .gameDialog(
          L("leave_title"), message: L("leave_message"), isPresented: $leaving,
          actions: [
            DialogAction(title: L("collect")) {
              if store.perform({ try store.collect(id) }) { dismiss() }
            },
            DialogAction(title: L("delete"), role: .destructive) {
              if store.perform({ try store.delete(id) }) { nav.discarded(id) }
            },
            DialogAction(title: L("cancel"), role: .cancel),
          ]
        )
        .gameDialog(
          L("delete_title"), message: L("delete_message"), isPresented: $deleting,
          actions: [
            DialogAction(title: L("delete"), role: .destructive) {
              if store.perform({ try store.delete(id) }) {
                if card.collected { nav.album(card.kind) } else { nav.discarded(id) }
              }
            },
            DialogAction(title: L("cancel"), role: .cancel),
          ]
        )
        .onAppear { name = card.name ?? "" }
      } else {
        ContentUnavailableView(L("error_card_missing"), systemImage: "rectangle.slash").gameScreen(
          "album")
      }
    }
  }
  private func hauntedControls(_ card: SpiritCard) -> some View {
    let sufficient = card.requirements.allSatisfy { store.count($0.key) >= $0.value }
    return VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(verbatim: L("requirements")).font(Palette.font(18))
        ForEach(Tool.allCases.filter { card.requirements[$0, default: 0] > 0 }) { tool in
          HStack {
            ToolIcon(tool: tool, size: 30)
            Text(verbatim: L(tool.key)).font(Palette.font(15))
            Spacer()
            Text(
              verbatim: F("needed_owned", card.requirements[tool, default: 0], store.count(tool))
            ).font(.caption).foregroundStyle(
              store.count(tool) < card.requirements[tool, default: 0] ? Palette.purple : Palette.ink
            )
          }
        }
      }.panel()
      HStack {
        Text(verbatim: F("reward", card.reward))
        Spacer()
        Text(verbatim: F("taps", card.tapGoal))
      }.font(Palette.font(15))
      GameButton(
        key: sufficient ? (card.collected ? "exorcise" : "exorcise_now") : "buy_tools",
        symbol: sufficient ? "sparkles" : "basket"
      ) { nav.path.append(sufficient ? .exorcism(id) : .shop(id)) }
      if !card.collected {
        GameButton(key: "collect", color: Palette.ivory) {
          if store.perform({ try store.collect(id) }) { nav.album(.haunted) }
        }
      }
      if card.collected {
        GameButton(key: "save_image", symbol: "square.and.arrow.down", color: Palette.ivory) {
          save(card)
        }.disabled(exporting)
      }
      Button(L("discard"), role: .destructive) { deleting = true }.padding(10).haptic()
    }
  }
  private func blessedControls(_ card: SpiritCard) -> some View {
    VStack(spacing: 14) {
      HStack {
        TextField(L("charm_name_placeholder"), text: $name).focused($naming).textFieldStyle(
          .roundedBorder
        ).submitLabel(.done).onSubmit { saveName() }
        Button(L("rename")) { saveName() }.font(.callout).haptic()
      }
      Text(verbatim: L("name_hint")).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
      GameButton(key: "save_image", symbol: "square.and.arrow.down", color: Palette.gold) {
        save(card)
      }.disabled(exporting)
      HStack {
        GameButton(key: "album", color: Palette.ivory) { nav.album(.blessed) }
        GameButton(key: "retake", color: Palette.ivory) { nav.path = [.camera] }
      }
      Button(L("release"), role: .destructive) { deleting = true }.padding(10).haptic()
    }
  }
  private func backToCharms() {
    nav.albumKind = .blessed
    if nav.path.dropLast().last == .album { dismiss() } else { nav.album(.blessed) }
  }
  private func saveName() {
    if store.perform({ try store.rename(id, to: name) }) {
      naming = false
      name = store.card(id)?.name ?? ""
    }
  }
  private func save(_ card: SpiritCard) {
    guard !exporting else { return }
    exporting = true
    Task { @MainActor in
      defer { exporting = false }
      let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      guard status == .authorized || status == .limited else {
        store.errorMessage = L("photo_permission")
        return
      }
      let renderer = ImageRenderer(
        content: CardFace(card: card, photo: store.image(card)).frame(width: 340).padding(12)
          .background(Palette.paper))
      renderer.scale = 3
      guard let image = renderer.uiImage else {
        store.report(GameError.photo)
        return
      }
      do {
        try await PHPhotoLibrary.shared().performChanges {
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        store.toast = L("saved_image")
      } catch { store.report(GameError.photo) }
    }
  }
}
struct ExorcismScreen: View {
  let id: UUID
  @Environment(GameStore.self) var store
  @Environment(\.dismiss) var dismiss
  @State private var taps = 0
  @State private var finished = false
  @State private var bounce = false
  var body: some View {
    Group {
      if let card = store.card(id) {
        ScrollView {
          VStack(spacing: 18) {
            Button {
              tap(card)
            } label: {
              CardFace(card: card, photo: store.image(card)).scaleEffect(bounce ? 0.975 : 1)
                .rotationEffect(.degrees(bounce ? (taps.isMultiple(of: 2) ? 1 : -1) : 0))
            }.buttonStyle(.plain).padding(.top, 6).disabled(finished).accessibilityLabel(
              L("exorcism_hint"))
            ProgressView(value: Double(taps), total: Double(card.tapGoal)).tint(Palette.purple)
            Text(verbatim: finished ? L("completed") : F("remaining", max(0, card.tapGoal - taps)))
              .font(Palette.font(22))
            Text(verbatim: L("exorcism_hint"))
            Text(verbatim: L("exorcism_cost")).font(.callout).foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }.padding(20).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }.gameScreen("exorcism")
      } else {
        ContentUnavailableView(L("error_card_missing"), systemImage: "rectangle.slash")
      }
    }
  }
  private func tap(_ card: SpiritCard) {
    guard !finished, card.kind == .haunted else { return }
    taps = min(taps + 1, card.tapGoal)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    withAnimation(.easeOut(duration: 0.09)) { bounce = true }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(95))
      withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bounce = false }
    }
    if taps == card.tapGoal {
      do {
        let reward = try store.exorcise(id)
        finished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.toast = L("completed") + " +\(reward) G"
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(700))
          dismiss()
        }
      } catch {
        taps = 0
        store.report(error)
      }
    }
  }
}
struct AlbumScreen: View {
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  var body: some View {
    @Bindable var nav = nav
    let cards = store.state.cards.filter { $0.collected && $0.kind == nav.albumKind }.sorted {
      $0.createdAt > $1.createdAt
    }
    VStack(spacing: 12) {
      Picker(L("album"), selection: $nav.albumKind) {
        ForEach([CardKind.haunted, .blessed], id: \.self) { kind in
          Text(
            verbatim: L(kind.rawValue)
              + " \(store.state.cards.filter{$0.collected && $0.kind==kind}.count)"
          ).tag(kind)
        }
      }.pickerStyle(.segmented).padding(.horizontal, 20).sensoryFeedback(.selection, trigger: nav.albumKind)
      ScrollView {
        if cards.isEmpty {
          ContentUnavailableView(
            L("empty_album"), systemImage: "rectangle.stack",
            description: Text(verbatim: L("empty_hint"))
          ).padding(.top, 60)
        } else {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
            ForEach(cards) { card in
              Button {
                nav.path.append(.card(card.id))
              } label: {
                CardFace(card: card, photo: store.image(card), compact: true)
              }.buttonStyle(.plain).haptic()
            }
          }.padding(20)
        }
      }
    }.gameScreen("album")
  }
}
