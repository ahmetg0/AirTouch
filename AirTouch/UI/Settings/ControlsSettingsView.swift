import SwiftUI

struct ControlsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Cursor") {
                Slider(value: $settings.sensitivity, in: 0.2...2.0, step: 0.1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Low").font(.caption2)
                } maximumValueLabel: {
                    Text("High").font(.caption2)
                }

                Slider(value: $settings.cursorSpeed, in: 0.2...3.0, step: 0.1) {
                    Text("Cursor Speed")
                } minimumValueLabel: {
                    Text("Slow").font(.caption2)
                } maximumValueLabel: {
                    Text("Fast").font(.caption2)
                }
            }

            Section("Smoothing") {
                Slider(value: $settings.smoothingMinCutoff, in: 0.1...5.0, step: 0.1) {
                    Text("Smoothing (Min Cutoff)")
                } minimumValueLabel: {
                    Text("Smooth").font(.caption2)
                } maximumValueLabel: {
                    Text("Responsive").font(.caption2)
                }

                Slider(value: $settings.smoothingBeta, in: 0.0...1.0, step: 0.01) {
                    Text("Speed Coefficient (Beta)")
                } minimumValueLabel: {
                    Text("0").font(.caption2)
                } maximumValueLabel: {
                    Text("1.0").font(.caption2)
                }
            }

            Section("Pinch") {
                Slider(value: $settings.pinchThreshold, in: 0.01...0.12, step: 0.005) {
                    Text("Pinch Threshold  \(settings.pinchThreshold, specifier: "%.3f")")
                } minimumValueLabel: {
                    Text("Tight").font(.caption2)
                } maximumValueLabel: {
                    Text("Loose").font(.caption2)
                }
            }

            Section("Drag") {
                Slider(value: $settings.dragHoldDuration, in: 0.1...2.0, step: 0.1) {
                    Text("Hold Duration  \(settings.dragHoldDuration, specifier: "%.1f")s")
                } minimumValueLabel: {
                    Text("0.1s").font(.caption2)
                } maximumValueLabel: {
                    Text("2.0s").font(.caption2)
                }
            }

            Section("Open Palm Right-Click") {
                LabeledContent("Hold Duration", value: "1.0s (fixed)")
                    .foregroundStyle(.secondary)
            }

            Section("Scroll") {
                Slider(value: $settings.scrollSpeed, in: 0.2...5.0, step: 0.2) {
                    Text("Scroll Speed")
                } minimumValueLabel: {
                    Text("Slow").font(.caption2)
                } maximumValueLabel: {
                    Text("Fast").font(.caption2)
                }

                Toggle("Invert Scroll Direction", isOn: $settings.invertScroll)
            }

            Section("Accessibility") {
                Toggle("Dwell Click", isOn: $settings.dwellClickEnabled)

                if settings.dwellClickEnabled {
                    Slider(value: $settings.dwellClickDuration, in: 0.5...2.0, step: 0.1) {
                        Text("Dwell Duration")
                    } minimumValueLabel: {
                        Text("0.5s").font(.caption2)
                    } maximumValueLabel: {
                        Text("2.0s").font(.caption2)
                    }
                }
            }

            Section("Hand Preference") {
                Picker("Dominant Hand", selection: $settings.dominantHand) {
                    Text("Right").tag(HandChirality.right)
                    Text("Left").tag(HandChirality.left)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: settings.sensitivity) { appState.syncSettings() }
        .onChange(of: settings.cursorSpeed) { appState.syncSettings() }
        .onChange(of: settings.scrollSpeed) { appState.syncSettings() }
    }
}
