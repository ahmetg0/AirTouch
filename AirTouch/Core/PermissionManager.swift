import AVFoundation
import AppKit

// MARK: - Permission Manager

@Observable
final class PermissionManager: @unchecked Sendable {
    var cameraStatus: AVAuthorizationStatus = .notDetermined
    var accessibilityGranted = false

    // MARK: - Camera

    func requestCamera() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .authorized : .denied
        return granted
    }

    var isCameraAuthorized: Bool { cameraStatus == .authorized }

    // MARK: - Accessibility

    /// Prompt macOS to show the accessibility / event-posting trust dialog.
    func promptAccessibility() {
        CGRequestPostEventAccess()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Combined Status

    var allPermissionsGranted: Bool {
        isCameraAuthorized && accessibilityGranted
    }
}
