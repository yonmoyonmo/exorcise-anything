import SwiftUI

@main
struct Exorcise_AnythingApp: App {
  var body: some Scene { WindowGroup { BootstrapView().preferredColorScheme(.light) } }
}
struct BootstrapView: View {
  @State private var store: GameStore?
  @State private var error: String?
  @State private var showSplash = true
  var body: some View {
    ZStack {
      content
      if showSplash { SplashView().transition(.opacity) }
    }.task {
      try? await Task.sleep(for: .milliseconds(1800))
      withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
    }
  }
  private var content: some View {
    Group {
      if let store {
        ContentView().environment(store)
      } else if let error {
        VStack(spacing: 20) {
          Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
          Text(verbatim: L("boot_error"))
          Text(verbatim: error)
          GameButton(key: "retry", action: load)
        }.padding(24)
      } else {
        ProgressView()
      }
    }.tint(Palette.purple).foregroundStyle(Palette.ink).task { if store == nil { load() } }
  }
  private func load() {
    do {
      let loaded = try GameStore()
      store = loaded
      error = nil
    } catch { self.error = (error as? GameError)?.errorDescription ?? L("error_storage") }
  }
}
