import AVFoundation
import Observation
import SwiftUI

/// All session configuration and capture operations run on this serial queue.
final class CameraHardware: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "exorcise.camera")
  private let output = AVCapturePhotoOutput()
  private var front = false
  private var completion: (@Sendable (Data?) -> Void)?
  func start(front: Bool = false, completion: @escaping @Sendable (Bool, Bool) -> Void) {
    queue.async { [self] in
      session.beginConfiguration()
      session.sessionPreset = .photo
      for input in session.inputs { session.removeInput(input) }
      guard
        let device = AVCaptureDevice.default(
          .builtInWideAngleCamera, for: .video, position: front ? .front : .back),
        let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
      else {
        session.commitConfiguration()
        completion(false, false)
        return
      }
      session.addInput(input)
      if session.outputs.isEmpty {
        guard session.canAddOutput(output) else {
          session.commitConfiguration()
          completion(false, false)
          return
        }
        session.addOutput(output)
      }
      if let connection = output.connection(with: .video) {
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = front }
      }
      self.front = front
      session.commitConfiguration()
      session.startRunning()
      completion(true, device.hasFlash)
    }
  }
  func stop() { queue.async { [self] in session.stopRunning() } }
  func capture(flash: Bool, completion: @escaping @Sendable (Data?) -> Void) {
    queue.async { [self] in
      guard session.isRunning, self.completion == nil else {
        completion(nil)
        return
      }
      self.completion = completion
      let settings = AVCapturePhotoSettings()
      if output.supportedFlashModes.contains(flash ? .on : .off) {
        settings.flashMode = flash ? .on : .off
      }
      output.capturePhoto(with: settings, delegate: self)
    }
  }
  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    let data = error == nil ? photo.fileDataRepresentation() : nil
    queue.async { [self] in
      let callback = completion
      completion = nil
      callback?(data)
    }
  }
}
@MainActor @Observable final class CameraModel {
  let hardware = CameraHardware()
  var ready = false
  var denied = false
  var unavailable = false
  var front = false
  var flash = false
  var hasFlash = false
  var capturing = false
  func start() async {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    let allowed =
      status == .authorized
      ? true : status == .notDetermined ? await AVCaptureDevice.requestAccess(for: .video) : false
    guard allowed else {
      denied = true
      return
    }
    configure()
  }
  func configure() {
    ready = false
    hardware.start(front: front) { [weak self] ready, flash in
      Task { @MainActor [weak self] in
        self?.ready = ready
        self?.hasFlash = flash
        self?.unavailable = !ready
      }
    }
  }
  func flip() {
    guard ready, !capturing else { return }
    front.toggle()
    flash = false
    configure()
  }
  func capture(_ callback: @escaping @MainActor (UIImage?) -> Void) {
    guard ready, !capturing else { return }
    capturing = true
    hardware.capture(flash: flash) { [weak self] data in
      Task { @MainActor [weak self] in
        self?.capturing = false
        callback(data.flatMap { UIImage(data: $0) })
      }
    }
  }
}
private final class CameraPreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  override func layoutSubviews() {
    super.layoutSubviews()
    if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
  }
}
struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  func makeUIView(context: Context) -> UIView {
    let view = CameraPreviewView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }
  func updateUIView(_ uiView: UIView, context: Context) {}
}
