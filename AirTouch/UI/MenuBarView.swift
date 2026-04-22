import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status
        Text(appState.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        // Toggle tracking
        Button {
            appState.toggleTracking()
        } label: {
            HStack {
                Image(systemName: appState.isTracking ? "stop.circle.fill" : "play.circle.fill")
                Text(appState.isTracking ? "Stop Tracking" : "Start Tracking")
            }
        }
        .keyboardShortcut("T", modifiers: [.command, .shift])
        .disabled(!appState.permissionManager.isCameraAuthorized)

        Divider()

        // Settings
        Button {
            openWindow(id: "settings")
            NSApp.activate()
        } label: {
            HStack {
                Image(systemName: "gear")
                Text("Settings...")
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        // Camera Preview
        Button {
            openWindow(id: "camera-preview")
            NSApp.activate()
        } label: {
            HStack {
                Image(systemName: "camera.viewfinder")
                Text("Camera Preview")
            }
        }

        Divider()

        // Permissions warning
        if !appState.permissionManager.allPermissionsGranted {
            Button {
                openWindow(id: "onboarding")
                NSApp.activate()
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Setup Required")
                }
            }

            Divider()
        }

        // Quit
        Button {
            appState.stopPipeline()
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit AirTouch")
        }
        .keyboardShortcut("Q", modifiers: .command)
    }
}
