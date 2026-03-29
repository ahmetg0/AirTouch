import Foundation

// MARK: - Gesture Template

struct GestureTemplate: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var type: GestureType
    var action: GestureAction
    var samples: [[LandmarkSnapshot]]
    var matchThreshold: Double
    var cooldownInterval: TimeInterval
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: GestureType,
        action: GestureAction,
        samples: [[LandmarkSnapshot]] = [],
        matchThreshold: Double = 0.08,
        cooldownInterval: TimeInterval = 0.8,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.action = action
        self.samples = samples
        self.matchThreshold = matchThreshold
        self.cooldownInterval = cooldownInterval
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    var sampleCount: Int { samples.count }
    var isReadyForMatching: Bool { sampleCount >= 5 }
}

// MARK: - Gesture Type

enum GestureType: String, Codable, Sendable, CaseIterable {
    case staticPose = "Static Pose"
    case dynamicMotion = "Dynamic Motion"

    var description: String {
        switch self {
        case .staticPose: return "A fixed hand shape (e.g., fist, peace sign)"
        case .dynamicMotion: return "A hand movement (e.g., swipe, circle)"
        }
    }

    var minimumSamples: Int {
        switch self {
        case .staticPose: return 5
        case .dynamicMotion: return 8
        }
    }

    var recommendedSamples: Int {
        switch self {
        case .staticPose: return 15
        case .dynamicMotion: return 12
        }
    }
}

// MARK: - Built-in Gesture Definition

enum BuiltInGesture: String, CaseIterable, Sendable, Identifiable {
    case cursorMove = "Cursor Movement"
    case pinchIndex = "Pinch (Index)"
    case pinchMiddle = "Pinch (Middle)"
    case pinchRing = "Pinch (Ring)"
    case pinchLittle = "Pinch (Little)"
    case scroll = "Scroll"
    case drag = "Drag"
    case zoom = "Zoom"

    var id: String { rawValue }

    var defaultAction: GestureAction {
        switch self {
        case .cursorMove: return .none
        case .pinchIndex: return .leftClick
        case .pinchMiddle: return .rightClick
        case .pinchRing: return .middleClick
        case .pinchLittle: return .none
        case .scroll: return .none
        case .drag: return .none
        case .zoom: return .none
        }
    }

    var description: String {
        switch self {
        case .cursorMove: return "Index fingertip controls cursor position"
        case .pinchIndex: return "Thumb + Index finger pinch"
        case .pinchMiddle: return "Thumb + Middle finger pinch"
        case .pinchRing: return "Thumb + Ring finger pinch"
        case .pinchLittle: return "Thumb + Little finger pinch"
        case .scroll: return "Open palm + vertical wrist movement"
        case .drag: return "Index pinch hold + move"
        case .zoom: return "Two hands, change distance between index tips"
        }
    }

    var isReassignable: Bool {
        switch self {
        case .cursorMove, .scroll, .drag, .zoom: return false
        case .pinchIndex, .pinchMiddle, .pinchRing, .pinchLittle: return true
        }
    }
}
