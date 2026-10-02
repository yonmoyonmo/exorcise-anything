import PhotosUI
import SwiftUI

enum Route: Hashable {
  case camera
  case card(UUID)
  case exorcism(UUID)
  case album, bag
  case shop(UUID?)
  case work
}
@MainActor @Observable final class NavigationState {
  var path: [Route] = []
  var albumKind: CardKind = .haunted
  var importedIDs: Set<UUID> = []
  func album(_ kind: CardKind) {
    albumKind = kind
    path = [.album]
  }
  func captured(_ id: UUID) {
    if path.last == .camera { path.removeLast() }
    path.append(.card(id))
  }
  func imported(_ id: UUID) {
    importedIDs.insert(id)
    path.append(.card(id))
  }
  /// After discarding an uncollected result: camera captures return to the camera, imports to home.
  func discarded(_ id: UUID) {
    path.removeLast()
    if importedIDs.remove(id) == nil { path.append(.camera) }
  }
}
struct ContentView: View {
  @Environment(GameStore.self) private var store
  @State private var nav = NavigationState()
  var body: some View {
    @Bindable var nav = nav
    @Bindable var store = store
    NavigationStack(path: $nav.path) {
      HomeView().navigationDestination(for: Route.self) { route in
        switch route {
        case .camera: CameraScreen()
        case .card(let id): CardDetailScreen(id: id)
        case .exorcism(let id): ExorcismScreen(id: id)
        case .album: AlbumScreen()
        case .bag: BagScreen()
        case .shop(let id): ShopScreen(cardID: id)
        case .work: WorkScreen()
        }
      }
    }.environment(nav).font(Palette.font(17))
      .gameDialog(
        L("error_title"), message: store.errorMessage,
        isPresented: Binding(
          get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }),
        actions: [DialogAction(title: L("ok"), role: .cancel)])
      .overlay {
        if let request = DialogCenter.shared.current { GameDialogOverlay(request: request) }
      }.animation(.easeOut(duration: 0.2), value: DialogCenter.shared.current?.id)
      .overlay(alignment: .top) {
        if let toast = store.toast {
          Text(verbatim: toast).font(Palette.font(16)).padding(14).background(
            Palette.gold, in: Capsule()
          ).shadow(radius: 6).padding(.top, 54).allowsHitTesting(false).task(id: toast) {
            try? await Task.sleep(for: .seconds(2))
            if store.toast == toast { store.toast = nil }
          }
        }
      }
  }
}
struct HomeView: View {
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var importing = false
  @State private var cropRequest: CropRequest?
  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.height < 700
      ScrollView {
        VStack(spacing: compact ? 16 : 24) {
          Spacer(minLength: compact ? 0 : 25)
          Button {
            nav.path.append(.camera)
          } label: {
            VStack(spacing: compact ? 16 : 25) {
              Image(systemName: "camera.viewfinder").font(
                .system(size: compact ? 64 : 84, weight: .light))
              Text(verbatim: L("capture")).font(Palette.font(30))
              Text(verbatim: L("home_tagline")).font(Palette.font(16)).multilineTextAlignment(
                .center)
            }.frame(maxWidth: .infinity).padding(.vertical, compact ? 30 : 55).padding(
              .horizontal, 20
            ).background(
              Palette.purple, in: RoundedRectangle(cornerRadius: 28)
            ).foregroundStyle(.white).overlay(alignment: .topTrailing) {
              Image(systemName: "sparkle").font(.system(size: 36)).foregroundStyle(Palette.green)
                .padding(20)
            }
          }.buttonStyle(.plain).haptic()
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            menu("album", "rectangle.stack", .album)
            menu("bag", "shippingbox", .bag)
          }
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            menu("shop", "storefront", .shop(nil))
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
              menuLabel("import_photo", "photo.on.rectangle")
            }.buttonStyle(.plain).haptic().disabled(importing)
          }
          if let draft = store.drafts.first {
            GameButton(key: "resume_capture", color: Palette.ivory) {
              nav.path.append(.card(draft.id))
            }
          }
        }.padding(20)
      }
    }.gameScreen("").onChange(of: pickedPhoto) { _, item in
      guard let item else { return }
      pickedPhoto = nil
      importing = true
      Task {
        defer { importing = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
          let image = UIImage(data: data)
        else { return store.toast = L("import_photo_failed") }
        cropRequest = CropRequest(image: image.normalized())
      }
    }.fullScreenCover(item: $cropRequest) { request in
      CropScreen(
        image: request.image,
        onDone: { cropped in
          cropRequest = nil
          do { nav.imported(try store.capture(cropped)) } catch { store.report(error) }
        }, onCancel: { cropRequest = nil })
    }
  }
  private func menu(_ key: String, _ icon: String, _ route: Route) -> some View {
    Button {
      nav.path.append(route)
    } label: {
      menuLabel(key, icon)
    }.buttonStyle(.plain).haptic()
  }
  private func menuLabel(_ key: String, _ icon: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: icon).font(.system(size: 28))
      Text(verbatim: L(key))
    }.frame(maxWidth: .infinity, minHeight: 106).background(
      Palette.ivory, in: RoundedRectangle(cornerRadius: 18))
  }
}
