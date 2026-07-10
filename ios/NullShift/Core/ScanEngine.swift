import AVFoundation
import SwiftUI
import UIKit
import Vision

// Real on-device body measurement — silhouette edition.
//
// Pipeline: Apple Vision person segmentation (runs entirely on the phone,
// no model download) → silhouette breadth (front photo) and depth (side
// photo) at anthropometric waist/hip heights → ellipse circumference,
// calibrated by the user's height. Photos live in MEMORY ONLY: never
// written to disk, never uploaded, dropped the moment measuring ends.
//
// Honesty note: this is silhouette math with a few-cm error bar, offered
// as an ESTIMATE the user can correct by hand. The v1.5 engine (MediaPipe
// pose + SMPL fitting per the locked platform decision) replaces the math,
// not the flow.

enum ScanEngine {
    struct Result {
        let waistCm: Double
        let hipCm: Double
    }

    enum ScanError: LocalizedError {
        case noPerson
        case tooSmall
        case implausible

        var errorDescription: String? {
            switch self {
            case .noPerson: "Không thấy người trong khung — đứng vào giữa khung nhé."
            case .tooSmall: "Đứng gần hơn một chút — cả người phải chiếm phần lớn khung hình."
            case .implausible: "Số đo không hợp lý — kiểm tra tư thế và ánh sáng rồi quét lại."
            }
        }
    }

    /// One segmented photo: per-row mask runs + person bounding box.
    struct Silhouette {
        let personTop: Int
        let personBottom: Int
        let centerX: Int
        /// For each mask row, the contiguous person runs (excludes gaps —
        /// this is what keeps outstretched arms out of a waist reading).
        let runs: [[Range<Int>]]

        var personHeightPx: Int { personBottom - personTop }

        /// Median body width (px) around `fraction` of the person's height
        /// measured from the top — only the run containing the body center
        /// counts, so limbs separated from the torso are ignored.
        func widthAt(fraction: Double) -> Double? {
            let target = personTop + Int(Double(personHeightPx) * fraction)
            var widths: [Int] = []
            for y in (target - 3)...(target + 3) where runs.indices.contains(y) {
                guard let run = runs[y].first(where: { $0.contains(centerX) })
                    ?? runs[y].min(by: {
                        abs($0.lowerBound + $0.count / 2 - centerX) <
                        abs($1.lowerBound + $1.count / 2 - centerX)
                    })
                else { continue }
                widths.append(run.count)
            }
            guard !widths.isEmpty else { return nil }
            return Double(widths.sorted()[widths.count / 2])
        }
    }

    // Anthropometric row positions, as a fraction of body height from the
    // top of the head (waist ≈ navel level, hip = widest trochanter level).
    private static let waistFraction = 0.38
    private static let hipFraction = 0.47

    /// Person silhouette via Vision — on-device, CPU/ANE.
    static func silhouette(of image: UIImage) async throws -> Silhouette {
        let cg = normalized(image)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            guard let mask = request.results?.first?.pixelBuffer else {
                throw ScanError.noPerson
            }
            return try parse(mask: mask)
        }.value
    }

    /// Combines front (breadth) + side (depth) silhouettes into waist/hip
    /// circumference estimates, calibrated by the user's height.
    static func measurements(front: Silhouette, side: Silhouette, heightCm: Double) throws -> Result {
        let cmPerPxFront = heightCm / Double(front.personHeightPx)
        let cmPerPxSide = heightCm / Double(side.personHeightPx)

        guard
            let waistBreadthPx = front.widthAt(fraction: waistFraction),
            let hipBreadthPx = front.widthAt(fraction: hipFraction),
            let waistDepthPx = side.widthAt(fraction: waistFraction),
            let hipDepthPx = side.widthAt(fraction: hipFraction)
        else { throw ScanError.noPerson }

        let waist = ellipseCircumference(
            a: waistBreadthPx * cmPerPxFront / 2,
            b: waistDepthPx * cmPerPxSide / 2
        )
        let hip = ellipseCircumference(
            a: hipBreadthPx * cmPerPxFront / 2,
            b: hipDepthPx * cmPerPxSide / 2
        )
        guard (40...200).contains(waist), (50...220).contains(hip) else {
            throw ScanError.implausible
        }
        return Result(waistCm: waist, hipCm: hip)
    }

    /// Ramanujan's ellipse perimeter approximation.
    private static func ellipseCircumference(a: Double, b: Double) -> Double {
        Double.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
    }

    private static func parse(mask: CVPixelBuffer) throws -> Silhouette {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { throw ScanError.noPerson }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var runs: [[Range<Int>]] = Array(repeating: [], count: height)
        var top = -1, bottom = -1, minX = width, maxX = 0
        for y in 0..<height {
            var x = 0
            while x < width {
                if pixels[y * stride + x] > 127 {
                    let start = x
                    while x < width, pixels[y * stride + x] > 127 { x += 1 }
                    // Ignore speckle noise narrower than ~1% of the frame.
                    if x - start > width / 100 {
                        runs[y].append(start..<x)
                        if top < 0 { top = y }
                        bottom = y
                        minX = min(minX, start)
                        maxX = max(maxX, x)
                    }
                } else {
                    x += 1
                }
            }
        }
        guard top >= 0, bottom > top else { throw ScanError.noPerson }
        // The person must dominate the frame for height calibration to hold.
        guard bottom - top >= height / 2 else { throw ScanError.tooSmall }
        return Silhouette(
            personTop: top,
            personBottom: bottom,
            centerX: (minX + maxX) / 2,
            runs: runs
        )
    }

    /// Upright, ≤1440 px on the long edge — Vision runs faster and the
    /// mask geometry no longer depends on EXIF orientation.
    private static func normalized(_ image: UIImage) -> CGImage {
        let maxDim: CGFloat = 1440
        let scale = min(1, maxDim / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let redrawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage!
    }
}

/// Front-camera capture for the scan — session + one-shot photo capture.
@MainActor
final class ScanCamera: NSObject, ObservableObject {
    enum State { case starting, ready, denied, unavailable }

    @Published var state: State = .starting

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage, Error>?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .denied
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            state = .unavailable
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
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
            continuation = cont
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension ScanCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            if let image {
                continuation?.resume(returning: image)
            } else {
                continuation?.resume(throwing: error ?? ScanEngine.ScanError.noPerson)
            }
            continuation = nil
        }
    }
}

/// Live viewfinder for the scan session.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
