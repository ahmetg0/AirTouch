import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showResetConfirmation = false

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Startup") {
                Toggle("Launch AirTouch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }
            }

            Section("Permissions") {
                HStack {
                    Label {
                        Text("Camera")
                    } icon: {
                        Image(systemName: appState.permissionManager.isCameraAuthorized
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.permissionManager.isCameraAuthorized ? .green : .red)
                    }
                    Spacer()
                    if !appState.permissionManager.isCameraAuthorized {
                        Button("Grant Access") {
                            Task {
                                await appState.permissionManager.requestCamera()
                            }
                        }
                    } else {
                        Text("Granted")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label {
                        Text("Accessibility")
                    } icon: {
                        Image(systemName: appState.permissionManager.accessibilityGranted
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.permissionManager.accessibilityGranted ? .green : .red)
                    }
                    Spacer()
                    if !appState.permissionManager.accessibilityGranted {
                        Button("Open Settings") {
                            appState.permissionManager.openAccessibilitySettings()
                        }
                    } else {
                        Text("Granted")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Data") {
                Button("Reset All Settings", role: .destructive) {
                    showResetConfirmation = true
                }

                Button("Reset Onboarding") {
                    appState.settings.hasCompletedOnboarding = false
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
                LabeledContent("App") {
                    Text("AirTouch — Hand Gesture Control for macOS")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                appState.stopPipeline()
                appState.settings.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all settings to their default values. Custom gestures will not be deleted.")
        }
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login item registration failed — reset toggle
            appState.settings.launchAtLogin = !enabled
        }
    }
}
