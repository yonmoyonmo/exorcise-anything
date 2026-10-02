import SwiftUI

struct CropRequest: Identifiable {
  let id = UUID()
  let image: UIImage
}

/// Square crop for imported photos: drag and pinch the photo under a fixed square window.
struct CropScreen: View {
  let image: UIImage
  let onDone: (UIImage) -> Void
  let onCancel: () -> Void
  @State private var scale: CGFloat = 1  // points per image pixel
  @State private var baseScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var baseOffset: CGSize = .zero
  @State private var ready = false
  @State private var side: CGFloat = 300

  private var pixelSize: CGSize { CGSize(width: image.size.width, height: image.size.height) }
  private var minScale: CGFloat { side / min(pixelSize.width, pixelSize.height) }

  var body: some View {
    VStack(spacing: 16) {
      Text(verbatim: L("crop_hint")).font(Palette.font(17)).multilineTextAlignment(.center)
        .padding(.top, 24).padding(.horizontal, 20)
      GeometryReader { geo in
        let square = min(geo.size.width - 40, geo.size.height)
        ZStack {
          Color.black
          Image(uiImage: image).resizable().interpolation(.high)
            .frame(width: pixelSize.width * scale, height: pixelSize.height * scale)
            .offset(offset)
          Canvas { context, size in
            let hole = CGRect(
              x: (size.width - square) / 2, y: (size.height - square) / 2, width: square,
              height: square)
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(hole)
            context.fill(path, with: .color(.black.opacity(0.6)), style: FillStyle(eoFill: true))
            context.stroke(Path(hole), with: .color(Palette.green), lineWidth: 2)
          }.allowsHitTesting(false)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped().contentShape(Rectangle())
        .gesture(
          DragGesture().onChanged { value in
            offset = clamped(
              CGSize(
                width: baseOffset.width + value.translation.width,
                height: baseOffset.height + value.translation.height), scale: scale)
          }.onEnded { _ in baseOffset = offset }
            .simultaneously(
              with: MagnifyGesture().onChanged { value in
                scale = min(max(baseScale * value.magnification, minScale), minScale * 8)
                offset = clamped(offset, scale: scale)
              }.onEnded { _ in
                baseScale = scale
                baseOffset = offset
              })
        )
        .onAppear { setUp(square) }
        .onChange(of: square) { _, new in setUp(new) }
      }
      VStack(spacing: 10) {
        GameButton(key: "ok", symbol: "checkmark") { onDone(cropped()) }.haptic()
        GameButton(key: "cancel", color: Palette.ivory) { onCancel() }
      }.padding(.horizontal, 20).padding(.bottom, 16)
    }.background(Palette.paper.ignoresSafeArea()).foregroundStyle(Palette.ink)
  }

  private func setUp(_ square: CGFloat) {
    side = square
    scale = max(scale, square / min(pixelSize.width, pixelSize.height))
    if !ready {
      scale = square / min(pixelSize.width, pixelSize.height)
      ready = true
    }
    baseScale = scale
    offset = clamped(offset, scale: scale)
    baseOffset = offset
  }

  /// Keeps the photo covering the whole crop window.
  private func clamped(_ value: CGSize, scale: CGFloat) -> CGSize {
    let maxX = max(0, (pixelSize.width * scale - side) / 2)
    let maxY = max(0, (pixelSize.height * scale - side) / 2)
    return CGSize(
      width: min(max(value.width, -maxX), maxX), height: min(max(value.height, -maxY), maxY))
  }

  private func cropped() -> UIImage {
    let edge = side / scale
    let originX = (pixelSize.width - edge) / 2 - offset.width / scale
    let originY = (pixelSize.height - edge) / 2 - offset.height / scale
    let rect = CGRect(x: originX, y: originY, width: edge, height: edge).integral
      .intersection(CGRect(origin: .zero, size: pixelSize))
    guard let cg = image.cgImage?.cropping(to: rect) else { return image }
    return UIImage(cgImage: cg, scale: 1, orientation: .up)
  }
}

extension UIImage {
  /// Redraws upright (bakes in EXIF orientation) and caps the long edge so cropping stays light.
  func normalized(maxEdge: CGFloat = 2400) -> UIImage {
    let factor = min(1, maxEdge / max(size.width, size.height))
    let target = CGSize(width: size.width * factor, height: size.height * factor)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
