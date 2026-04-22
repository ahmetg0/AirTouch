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
    case scroll = "Scroll (👌)"
    case drag = "Drag"
    case openPalmRightClick = "Open Palm Right-Click"

    var id: String { rawValue }

    var defaultAction: GestureAction {
        switch self {
        case .cursorMove: return .none
        case .pinchIndex: return .leftClick
        case .scroll: return .none
        case .drag: return .none
        case .openPalmRightClick: return .rightClick
        }
    }

    var description: String {
        switch self {
        case .cursorMove: return "Point with index finger to move the cursor"
        case .pinchIndex: return "Quick pinch thumb + index → left click"
        case .scroll: return "👌 sign (thumb+index pinched, others extended) + move middle finger"
        case .drag: return "Hold index pinch for 1+ second then move to drag"
        case .openPalmRightClick: return "Hold open palm for 1 second → right click"
        }
    }

    var icon: String {
        switch self {
        case .cursorMove: return "cursorarrow.rays"
        case .pinchIndex: return "hand.pinch"
        case .scroll: return "scroll"
        case .drag: return "hand.draw"
        case .openPalmRightClick: return "hand.raised.fingers.spread"
        }
    }

    var isReassignable: Bool { false }
}
