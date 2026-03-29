import SwiftUI

struct CalibrationView: View {
    @Environment(AppState.self) private var appState
    @State private var calibrationStep = 0
    @State private var capturedPoints: [CGPoint] = []
    @State private var isCalibrating = false
    @State private var calibrationComplete = false
    @State private var statusMessage = ""

    private let targetPositions: [(String, CGPoint)] = [
        ("Top-Left", CGPoint(x: 0.15, y: 0.15)),
        ("Top-Right", CGPoint(x: 0.85, y: 0.15)),
        ("Bottom-Right", CGPoint(x: 0.85, y: 0.85)),
        ("Bottom-Left", CGPoint(x: 0.15, y: 0.85))
    ]

    var body: some View {
        VStack(spacing: 20) {
            if isCalibrating {
                calibrationOverlay
            } else {
                calibrationInfo
            }
        }
        .padding()
    }

    // MARK: - Info View

    private var calibrationInfo: some View {
        VStack(spacing: 16) {
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Screen Calibration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Calibration improves cursor accuracy by mapping your camera's view to your screen. You'll point at 4 targets on screen and press Capture to confirm each one.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if appState.settings.calibrationData != nil {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Calibration data saved")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button("Start Calibration") {
                    startCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.cameraManager.isRunning)

                if appState.settings.calibrationData != nil {
                    Button("Clear Calibration") {
                        appState.settings.calibrationData = nil
                        appState.cursorController.calibrationTransform = nil
                    }
                }
            }

            if !appState.cameraManager.isRunning {
                Text("Start tracking first to enable calibration")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Calibration Overlay

    private let cameraWidth: CGFloat = 480
    private let cameraHeight: CGFloat = 360

    private var calibrationOverlay: some View {
        ZStack {
            // Camera feed fills the calibration area
            CameraFeedLayer(session: appState.cameraManager.currentSession)
                .frame(width: cameraWidth, height: cameraHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Hand landmarks
            if let frame = appState.currentFrame {
                LandmarkOverlay(frame: frame, size: CGSize(width: cameraWidth, height: cameraHeight))
            }

            if calibrationComplete {
                // Completion overlay
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Calibration Complete!")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Your cursor mapping has been updated.")
                        .foregroundStyle(.white.opacity(0.8))
                    Button("Done") {
                        isCalibrating = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            } else {
                // Target crosshair on the camera feed
                let target = targetPositions[calibrationStep]
                Circle()
                    .stroke(.red, lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().fill(.red.opacity(0.4)).frame(width: 10, height: 10)
                    }
                    .position(
                        x: target.1.x * cameraWidth,
                        y: target.1.y * cameraHeight
                    )

                // Step info at top
                VStack(spacing: 4) {
                    Text("Point at: \(target.0)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Step \(calibrationStep + 1) of 4")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)

                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 56)
                }

                // Buttons at bottom
                HStack(spacing: 16) {
                    Button("Cancel") {
                        isCalibrating = false
                        capturedPoints.removeAll()
                        calibrationStep = 0
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button("Capture Point") {
                        captureCurrentPoint()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.currentFrame?.dominantHand?.indexTip == nil)
                }
                .padding(10)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
            }
        }
        .frame(width: cameraWidth, height: cameraHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Calibration Logic

    private func startCalibration() {
        isCalibrating = true
        calibrationComplete = false
        calibrationStep = 0
        capturedPoints.removeAll()
        statusMessage = "Point your index finger at the red target"
    }

    private func captureCurrentPoint() {
        guard let hand = appState.currentFrame?.dominantHand,
              let indexTip = hand.indexTip else {
            statusMessage = "No hand detected — show your hand to the camera"
            return
        }

        let cameraPoint = CGPoint(x: CGFloat(indexTip.x), y: CGFloat(indexTip.y))
        capturedPoints.append(cameraPoint)
        calibrationStep += 1

        if calibrationStep >= 4 {
            // Compute calibration transform
            computeCalibration()
        } else {
            statusMessage = "Point at the next target"
        }
    }

    private func computeCalibration() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let screenTargets = targetPositions.map { target in
            CGPoint(
                x: target.1.x * screenFrame.width,
                y: target.1.y * screenFrame.height
            )
        }

        // Flip Y on camera points (Vision bottom-left → screen top-left)
        let flippedCameraPoints = capturedPoints.map { point in
            CGPoint(x: point.x, y: 1.0 - point.y)
        }

        if let transform = CalibrationTransform.compute(
            from: flippedCameraPoints,
            to: screenTargets
        ) {
            appState.cursorController.calibrationTransform = transform

            // Save calibration data
            appState.settings.calibrationData = CalibrationData(
                cameraPoints: capturedPoints,
                screenPoints: screenTargets,
                matrix: transform.matrix
            )

            calibrationComplete = true
            statusMessage = ""
        } else {
            statusMessage = "Calibration failed — try again with clearer hand position"
            capturedPoints.removeAll()
            calibrationStep = 0
        }
    }
}
