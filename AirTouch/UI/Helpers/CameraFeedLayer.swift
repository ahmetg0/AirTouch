import SwiftUI
import AVFoundation

// MARK: - Camera Feed Layer

/// NSViewRepresentable wrapping AVCaptureVideoPreviewLayer for displaying live camera feed
struct CameraFeedLayer: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        // Only update if the session actually changed
        if nsView.session !== session {
            nsView.session = session
        }
    }
}

// MARK: - Camera Preview NSView

class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? {
        didSet {
            guard session !== oldValue else { return }
            setupPreviewLayer()
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    private func setupPreviewLayer() {
        // Remove existing layer
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        guard let session else { return }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        // Mirror the preview to match the user's perspective (selfie view)
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        self.wantsLayer = true
        self.layer?.addSublayer(layer)
        previewLayer = layer
    }
}
