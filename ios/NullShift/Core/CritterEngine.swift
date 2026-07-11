import AVFoundation
import SwiftUI
import UIKit
import Vision

// "Thú Cưng Đường Phố" — catch real street cats & dogs, Pokémon-GO style.
// On-device detection via Apple Vision (VNRecognizeAnimalsRequest — cats/dogs,
// no model download), a live back-camera stream, and a still capture for the
// collection. Nothing leaves the device: photos are saved to the app sandbox,
// never uploaded (the same privacy stance as the body scan).

enum Critter: String, Codable {
    case cat, dog

    var treat: String { self == .cat ? "🐟" : "🦴" }
    var label: String { self == .cat ? "Mèo" : "Cún" }
    var treatName: String { self == .cat ? "cá" : "xương" }
}

struct Detection: Equatable {
    let species: Critter
    let confidence: Float
    /// Vision space: normalized [0,1], BOTTOM-LEFT origin.
    let boundingBox: CGRect
}

/// Back-camera engine: live animal detection + a high-res catch photo.
@MainActor
final class CritterCamera: NSObject, ObservableObject {
    enum State { case starting, ready, denied, unavailable }

    @Published var state: State = .starting
    /// Latest detection — drives the on-screen reticle.
    @Published var detection: Detection?

    let session = AVCaptureSession()
    private let videoOut = AVCaptureVideoDataOutput()
    private let photoOut = AVCapturePhotoOutput()
    // Vision runs on the sample-buffer serial queue, so these live outside
    // the main actor; access is serialized by that queue.
    private nonisolated let queue = DispatchQueue(label: "critter.vision")
    private nonisolated let request = VNRecognizeAnimalsRequest()
    private nonisolated(unsafe) var lastRun = Date.distantPast
    private var photoCont: CheckedContinuation<UIImage, Error>?

    /// Set by CritterPreview once the layer exists — used to map Vision boxes
    /// to on-screen rects (handles the aspect-fill crop correctly).
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .denied
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            state = .unavailable
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
        if session.canAddOutput(photoOut) { session.addOutput(photoOut) }
        session.commitConfiguration()
        let session = session
        await Task.detached { session.startRunning() }.value
        state = .ready
    }

    func stop() {
        let session = session
        Task.detached { session.stopRunning() }
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            photoCont = cont
            photoOut.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    /// On-screen rect for a Vision bounding box (nil until the preview exists).
    func reticleRect(for box: CGRect) -> CGRect? {
        guard let layer = previewLayer else { return nil }
        // Vision boxes are bottom-left origin; flip Y for AVFoundation's
        // metadata space, then let the layer account for aspect-fill.
        let meta = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        return layer.layerRectConverted(fromMetadataOutputRect: meta)
    }
}

extension CritterCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Throttle to ~5 Hz — Vision on every frame heats the device and
        // janks the preview for no benefit. This delegate already runs on the
        // serial `queue`, so touch lastRun directly — a queue.sync onto the
        // SAME serial queue we're executing on would deadlock the first frame.
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.2 else { return }
        lastRun = now
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Back camera held in portrait → .right so boxes match the preview.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .right, options: [:])
        try? handler.perform([request])
        let best = (request.results ?? [])
            .compactMap { obs -> Detection? in
                guard let top = obs.labels.first, top.confidence > 0.6 else { return nil }
                let species: Critter? =
                    top.identifier == VNAnimalIdentifier.cat.rawValue ? .cat
                    : top.identifier == VNAnimalIdentifier.dog.rawValue ? .dog : nil
                guard let species else { return nil }
                return Detection(species: species, confidence: top.confidence, boundingBox: obs.boundingBox)
            }
            .max { $0.confidence < $1.confidence }

        Task { @MainActor in self.detection = best }
    }
}

extension CritterCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            if let image {
                photoCont?.resume(returning: image)
            } else {
                photoCont?.resume(throwing: error ?? URLError(.unknown))
            }
            photoCont = nil
        }
    }
}

/// Live viewfinder that also hands its preview layer back to the camera so
/// detections can be mapped to on-screen reticle rects.
struct CritterPreview: UIViewRepresentable {
    let camera: CritterCamera

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        camera.previewLayer = view.previewLayer
    }
}
