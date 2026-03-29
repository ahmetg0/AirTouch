import SwiftUI

@main
struct AirTouchApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with pull-down menu
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }

        // Main settings window
        Window("AirTouch", id: "settings") {
            SettingsView()
                .environment(appState)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    // Return to accessory mode if no other windows are open
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if NSApp.windows.filter({ $0.isVisible && $0.title != "" }).isEmpty {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                }
        }
        .defaultSize(width: 750, height: 520)

        // Camera preview window
        Window("Camera Preview", id: "camera-preview") {
            CameraPreviewView()
                .environment(appState)
        }
        .windowStyle(.plain)
        .defaultSize(width: 320, height: 260)

        // Onboarding window
        Window("Welcome to AirTouch", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }

    init() {
        // Initialize on first launch
        DispatchQueue.main.async {
            self.appState.initialize()
        }
    }
}
