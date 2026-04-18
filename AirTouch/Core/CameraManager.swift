import AVFoundation

// MARK: - Camera Manager

@Observable
final class CameraManager: NSObject, @unchecked Sendable {
    private(set) var isRunning = false
    private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.airtouch.camera.session", qos: .userInteractive)
    private let outputQueue = DispatchQueue(label: "com.airtouch.camera.output", qos: .userInteractive)

    /// Callback invoked on the output queue for each frame.
    /// Set this before calling startSession().
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Authorization

    func checkAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAuthorization() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = granted ? .authorized : .denied
        return granted
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard !isRunning else { return }
        errorMessage = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSession()
                self.captureSession?.startRunning()
                Task { @MainActor in
                    self.isRunning = true
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession?.stopRunning()
            self.onFrame = nil
            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    // MARK: - Configuration

    private func configureSession() throws {
        // Reuse existing session if possible
        if let existing = captureSession, existing.isRunning {
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        // Find camera: prefer front-facing, fall back to system preferred or default
        let device = findCamera()
        guard let camera = device else {
            session.commitConfiguration()
            throw CameraError.noDeviceAvailable
        }

        // Add input
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        // Add output
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)

        // Mirror the video so the user sees themselves correctly
        if let connection = output.connection(with: .video) {
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()

        self.captureSession = session
        self.videoOutput = output
    }

    private func findCamera() -> AVCaptureDevice? {
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        if let preferred = AVCaptureDevice.systemPreferredCamera {
            return preferred
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// The current capture session, exposed for preview layer
    var currentSession: AVCaptureSession? { captureSession }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frames dropped — this is expected under load
    }
}

// MARK: - Camera Errors

enum CameraError: LocalizedError {
    case noDeviceAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable: return "No camera found. Please connect a camera."
        case .cannotAddInput: return "Failed to configure camera input."
        case .cannotAddOutput: return "Failed to configure camera output."
        }
    }
}
