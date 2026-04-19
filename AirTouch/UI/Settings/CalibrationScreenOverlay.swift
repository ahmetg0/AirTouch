import AppKit
import Combine
import SwiftUI

// MARK: - Full-Screen Calibration Overlay

/// Manages an NSPanel that covers the entire screen during calibration.
/// Cursor movement is suppressed by the caller (appState.isCalibrating = true).
@MainActor
final class CalibrationScreenOverlay {
    static let shared = CalibrationScreenOverlay()
    private var panel: NSPanel?
    private var escapeMonitor: Any?

    private init() {}

    func show(
        step: Int,
        targetName: String,
        targetFraction: CGPoint,
        cornerIndex: Int,
        appState: AppState,
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

        // App-level Escape key monitor — works even if panel doesn't have key focus
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onCancel()
                return nil  // consume the event
            }
            return event
        }

        let content = CalibrationOverlayContent(
            step: step,
            totalSteps: 4,
            targetName: targetName,
            targetFraction: targetFraction,
            screenSize: screen.frame.size,
            cornerIndex: cornerIndex,
            onCapture: onCapture,
            onCancel: onCancel
        )
        .environment(appState)

        panel?.contentView = NSHostingView(rootView: content)
        panel?.setFrame(screen.frame, display: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        removeEscapeMonitor()
        panel?.close()
        panel = nil
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}

// MARK: - Overlay Content

struct CalibrationOverlayContent: View {
    let step: Int
    let totalSteps: Int
    let targetName: String
    let targetFraction: CGPoint
    let screenSize: CGSize
    let cornerIndex: Int
    let onCapture: () -> Void
    let onCancel: () -> Void

    @Environment(AppState.self) private var appState
    @State private var pinchProgress: Double = 0
    @State private var captured = false

    private let pinchThreshold: Float = 0.05
    private let holdDuration: Double = 2.0

    private var isPinching: Bool {
        guard let hand = appState.currentFrame?.dominantHand,
              let thumb = hand.thumbTip,
              let index = hand.indexTip else { return false }
        return thumb.distance(to: index) < pinchThreshold
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            // Corner target with progress ring
            ZStack {
                CornerTarget(corner: cornerIndex)

                // Pinch progress ring
                Circle()
                    .trim(from: 0, to: pinchProgress)
                    .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: pinchProgress)
            }
            .position(
                x: targetFraction.x * screenSize.width,
                y: targetFraction.y * screenSize.height
            )

            // Centre HUD
            VStack(spacing: 14) {
                if captured {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("Captured!")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.green)
                } else {
                    Text("Step \(step + 1) of \(totalSteps)")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("Point at the **\(targetName)** corner\nand **pinch for 2 seconds** to capture")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: 380)

                    // Hand / pinch status
                    HStack(spacing: 8) {
                        if isPinching {
                            Image(systemName: "hand.pinch.fill")
                                .foregroundStyle(.green)
                            Text("Pinching — hold steady…")
                                .foregroundStyle(.green)
                        } else if appState.handsDetected > 0 {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.yellow)
                            Text("Hand detected — pinch to capture")
                                .foregroundStyle(.yellow)
                        } else {
                            Image(systemName: "hand.raised")
                                .foregroundStyle(.orange)
                            Text("No hand detected")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.callout)

                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .padding(28)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard !captured else { return }

            // Read pinch state from the live hand frame
            let pinching: Bool = {
                guard let hand = appState.currentFrame?.dominantHand,
                      let thumb = hand.thumbTip,
                      let index = hand.indexTip else { return false }
                return thumb.distance(to: index) < pinchThreshold
            }()

            if pinching {
                pinchProgress = min(1.0, pinchProgress + 0.1 / holdDuration)
                if pinchProgress >= 1.0 {
                    captured = true
                    // Brief visual feedback before advancing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onCapture()
                    }
                }
            } else {
                // Reset progress when pinch is released
                pinchProgress = 0
            }
        }
    }
}

// MARK: - Corner Target

/// Draws a crosshair-style marker whose lines extend inward from the corner.
struct CornerTarget: View {
    let corner: Int   // 0 = TL, 1 = TR, 2 = BR, 3 = BL
    @State private var pulse = false

    /// Horizontal direction toward screen centre
    private var dx: CGFloat { (corner == 0 || corner == 3) ? 1 : -1 }
    /// Vertical direction toward screen centre
    private var dy: CGFloat { (corner == 0 || corner == 1) ? 1 : -1 }

    var body: some View {
        ZStack {
            // Pulsing ring
            Circle()
                .stroke(.red.opacity(0.35), lineWidth: 1.5)
                .frame(width: 70, height: 70)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0 : 1)

            // Corner dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            // Horizontal line pointing inward
            Rectangle()
                .fill(.red)
                .frame(width: 44, height: 2.5)
                .offset(x: dx * 22)

            // Vertical line pointing inward
            Rectangle()
                .fill(.red)
                .frame(width: 2.5, height: 44)
                .offset(y: dy * 22)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
