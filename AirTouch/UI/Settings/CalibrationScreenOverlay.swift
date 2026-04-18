import AppKit
import SwiftUI

// MARK: - Full-Screen Calibration Overlay

/// Manages an NSPanel that covers the entire screen during calibration.
/// Cursor movement is suppressed by the caller (appState.isCalibrating = true).
@MainActor
final class CalibrationScreenOverlay {
    static let shared = CalibrationScreenOverlay()
    private var panel: NSPanel?

    private init() {}

    func show(
        step: Int,
        targetName: String,
        targetFraction: CGPoint,   // (x, y) in top-left origin, 0–1
        handsDetected: Int,
        onCapture: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main else { return }

        if panel == nil {
            let p = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.ignoresMouseEvents = false
            self.panel = p
        }

        let content = CalibrationOverlayContent(
            step: step,
            targetName: targetName,
            targetFraction: targetFraction,
            screenSize: screen.frame.size,
            handsDetected: handsDetected,
            onCapture: onCapture,
            onCancel: onCancel
        )
        panel?.contentView = NSHostingView(rootView: content)
        panel?.setFrame(screen.frame, display: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Overlay Content

struct CalibrationOverlayContent: View {
    let step: Int
    let targetName: String
    let targetFraction: CGPoint
    let screenSize: CGSize
    let handsDetected: Int
    let onCapture: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            // Crosshair pinned to target corner
            CrosshairTarget()
                .position(
                    x: targetFraction.x * screenSize.width,
                    y: targetFraction.y * screenSize.height
                )

            // HUD in the centre
            VStack(spacing: 14) {
                Text("Screen Calibration  •  Step \(step + 1) of 4")
                    .font(.title3).fontWeight(.semibold).foregroundStyle(.white)

                Text("Point your index finger at the **\(targetName)** crosshair, then click Capture.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 420)

                HStack(spacing: 8) {
                    Image(systemName: handsDetected > 0 ? "hand.raised.fill" : "hand.raised")
                        .foregroundStyle(handsDetected > 0 ? .green : .orange)
                    Text(handsDetected > 0 ? "Hand detected" : "No hand detected")
                        .foregroundStyle(handsDetected > 0 ? .green : .orange)
                        .font(.callout)
                }

                HStack(spacing: 16) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                        .tint(.white)

                    Button("Capture Point") { onCapture() }
                        .buttonStyle(.borderedProminent)
                        .disabled(handsDetected == 0)
                }
            }
            .padding(28)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Animated Crosshair

struct CrosshairTarget: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.red.opacity(0.35), lineWidth: 1.5)
                .frame(width: 80, height: 80)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0 : 1)

            Circle()
                .stroke(.red, lineWidth: 2)
                .frame(width: 48, height: 48)

            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            Rectangle().fill(.red).frame(width: 36, height: 2)
            Rectangle().fill(.red).frame(width: 2, height: 36)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
