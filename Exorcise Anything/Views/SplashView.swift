import SwiftUI

/// YCGS splash: studio logo → crossfade → YCGS logo. Each phase swaps background and logo together.
struct SplashView: View {
  @State private var showStudioLogo = true
  var body: some View {
    ZStack {
      // Opaque base so the main screen never shows through mid-crossfade.
      Color.skyStrong.ignoresSafeArea()
      if showStudioLogo {
        ZStack {
          Color.brandGradient.ignoresSafeArea()
          Image("StudioLogo").resizable().scaledToFit().frame(maxWidth: 260)
        }.transition(.opacity)
      } else {
        ZStack {
          Color.skyStrong.ignoresSafeArea()
          Image("YCGSLogo").resizable().scaledToFit().frame(maxWidth: 200)
        }.transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.6), value: showStudioLogo)
    .task {
      try? await Task.sleep(for: .milliseconds(700))
      showStudioLogo = false
    }
  }
}
