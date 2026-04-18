import SwiftUI

// MARK: - App Delegate

final class AirTouchAppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState?.initialize()
        // First permission check — deferred so menu bar icon appears first,
        // and runs on a background thread so it never blocks the UI.
        schedulePermissionRefresh(delay: 1.0)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check when user returns (e.g. after granting in System Settings).
        schedulePermissionRefresh(delay: 0.5)
    }

    private func schedulePermissionRefresh(delay: Double) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.appState?.refreshPermissionsInBackground()
        }
    }
}

// MARK: - App

@main
struct AirTouchApp: App {
    @NSApplicationDelegateAdaptor(AirTouchAppDelegate.self) var delegate
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with pull-down menu
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .onAppear { delegate.appState = appState }
        } label: {
            Image(systemName: appState.menuBarIconName)
        }

        // Main settings window
        Window("AirTouch", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .defaultSize(width: 750, height: 520)
        .restorationBehavior(.disabled)

        // Camera preview window
        Window("Camera Preview", id: "camera-preview") {
            CameraPreviewView()
                .environment(appState)
        }
        .windowStyle(.plain)
        .defaultSize(width: 640, height: 514)
        .restorationBehavior(.disabled)

        // Onboarding window
        Window("Welcome to AirTouch", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
        .restorationBehavior(.disabled)
    }
}
