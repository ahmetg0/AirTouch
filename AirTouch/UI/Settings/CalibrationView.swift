import SwiftUI

struct CalibrationView: View {
    @Environment(AppState.self) private var appState
    @State private var capturedPoints: [CGPoint] = []
    @State private var calibrationStep = 0
    @State private var isCalibrating = false
    @State private var calibrationComplete = false
    @State private var errorMessage: String?

    /// Target positions in top-left-origin fraction space (x right, y down).
    /// These map to real screen corners so the homography covers the full display.
    private let targets: [(name: String, fraction: CGPoint)] = [
        ("Top-Left",     CGPoint(x: 0.05, y: 0.05)),
        ("Top-Right",    CGPoint(x: 0.95, y: 0.05)),
        ("Bottom-Right", CGPoint(x: 0.95, y: 0.95)),
        ("Bottom-Left",  CGPoint(x: 0.05, y: 0.95))
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Screen Calibration")
                .font(.title2).fontWeight(.semibold)

            Text("Calibration maps your camera's hand position to screen coordinates, making the cursor accurate across the full display. The cursor is disabled during calibration so you can click freely.")
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
        .padding()
        .onDisappear {
            // Safety: always clean up if the view disappears mid-calibration
            if isCalibrating { cancelCalibration() }
        }
    }

    // MARK: - Calibration Flow

    private func startCalibration() {
        capturedPoints.removeAll()
        calibrationStep = 0
        calibrationComplete = false
        errorMessage = nil
        isCalibrating = true
        appState.isCalibrating = true  // suppress cursor movement
        showOverlayForCurrentStep()
    }

    private func showOverlayForCurrentStep() {
        guard calibrationStep < targets.count else { return }
        let target = targets[calibrationStep]
        CalibrationScreenOverlay.shared.show(
            step: calibrationStep,
            targetName: target.name,
            targetFraction: target.fraction,
            handsDetected: appState.handsDetected,
            onCapture: captureCurrentPoint,
            onCancel: cancelCalibration
        )
    }

    private func captureCurrentPoint() {
        guard let indexTip = appState.currentFrame?.dominantHand?.indexTip else { return }

        // Vision coordinates: x left→right [0,1], y bottom→top [0,1]
        let visionPoint = CGPoint(x: CGFloat(indexTip.x), y: CGFloat(indexTip.y))
        capturedPoints.append(visionPoint)
        calibrationStep += 1

        if calibrationStep >= targets.count {
            CalibrationScreenOverlay.shared.hide()
            computeCalibration()
        } else {
            showOverlayForCurrentStep()
        }
    }

    private func cancelCalibration() {
        CalibrationScreenOverlay.shared.hide()
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

        // Screen targets in CGEvent space (top-left origin, y down)
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
