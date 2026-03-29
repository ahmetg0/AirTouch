import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var accessibilityPollTask: Task<Void, Never>?

    private var allPermissionsGranted: Bool {
        appState.permissionManager.isCameraAuthorized && appState.permissionManager.accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentStep) {
                welcomeStep
                    .tag(0)
                    .tabItem { Label("Welcome", systemImage: "hand.raised.fill") }
                cameraStep
                    .tag(1)
                    .tabItem { Label("Camera", systemImage: "camera.fill") }
                accessibilityStep
                    .tag(2)
                    .tabItem { Label("Accessibility", systemImage: "accessibility") }
                completeStep
                    .tag(3)
                    .tabItem { Label("Done", systemImage: "checkmark.circle.fill") }
            }
            .tabViewStyle(.automatic)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 && currentStep < 3 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? .blue : .gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep < 3 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        appState.settings.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allPermissionsGranted)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            appState.permissionManager.checkCamera()
            appState.permissionManager.checkAccessibility()
            // Poll accessibility every second so the UI updates after the user grants it
            accessibilityPollTask = Task { @MainActor in
                while !Task.isCancelled {
                    appState.permissionManager.checkAccessibility()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        .onDisappear {
            accessibilityPollTask?.cancel()
            accessibilityPollTask = nil
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to AirTouch")
                .font(.title)
                .fontWeight(.bold)

            Text("Control your Mac with hand gestures using your camera. Move the cursor with your index finger and click by pinching.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)

            Spacer()
        }
        .padding()
    }

    // MARK: - Camera Permission Step

    private var cameraStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Camera Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("AirTouch needs access to your camera to track your hand movements. No video is recorded or transmitted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)

            permissionStatusRow(
                granted: appState.permissionManager.isCameraAuthorized,
                grantedText: "Camera access granted",
                deniedText: "Camera access not granted"
            )

            if !appState.permissionManager.isCameraAuthorized {
                Button("Grant Camera Access") {
                    Task {
                        await appState.permissionManager.requestCamera()
                        // Re-activate after the system dialog dismisses
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Accessibility Permission Step

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("AirTouch needs Accessibility permission to control your cursor and simulate clicks. This is required for the app to function.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)

            permissionStatusRow(
                granted: appState.permissionManager.accessibilityGranted,
                grantedText: "Accessibility access granted",
                deniedText: "Accessibility access not granted"
            )

            if !appState.permissionManager.accessibilityGranted {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        appState.permissionManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Add AirTouch in System Settings → Privacy & Security → Accessibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if allPermissionsGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Permissions Required")
                    .font(.title)
                    .fontWeight(.bold)
            }

            // Dynamic permission checklist
            VStack(alignment: .leading, spacing: 10) {
                PermissionCheckRow(
                    label: "Camera Access",
                    granted: appState.permissionManager.isCameraAuthorized
                )
                PermissionCheckRow(
                    label: "Accessibility Access",
                    granted: appState.permissionManager.accessibilityGranted
                )
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 300)

            if allPermissionsGranted {
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "hand.point.up.left", text: "Move cursor with your index finger")
                    FeatureRow(icon: "hand.tap", text: "Pinch thumb + index to left click")
                    FeatureRow(icon: "hand.tap", text: "Pinch thumb + middle to right click")
                    FeatureRow(icon: "hand.raised", text: "Open palm + move wrist to scroll")
                }
                .frame(maxWidth: 300)

                Text("Click the hand icon in the menu bar to start tracking.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Please go back and grant the required permissions before continuing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func permissionStatusRow(granted: Bool, grantedText: String, deniedText: String) -> some View {
        Label(
            granted ? grantedText : deniedText,
            systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .foregroundStyle(granted ? .green : .red)
        .animation(.default, value: granted)
    }
}

// MARK: - Permission Check Row

private struct PermissionCheckRow: View {
    let label: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(label)
                .font(.callout)
            Spacer()
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption)
                .foregroundStyle(granted ? .green : .red)
        }
        .animation(.default, value: granted)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(text)
                .font(.callout)
        }
    }
}
