import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Gestures", systemImage: "hand.raised") {
                GestureListView()
                    .environment(appState)
            }

            Tab("Calibration", systemImage: "scope") {
                CalibrationView()
                    .environment(appState)
            }

            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
                    .environment(appState)
            }
        }
        .frame(minWidth: 650, minHeight: 450)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
