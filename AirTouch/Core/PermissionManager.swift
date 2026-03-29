import AVFoundation
import AppKit

// MARK: - Permission Manager

@Observable
final class PermissionManager: @unchecked Sendable {
    private(set) var cameraStatus: AVAuthorizationStatus = .notDetermined
    private(set) var accessibilityGranted = false

    // MARK: - Camera

    func checkCamera() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestCamera() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .authorized : .denied
        return granted
    }

    var isCameraAuthorized: Bool { cameraStatus == .authorized }

    // MARK: - Accessibility

    func checkAccessibility() {
        // AXIsProcessTrusted() can return false even when CGEvent posting works
        // (observed on macOS 26). Use a practical test: try to create and post
        // a no-op mouse move to the current cursor position.
        let trusted = AXIsProcessTrusted()
        if trusted {
            accessibilityGranted = true
            return
        }

        // Fallback: test if we can actually post a CGEvent
        accessibilityGranted = canPostCGEvents()
    }

    /// Prompt macOS to show the accessibility trust dialog for this specific app binary.
    func promptAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
        // Re-check after prompting
        checkAccessibility()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Combined Status

    var allPermissionsGranted: Bool {
        isCameraAuthorized && accessibilityGranted
    }

    /// Poll accessibility status (it can change while app is running)
    func startPollingAccessibility() -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                checkAccessibility()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Private

    /// Practical test: attempt to post a harmless mouse-move event to the current cursor location.
    /// Returns true if CGEvent posting succeeds (meaning we have the required privileges).
    private func canPostCGEvents() -> Bool {
        guard let source = CGEvent(source: nil) else { return false }
        let currentPos = source.location
        guard let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: currentPos,
            mouseButton: .left
        ) else { return false }
        moveEvent.post(tap: .cghidEventTap)
        return true
    }
}
