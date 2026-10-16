import AVFoundation
import Flutter
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class NativeCapture: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private var imageContinuation: CheckedContinuation<PlatformCapturedImage?, Error>?
  private var captureInProgress = false

  func scanBarcode() async throws -> String? {
    try beginCapture()
    try await ensureCameraPermission()
    let scanner = BarcodeScannerViewController()
    return try await withCheckedThrowingContinuation { continuation in
      scanner.onFinish = { [weak self] value in
        self?.captureInProgress = false
        continuation.resume(returning: value)
      }
      guard let presenter = Self.topViewController() else {
        captureInProgress = false
        continuation.resume(throwing: PigeonError(code: "capture_unavailable", message: "Camera presentation is unavailable.", details: nil))
        return
      }
      presenter.present(scanner, animated: true)
    }
  }

  func capturePhoto() async throws -> PlatformCapturedImage? {
    try beginCapture()
    try await ensureCameraPermission()
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      captureInProgress = false
      throw PigeonError(code: "camera_unavailable", message: "A camera is not available on this device.", details: nil)
    }
    guard let presenter = Self.topViewController() else {
      captureInProgress = false
      throw PigeonError(code: "capture_unavailable", message: "Camera presentation is unavailable.", details: nil)
    }
    return try await withCheckedThrowingContinuation { continuation in
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.cameraCaptureMode = .photo
      picker.allowsEditing = false
      picker.delegate = self
      imageContinuation = continuation
      presenter.present(picker, animated: true)
    }
  }

  func chooseImage() async throws -> PlatformCapturedImage? {
    try beginCapture()
    guard let presenter = Self.topViewController() else {
      captureInProgress = false
      throw PigeonError(code: "capture_unavailable", message: "Photo selection is unavailable.", details: nil)
    }
    return try await withCheckedThrowingContinuation { continuation in
      var configuration = PHPickerConfiguration(photoLibrary: .shared())
      configuration.filter = .images
      configuration.selectionLimit = 1
      configuration.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      imageContinuation = continuation
      presenter.present(picker, animated: true)
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let result = results.first else {
      finishImage(.success(nil))
      return
    }
    let provider = result.itemProvider
    let typeIdentifier = provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
      Task { @MainActor in
        if let error {
          self?.finishImage(.failure(error))
        } else if let data {
          self?.finishImage(Self.normalizedImage(data: data))
        } else {
          let mimeType = UTType(typeIdentifier)?.preferredMIMEType ?? "application/octet-stream"
          self?.finishImage(.failure(PigeonError(code: "unsupported_image", message: "The selected item is not a supported image (\(mimeType)).", details: nil)))
        }
      }
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    finishImage(.success(nil))
  }

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    guard let image = info[.originalImage] as? UIImage else {
      finishImage(.failure(PigeonError(code: "capture_failed", message: "The captured photo could not be read.", details: nil)))
      return
    }
    guard let data = image.jpegData(compressionQuality: 0.95) else {
      finishImage(.failure(PigeonError(code: "capture_failed", message: "The captured photo could not be encoded.", details: nil)))
      return
    }
    finishImage(Self.normalizedImage(data: data))
  }

  private func finishImage(_ result: Result<PlatformCapturedImage?, Error>) {
    guard let continuation = imageContinuation else { return }
    imageContinuation = nil
    captureInProgress = false
    continuation.resume(with: result)
  }

  private func beginCapture() throws {
    guard !captureInProgress else {
      throw PigeonError(code: "capture_in_progress", message: "Another capture flow is already active.", details: nil)
    }
    captureInProgress = true
  }

  private func ensureCameraPermission() async throws {
    do {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        return
      case .notDetermined:
        guard await AVCaptureDevice.requestAccess(for: .video) else {
          throw PigeonError(code: "camera_permission_denied", message: "Camera access was denied. Manual entry remains available.", details: nil)
        }
      case .denied, .restricted:
        throw PigeonError(code: "camera_permission_denied", message: "Camera access is unavailable. Manual entry remains available.", details: nil)
      @unknown default:
        throw PigeonError(code: "camera_permission_unavailable", message: "Camera permission status is unknown.", details: nil)
      }
    } catch {
      captureInProgress = false
      throw error
    }
  }

  private static func normalizedImage(data: Data) -> Result<PlatformCapturedImage?, Error> {
    let maximumBytes = 8 * 1024 * 1024
    let maximumDimension = 4096
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
      let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
      sourceWidth > 0,
      sourceHeight > 0
    else {
      return .failure(PigeonError(code: "unsupported_image", message: "The selected image could not be decoded.", details: nil))
    }
    let sourcePixelCount = Double(sourceWidth) * Double(sourceHeight)
    let sourceLongestSide = Double(max(sourceWidth, sourceHeight))
    let dimensionForPixelLimit = sourcePixelCount > 16_000_000
      ? Int(sourceLongestSide * (sqrt(16_000_000 / sourcePixelCount)))
      : maximumDimension
    var dimension = min(maximumDimension, max(1, dimensionForPixelLimit))
    for _ in 0..<5 {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: dimension,
        kCGImageSourceShouldCacheImmediately: false,
      ]
      guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return .failure(PigeonError(code: "unsupported_image", message: "The selected image could not be decoded.", details: nil))
      }
      let normalized = UIImage(cgImage: thumbnail)
      for quality: CGFloat in [0.82, 0.76, 0.68] {
        if let encoded = normalized.jpegData(compressionQuality: quality), encoded.count <= maximumBytes {
          return .success(PlatformCapturedImage(bytes: FlutterStandardTypedData(bytes: encoded), mimeType: "image/jpeg"))
        }
      }
      dimension = Int(Double(dimension) * 0.8)
    }
    return .failure(PigeonError(code: "image_too_large", message: "The selected image could not be reduced below 8 MB.", details: nil))
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

@MainActor
private final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onFinish: ((String?) -> Void)?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "com.gainer.mobile.capture-session")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var hasFinished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureSession()
    NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    let cancel = UIButton(type: .system)
    cancel.setTitle("Abbrechen", for: .normal)
    cancel.setTitleColor(.white, for: .normal)
    cancel.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    cancel.accessibilityLabel = "Barcode-Scan abbrechen"
    cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(cancel)
    NSLayoutConstraint.activate([
      cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startScanning()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopScanning()
  }

  func startScanning() {
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  private func stopScanning() {
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  @objc private func applicationDidEnterBackground() { stopScanning() }

  @objc private func applicationWillEnterForeground() {
    guard viewIfLoaded?.window != nil else { return }
    startScanning()
  }

  private func configureSession() {
    guard let camera = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: camera),
      session.canAddInput(input)
    else {
      finish(nil)
      return
    }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      finish(nil)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = output.availableMetadataObjectTypes.filter {
      [.ean8, .ean13, .upce, .code39, .code93, .code128, .qr].contains($0)
    }
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    previewLayer = layer
    view.layer.insertSublayer(layer, at: 0)
  }

  func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
    guard let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first(where: { $0.stringValue != nil })?.stringValue else { return }
    finish(code)
  }

  @objc private func cancelScan() { finish(nil) }

  private func finish(_ value: String?) {
    guard !hasFinished else { return }
    hasFinished = true
    stopScanning()
    dismiss(animated: true) { [weak self] in
      self?.onFinish?(value)
      self?.onFinish = nil
    }
  }
}
