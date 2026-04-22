import SwiftUI

struct CalibrationView: View {
    @Environment(AppState.self) private var appState
    @State private var capturedPoints: [CGPoint] = []
    @State private var calibrationStep = 0
    @State private var isCalibrating = false
    @State private var calibrationComplete = false
    @State private var errorMessage: String?

    private let previewWidth: CGFloat = 420
    private let previewHeight: CGFloat = 315

    /// How far inward the corner dots sit (fraction of preview size).
    /// 15 % gives comfortable reach without pushing to the camera edge.
    private let dotInset: CGFloat = 0.15

    /// Screen corners — the homography maps captured Vision positions to these.
    private let targets: [(name: String, fraction: CGPoint)] = [
        ("Top-Left",     CGPoint(x: 0.0, y: 0.0)),
        ("Top-Right",    CGPoint(x: 1.0, y: 0.0)),
        ("Bottom-Right", CGPoint(x: 1.0, y: 1.0)),
        ("Bottom-Left",  CGPoint(x: 0.0, y: 1.0))
    ]

    var body: some View {
        VStack(spacing: 16) {
            if isCalibrating {
                calibratingView
            } else {
                setupView
            }
        }
        .padding()
        .onDisappear {
            if isCalibrating { cancelCalibration() }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Screen Calibration")
                .font(.title2).fontWeight(.semibold)

            Text("Align your index finger with each corner dot in the camera preview, then click Capture.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if calibrationComplete {
                Label("Calibration saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = errorMessage {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if appState.settings.calibrationData != nil {
                Label("Calibration data saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack(spacing: 16) {
                Button("Start Calibration") {
                    startCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.cameraManager.isRunning || isCalibrating)

                if appState.settings.calibrationData != nil {
                    Button("Clear Calibration") {
                        appState.settings.calibrationData = nil
                        appState.cursorController.calibrationTransform = nil
                        calibrationComplete = false
                    }
                }
            }

            if !appState.cameraManager.isRunning {
                Text("Start tracking first to enable calibration.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Calibrating View

    private var calibratingView: some View {
        VStack(spacing: 12) {
            Text("Step \(calibrationStep + 1) of 4 — \(targets[calibrationStep].name)")
                .font(.headline)

            Text("Align your **index finger** with the red dot, then click **Capture**")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Camera preview with corner markers
            ZStack {
                if appState.cameraManager.isRunning {
                    CameraFeedLayer(session: appState.cameraManager.currentSession)
                        .frame(width: previewWidth, height: previewHeight)

                    if let frame = appState.currentFrame {
                        LandmarkOverlay(
                            frame: frame,
                            size: CGSize(width: previewWidth, height: previewHeight),
                            videoDimensions: appState.cameraManager.videoDimensions
                        )
                    }
                } else {
                    Rectangle()
                        .fill(.black)
                        .frame(width: previewWidth, height: previewHeight)
                }

                // Corner dots
                ForEach(0..<4, id: \.self) { i in
                    cornerDot(index: i)
                }
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )

            // Status + buttons
            HStack(spacing: 8) {
                if appState.handsDetected > 0 {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.green)
                    Text("Hand detected")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "hand.raised")
                        .foregroundStyle(.orange)
                    Text("No hand detected")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)

            HStack(spacing: 16) {
                Button("Cancel") { cancelCalibration() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.bordered)

                Button("Capture Point") { captureCurrentPoint() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.handsDetected == 0)
            }
        }
    }

    // MARK: - Corner Dots

    /// Map a target index to a view-space position inside the camera preview.
    /// Dots are inset by `dotInset` fraction so the user doesn't have to
    /// push their finger to the very edge of the camera frame.
    private func cornerPosition(_ index: Int) -> CGPoint {
        let frac = targets[index].fraction
        let insetX = dotInset * previewWidth
        let insetY = dotInset * previewHeight
        return CGPoint(
            x: insetX + frac.x * (previewWidth  - 2 * insetX),
            y: insetY + frac.y * (previewHeight - 2 * insetY)
        )
    }

    @ViewBuilder
    private func cornerDot(index: Int) -> some View {
        let isCurrent   = index == calibrationStep
        let isCompleted = index < calibrationStep
        let pos = cornerPosition(index)

        ZStack {
            if isCurrent {
                Circle()
                    .stroke(.red.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
            }

            Circle()
                .fill(isCompleted ? .green : (isCurrent ? .red : .red.opacity(0.3)))
                .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .position(pos)
    }

    // MARK: - Calibration Flow

    private func startCalibration() {
        capturedPoints.removeAll()
        calibrationStep = 0
        calibrationComplete = false
        errorMessage = nil
        isCalibrating = true
        appState.isCalibrating = true
    }

    private func captureCurrentPoint() {
        guard let indexTip = appState.currentFrame?.dominantHand?.indexTip else { return }

        let visionPoint = CGPoint(x: CGFloat(indexTip.x), y: CGFloat(indexTip.y))
        capturedPoints.append(visionPoint)
        calibrationStep += 1

        if calibrationStep >= targets.count {
            computeCalibration()
        }
    }

    private func cancelCalibration() {
        isCalibrating = false
        appState.isCalibrating = false
        capturedPoints.removeAll()
        calibrationStep = 0
    }

    // MARK: - Compute Homography

    private func computeCalibration() {
        guard let screen = NSScreen.main else {
            finishCalibration(success: false)
            return
        }
        let W = screen.frame.width
        let H = screen.frame.height

        let screenTargets = targets.map { t in
            CGPoint(x: t.fraction.x * W, y: t.fraction.y * H)
        }

        // Flip Vision Y so both spaces share top-left origin before solving
        let flippedCamera = capturedPoints.map { CGPoint(x: $0.x, y: 1.0 - $0.y) }

        if let transform = CalibrationTransform.compute(from: flippedCamera, to: screenTargets) {
            appState.cursorController.calibrationTransform = transform
            appState.settings.calibrationData = CalibrationData(
                cameraPoints: capturedPoints,
                screenPoints: screenTargets,
                matrix: transform.matrix
            )
            finishCalibration(success: true)
        } else {
            finishCalibration(success: false)
        }
    }

    private func finishCalibration(success: Bool) {
        isCalibrating = false
        appState.isCalibrating = false
        if success {
            calibrationComplete = true
            errorMessage = nil
        } else {
            calibrationComplete = false
            errorMessage = "Calibration failed — points may be too close together. Try again."
            capturedPoints.removeAll()
            calibrationStep = 0
        }
    }
}
