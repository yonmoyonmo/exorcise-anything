import SwiftUI

struct CameraScreen: View {
  @Environment(GameStore.self) var store
  @Environment(NavigationState.self) var nav
  @Environment(\.scenePhase) var phase
  @State private var model = CameraModel()
  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        Color.black
        if model.ready {
          CameraPreview(session: model.hardware.session)
          RoundedRectangle(cornerRadius: 18).stroke(
            Palette.green, style: StrokeStyle(lineWidth: 2, dash: [18, 8])
          ).padding(28).allowsHitTesting(false)
          VStack {
            Text(verbatim: L("camera_guide")).font(Palette.font(17)).padding(12).background(
              .black.opacity(0.55), in: Capsule())
            Spacer()
          }.padding(.top, 40).foregroundStyle(.white)
        } else if model.denied || model.unavailable {
          VStack(spacing: 20) {
            Image(systemName: "camera.fill").font(.system(size: 40))
            Text(verbatim: L(model.denied ? "camera_permission" : "camera_unavailable"))
              .multilineTextAlignment(.center)
            if model.denied {
              Button(L("settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                  UIApplication.shared.open(url)
                }
              }.haptic()
            }
          }.foregroundStyle(.white).padding(30)
        } else {
          ProgressView().tint(.white)
        }
      }.clipShape(RoundedRectangle(cornerRadius: 24)).frame(minHeight: 300, maxHeight: .infinity)
      HStack {
        Button {
          model.flip()
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(
            width: 60, height: 60)
        }.haptic().accessibilityLabel(L("flip_camera")).disabled(!model.ready || model.capturing)
        Spacer()
        Button {
          model.capture { image in
            if let image { captured(image) } else { store.report(GameError.photo) }
          }
        } label: {
          Circle().fill(.white).frame(width: 72, height: 72).padding(5).overlay(
            Circle().stroke(Palette.purple, lineWidth: 4))
        }.haptic(.medium).accessibilityLabel(L("shutter")).disabled(
          !model.ready || model.capturing)
        Spacer()
        Button {
          model.flash.toggle()
        } label: {
          Image(systemName: model.flash ? "bolt.fill" : "bolt.slash").font(.title2).frame(
            width: 60, height: 60)
        }.haptic().accessibilityLabel(L("flash")).accessibilityValue(
          L(model.flash ? "flash_on" : "flash_off")
        ).disabled(!model.hasFlash || model.capturing)
      }
      #if targetEnvironment(simulator)
        GameButton(key: "simulator_sample", color: Palette.ivory) {
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1
          let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800), format: format)
            .image { context in
              UIColor(red: 0.91, green: 0.86, blue: 0.96, alpha: 1).setFill()
              context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
              UIImage(named: "tool_fist")?.draw(in: CGRect(x: 100, y: 100, width: 600, height: 600))
            }
          captured(image)
        }
      #endif
    }.padding(20).gameScreen("").task { await model.start() }.onDisappear {
      model.hardware.stop()
    }.onChange(of: phase) { _, phase in
      if phase == .active { Task { await model.start() } } else { model.hardware.stop() }
    }
  }
  private func captured(_ image: UIImage) {
    do {
      let id = try store.capture(image)
      model.hardware.stop()
      nav.captured(id)
    } catch { store.report(error) }
  }
}
