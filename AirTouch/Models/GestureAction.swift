import Foundation
import Carbon.HIToolbox

// MARK: - Gesture Action

enum GestureAction: Codable, Sendable, Hashable, Identifiable {
    // Mouse
    case leftClick
    case rightClick
    case middleClick
    case doubleClick

    // Scroll
    case scrollUp
    case scrollDown

    // Keyboard shortcuts
    case keyCombo(modifiers: [ModifierKey], keyCode: Int)

    // App shortcuts (preset)
    case missionControl
    case appExpose
    case launchpad
    case spotlight
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case screenshotArea

    // System
    case lockScreen
    case showDesktop

    // No action
    case none

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .keyCombo(let mods, let key):
            let modStr = mods.map(\.symbol).joined()
            return "Key: \(modStr)\(keyCodeName(key))"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launchpad"
        case .spotlight: return "Spotlight"
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .screenshotArea: return "Screenshot Area"
        case .lockScreen: return "Lock Screen"
        case .showDesktop: return "Show Desktop"
        case .none: return "None"
        }
    }

    var category: ActionCategory {
        switch self {
        case .leftClick, .rightClick, .middleClick, .doubleClick:
            return .mouse
        case .scrollUp, .scrollDown:
            return .scroll
        case .keyCombo:
            return .keyboard
        case .missionControl, .appExpose, .launchpad, .spotlight,
             .lockScreen, .showDesktop, .screenshotArea:
            return .system
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown:
            return .media
        case .none:
            return .system
        }
    }

    /// All simple (non-associated-value) actions for picker UI
    static let allSimpleActions: [GestureAction] = [
        .leftClick, .rightClick, .middleClick, .doubleClick,
        .scrollUp, .scrollDown,
        .missionControl, .appExpose, .launchpad, .spotlight,
        .playPause, .nextTrack, .previousTrack,
        .volumeUp, .volumeDown,
        .screenshotArea, .lockScreen, .showDesktop,
        .none
    ]
}

// MARK: - Action Category

enum ActionCategory: String, CaseIterable, Sendable {
    case mouse = "Mouse"
    case scroll = "Scroll"
    case keyboard = "Keyboard"
    case system = "System"
    case media = "Media"
}

// MARK: - Modifier Key

enum ModifierKey: String, Codable, Sendable, Hashable, CaseIterable {
    case command
    case option
    case control
    case shift

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }
}

// MARK: - Key Code Helper

private func keyCodeName(_ code: Int) -> String {
    switch code {
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Escape: return "Esc"
    case kVK_Delete: return "Delete"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    default:
        if let scalar = UnicodeScalar(code), scalar.isASCII {
            return String(Character(scalar)).uppercased()
        }
        return "Key(\(code))"
    }
}
