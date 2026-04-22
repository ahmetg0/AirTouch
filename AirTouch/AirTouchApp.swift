import SwiftUI
import AVFoundation

// MARK: - App Delegate

final class AirTouchAppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var permissionTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState?.initialize()
        startPermissionPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPermissionPolling()
    }

    func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let pm = self?.appState?.permissionManager else { return }
            // Skip polling while tracking — permissions are already known
            // and AXIsProcessTrusted() can block during camera I/O.
            guard self?.appState?.isTracking != true else { return }
            pm.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            pm.accessibilityGranted = AXIsProcessTrusted()
        }
        timer.resume()
        permissionTimer = timer
    }

    func stopPermissionPolling() {
        permissionTimer?.cancel()
        permissionTimer = nil
    }
}

// MARK: - App

@main
struct AirTouchApp: App {
    @NSApplicationDelegateAdaptor(AirTouchAppDelegate.self) var delegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .onAppear { delegate.appState = appState }
        } label: {
            Image(systemName: appState.menuBarIconName)
        }

        Window("AirTouch", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .defaultSize(width: 750, height: 520)
        .restorationBehavior(.disabled)

        Window("Camera Preview", id: "camera-preview") {
            CameraPreviewView()
                .environment(appState)
        }
        .defaultSize(width: 640, height: 480)
        .restorationBehavior(.disabled)

        Window("Welcome to AirTouch", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
        .restorationBehavior(.disabled)
    }
}
