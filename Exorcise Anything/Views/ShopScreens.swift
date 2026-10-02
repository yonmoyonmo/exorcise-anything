import SwiftUI

struct BagScreen: View {
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
          ForEach(Tool.allCases) { tool in ToolTile(tool: tool, count: store.count(tool)) }
        }
        GameButton(key: "buy_tools", symbol: "basket") { nav.path.append(.shop(nil)) }
      }.padding(20)
    }.gameScreen("bag")
  }
}
struct ShopScene: View {
  var customer: Int? = nil
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .bottom) {
        // The 2:3 background is cropped to a wide strip; show the wall (upper part), not just floor.
        let artHeight = geo.size.width * 1.5
        Image("shop_background").resizable().interpolation(.none)
          .frame(width: geo.size.width, height: artHeight)
          .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
          .offset(y: -min(0.26 * artHeight, max(0, artHeight - geo.size.height)))
        Image(customer.map { String(format: "customer_%02d", $0) } ?? "shop_owner").resizable().interpolation(.none)
          .scaledToFit().frame(height: geo.size.height * 0.95).offset(y: customer == nil ? 20 : 25)
        if customer != nil {
          Image("work_counter").resizable().interpolation(.none).scaledToFill().frame(height: geo.size.height * 0.23)
            .clipped()
        }
      }.frame(width: geo.size.width, height: geo.size.height).clipped().clipShape(
        RoundedRectangle(cornerRadius: 18))
    }
  }
}
private enum ShopTab: String, CaseIterable {
  case buy = "shop_buy_tab"
  case sell = "shop_sell_tab"
}
struct ShopScreen: View {
  var cardID: UUID?
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  @State private var tab: ShopTab = .buy
  @State private var quantities: [Tool: Int] = [:]
  @State private var initialized = false
  @State private var selectedID: UUID?
  @State private var saleConfirmation: SpiritCard?
  var cost: Int { quantities.values.reduce(0, +) * Tool.price }
  private var charms: [SpiritCard] {
    store.state.cards.filter { $0.salePrice != nil }.sorted { $0.createdAt > $1.createdAt }
  }
  private var selected: SpiritCard? { selectedID.flatMap { store.card($0) } }
  var body: some View {
    VStack(spacing: 0) {
      Picker(L("shop"), selection: $tab) {
        ForEach(ShopTab.allCases, id: \.self) { Text(verbatim: L($0.rawValue)).tag($0) }
      }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 8).sensoryFeedback(.selection, trigger: tab)
      ScrollView {
        VStack(spacing: 16) {
          ShopScene().frame(height: 155)
          if tab == .buy { purchaseControls } else { saleControls }
          GameButton(key: "work", color: Palette.ivory) { nav.path.append(.work) }

        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
      }
    }.gameScreen("shop")
      .onAppear {
        if !initialized {
          initialized = true
          if let cardID, let card = store.card(cardID) {
            for tool in Tool.allCases {
              quantities[tool] = max(0, card.requirements[tool, default: 0] - store.count(tool))
            }
          }
        }
      }
      .gameDialog(
        L("sale_confirm_title"),
        message: saleConfirmation.map {
          F("sale_confirm_message", $0.name ?? L("charm_name_placeholder"), $0.salePrice ?? 0)
        },
        isPresented: Binding(
          get: { saleConfirmation != nil }, set: { if !$0 { saleConfirmation = nil } }),
        actions: saleConfirmation.map { card in
          [
            DialogAction(title: F("sale_action", card.salePrice ?? 0)) { sell(card) },
            DialogAction(title: L("cancel"), role: .cancel),
          ]
        } ?? []
      )
  }
  private var purchaseControls: some View {
    VStack(spacing: 16) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12
      ) {
        ForEach(Tool.allCases) { tool in
          VStack(spacing: 4) {
            ToolIcon(tool: tool, size: 58)
            Text(verbatim: L(tool.key)).font(Palette.font(14)).multilineTextAlignment(.center)
            Text(verbatim: L("price")).font(.caption)
            if let id = cardID, let card = store.card(id),
              card.requirements[tool, default: 0] > store.count(tool)
            {
              Text(
                verbatim: F("missing", card.requirements[tool, default: 0] - store.count(tool))
              ).font(.caption2).foregroundStyle(Palette.purple)
            }
            QuantityPicker(
              tool: tool,
              value: Binding(
                get: { quantities[tool, default: 0] }, set: { quantities[tool] = $0 }))
          }.padding(.top, 10).background(Palette.ivory, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      Text(verbatim: F("total", cost)).font(Palette.font(22))
      if cost > store.gold {
        Text(verbatim: L("error_gold")).font(.callout).foregroundStyle(Palette.purple)
      }
      GameButton(key: "buy", symbol: "basket") {
        if store.perform({ try store.purchase(quantities) }) {
          quantities = [:]
          store.toast = L("purchased")
        }
      }.disabled(cost == 0 || cost > store.gold)

    }
  }
  private var saleControls: some View {
    VStack(spacing: 16) {
      VStack(spacing: 8) {
        Text(verbatim: L("charm_buyer_line")).font(Palette.font(17))
        Text(verbatim: L("sale_price_rule")).font(.caption).foregroundStyle(.secondary)
      }.multilineTextAlignment(.center).frame(maxWidth: .infinity).panel()
      if charms.isEmpty {
        ContentUnavailableView(
          L("sale_empty"), systemImage: "sparkles.rectangle.stack",
          description: Text(verbatim: L("sale_empty_hint")))
        GameButton(key: "capture", symbol: "camera", color: Palette.gold) {
          nav.path.append(.camera)
        }

      } else {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
          ForEach(charms) { card in
            Button {
              selectedID = selectedID == card.id ? nil : card.id
            } label: {
              VStack(spacing: 10) {
                CardFace(card: card, photo: store.image(card), compact: true)
                  .overlay(alignment: .topTrailing) {
                    if selectedID == card.id {
                      Image(systemName: "checkmark.circle.fill").font(.title)
                        .foregroundStyle(Palette.green).background(Palette.ink, in: Circle())
                        .padding(8)
                    }
                  }
                Text(verbatim: F("sale_quote", card.salePrice ?? 0)).font(Palette.font(17))
              }
            }.buttonStyle(.plain).haptic()
              .accessibilityAddTraits(selectedID == card.id ? .isSelected : [])
          }
        }
        Text(verbatim: L("sale_warning")).font(.callout).multilineTextAlignment(.center)
        if let selected, let price = selected.salePrice {
          Text(verbatim: F("sale_selected", selected.name ?? L("charm_name_placeholder"), price))
            .font(Palette.font(17)).multilineTextAlignment(.center)
        }
        GameButton(key: "sell_charm", symbol: "sparkles", color: Palette.gold) {
          saleConfirmation = selected
        }.disabled(selected?.salePrice == nil)
        if selected?.salePrice == nil { Text(verbatim: L("sale_select_hint")).font(.caption) }
      }
    }
  }
  private func sell(_ card: SpiritCard) {
    do {
      let paid = try store.sellCharm(card.id)
      selectedID = nil
      saleConfirmation = nil
      store.toast = F("sale_completed", paid)
    } catch {
      saleConfirmation = nil
      store.report(error)
    }
  }
}
struct WorkScreen: View {
  @Environment(GameStore.self) var store
  @Environment(\.dismiss) var dismiss
  @State private var requested = Tool.allCases.randomElement()!
  @State private var customer = Int.random(in: 1...4)
  @State private var order = UUID()
  @State private var feedback: String?
  @State private var serving = false
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text(verbatim: F("work_order", L(requested.key))).font(Palette.font(22))
          .multilineTextAlignment(.center).frame(maxWidth: .infinity).panel()
        ShopScene(customer: customer).frame(height: 230)
        Text(verbatim: L(feedback ?? "work_hint")).font(Palette.font(15)).frame(minHeight: 22)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
          ForEach(Tool.allCases) { tool in
            Button {
              serve(tool)
            } label: {
              VStack(spacing: 4) {
                ToolIcon(tool: tool, size: 56)
                Text(verbatim: L(tool.key)).font(Palette.font(14))
              }.frame(maxWidth: .infinity).padding(.vertical, 8).background(
                Palette.ivory, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).haptic().disabled(serving)
          }
        }
        GameButton(key: "exit_work", color: Palette.ivory) { dismiss() }
      }.padding(20)
    }.gameScreen("work_title")
  }
  private func serve(_ tool: Tool) {
    do {
      if try store.serve(order: order, requested: requested, supplied: tool) {
        feedback = "work_right"
        serving = true
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(500))
          order = UUID()
          requested = Tool.allCases.randomElement()!
          customer = Int.random(in: 1...4)
          serving = false
          feedback = nil
        }
      } else {
        feedback = "work_wrong"
      }
    } catch { store.report(error) }
  }
}
