import SwiftUI

// MARK: - App Settings

@Observable
final class AppSettings {
    // MARK: Tracking
    var trackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "trackingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "trackingEnabled") }
    }

    // MARK: Cursor
    var sensitivity: Double {
        get { UserDefaults.standard.double(forKey: "sensitivity").clamped(to: 0.1...2.0, default: 1.0) }
        set { UserDefaults.standard.set(newValue, forKey: "sensitivity") }
    }

    var cursorSpeed: Double {
        get { UserDefaults.standard.double(forKey: "cursorSpeed").clamped(to: 0.1...3.0, default: 1.0) }
        set { UserDefaults.standard.set(newValue, forKey: "cursorSpeed") }
    }

    // MARK: Smoothing
    var smoothingMinCutoff: Double {
        get { UserDefaults.standard.double(forKey: "smoothingMinCutoff").clamped(to: 0.01...10.0, default: 1.0) }
        set { UserDefaults.standard.set(newValue, forKey: "smoothingMinCutoff") }
    }

    var smoothingBeta: Double {
        get { UserDefaults.standard.double(forKey: "smoothingBeta").clamped(to: 0.0...1.0, default: 0.1) }
        set { UserDefaults.standard.set(newValue, forKey: "smoothingBeta") }
    }

    // MARK: Pinch
    var pinchThreshold: Double {
        get { UserDefaults.standard.double(forKey: "pinchThreshold").clamped(to: 0.01...0.15, default: 0.04) }
        set { UserDefaults.standard.set(newValue, forKey: "pinchThreshold") }
    }

    var pinchDebounceFrames: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "pinchDebounceFrames")
            return val > 0 ? val : 2
        }
        set { UserDefaults.standard.set(newValue, forKey: "pinchDebounceFrames") }
    }

    // MARK: Drag
    var dragHoldDuration: Double {
        get { UserDefaults.standard.double(forKey: "dragHoldDuration").clamped(to: 0.1...2.0, default: 0.4) }
        set { UserDefaults.standard.set(newValue, forKey: "dragHoldDuration") }
    }

    // MARK: Scroll
    var scrollSpeed: Double {
        get { UserDefaults.standard.double(forKey: "scrollSpeed").clamped(to: 0.1...5.0, default: 1.0) }
        set { UserDefaults.standard.set(newValue, forKey: "scrollSpeed") }
    }

    var invertScroll: Bool {
        get { UserDefaults.standard.bool(forKey: "invertScroll") }
        set { UserDefaults.standard.set(newValue, forKey: "invertScroll") }
    }

    // MARK: Dwell Click
    var dwellClickEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "dwellClickEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "dwellClickEnabled") }
    }

    var dwellClickDuration: Double {
        get { UserDefaults.standard.double(forKey: "dwellClickDuration").clamped(to: 0.5...2.0, default: 1.0) }
        set { UserDefaults.standard.set(newValue, forKey: "dwellClickDuration") }
    }

    // MARK: Hand Preference
    var dominantHand: HandChirality {
        get {
            let raw = UserDefaults.standard.string(forKey: "dominantHand") ?? "right"
            return HandChirality(rawValue: raw) ?? .right
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "dominantHand") }
    }

    // MARK: Built-in Gesture Action Overrides
    var pinchIndexAction: GestureAction {
        get { loadAction(forKey: "pinchIndexAction") ?? .leftClick }
        set { saveAction(newValue, forKey: "pinchIndexAction") }
    }

    var pinchMiddleAction: GestureAction {
        get { loadAction(forKey: "pinchMiddleAction") ?? .rightClick }
        set { saveAction(newValue, forKey: "pinchMiddleAction") }
    }

    var pinchRingAction: GestureAction {
        get { loadAction(forKey: "pinchRingAction") ?? .middleClick }
        set { saveAction(newValue, forKey: "pinchRingAction") }
    }

    var pinchLittleAction: GestureAction {
        get { loadAction(forKey: "pinchLittleAction") ?? .none }
        set { saveAction(newValue, forKey: "pinchLittleAction") }
    }

    // MARK: UI Preferences
    var showCameraPreview: Bool {
        get { UserDefaults.standard.bool(forKey: "showCameraPreview") }
        set { UserDefaults.standard.set(newValue, forKey: "showCameraPreview") }
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }

    // MARK: Calibration
    var calibrationData: CalibrationData? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "calibrationData") else { return nil }
            return try? JSONDecoder().decode(CalibrationData.self, from: data)
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "calibrationData")
        }
    }

    // MARK: Reset
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.ahmetgundogdu.AirTouch"
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    // MARK: Private Helpers
    private func loadAction(forKey key: String) -> GestureAction? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GestureAction.self, from: data)
    }

    private func saveAction(_ action: GestureAction, forKey key: String) {
        let data = try? JSONEncoder().encode(action)
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Calibration Data

struct CalibrationData: Codable, Sendable {
    let cameraPoints: [CGPoint]
    let screenPoints: [CGPoint]
    let matrix: [Double]
}

// MARK: - Double Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 && !range.contains(0) { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
