import Foundation
import Vision

// MARK: - Landmark Point

struct LandmarkPoint: Sendable, Codable, Hashable {
    let x: Float
    let y: Float
    let confidence: Float

    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    /// Euclidean distance to another point in normalized coordinate space
    func distance(to other: LandmarkPoint) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Hand Data

struct HandData: Sendable {
    let chirality: HandChirality
    let landmarks: [JointID: LandmarkPoint]
    let timestamp: TimeInterval

    // Convenience accessors for commonly-used fingertips
    var wrist: LandmarkPoint? { landmarks[.wrist] }
    var thumbTip: LandmarkPoint? { landmarks[.thumbTip] }
    var indexTip: LandmarkPoint? { landmarks[.indexTip] }
    var middleTip: LandmarkPoint? { landmarks[.middleTip] }
    var ringTip: LandmarkPoint? { landmarks[.ringTip] }
    var littleTip: LandmarkPoint? { landmarks[.littleTip] }
    var indexMCP: LandmarkPoint? { landmarks[.indexMCP] }
    var middleMCP: LandmarkPoint? { landmarks[.middleMCP] }
    var ringMCP: LandmarkPoint? { landmarks[.ringMCP] }
    var littleMCP: LandmarkPoint? { landmarks[.littleMCP] }
    var thumbIP: LandmarkPoint? { landmarks[.thumbIP] }

    /// Check if all fingers are extended (open palm)
    var isOpenPalm: Bool {
        guard let wristPt = wrist,
              let indexT = indexTip, let indexM = indexMCP,
              let middleT = middleTip, let middleM = middleMCP,
              let ringT = ringTip, let ringM = ringMCP,
              let littleT = littleTip, let littleM = littleMCP else {
            return false
        }
        // Each fingertip should be farther from wrist than its MCP joint
        let indexExtended = indexT.distance(to: wristPt) > indexM.distance(to: wristPt)
        let middleExtended = middleT.distance(to: wristPt) > middleM.distance(to: wristPt)
        let ringExtended = ringT.distance(to: wristPt) > ringM.distance(to: wristPt)
        let littleExtended = littleT.distance(to: wristPt) > littleM.distance(to: wristPt)
        return indexExtended && middleExtended && ringExtended && littleExtended
    }
}

// MARK: - Hand Chirality

enum HandChirality: String, Sendable, Codable {
    case left
    case right
    case unknown
}

// MARK: - Joint ID

/// Mirrors VNHumanHandPoseObservation.JointName for Codable support
enum JointID: String, Sendable, Codable, CaseIterable, Hashable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    var visionJointName: VNHumanHandPoseObservation.JointName {
        switch self {
        case .wrist: return .wrist
        case .thumbCMC: return .thumbCMC
        case .thumbMP: return .thumbMP
        case .thumbIP: return .thumbIP
        case .thumbTip: return .thumbTip
        case .indexMCP: return .indexMCP
        case .indexPIP: return .indexPIP
        case .indexDIP: return .indexDIP
        case .indexTip: return .indexTip
        case .middleMCP: return .middleMCP
        case .middlePIP: return .middlePIP
        case .middleDIP: return .middleDIP
        case .middleTip: return .middleTip
        case .ringMCP: return .ringMCP
        case .ringPIP: return .ringPIP
        case .ringDIP: return .ringDIP
        case .ringTip: return .ringTip
        case .littleMCP: return .littleMCP
        case .littlePIP: return .littlePIP
        case .littleDIP: return .littleDIP
        case .littleTip: return .littleTip
        }
    }

    static func from(_ jointName: VNHumanHandPoseObservation.JointName) -> JointID? {
        allCases.first { $0.visionJointName == jointName }
    }
}

// MARK: - Hand Frame

struct HandFrame: Sendable {
    let timestamp: TimeInterval
    let hands: [HandData]

    /// The primary hand used for cursor control (first detected, or matching user preference)
    var dominantHand: HandData? { hands.first }

    /// The secondary hand (for two-hand gestures like zoom)
    var offHand: HandData? { hands.count > 1 ? hands[1] : nil }

    /// Whether any hands are detected
    var isEmpty: Bool { hands.isEmpty }
}

// MARK: - Landmark Snapshot (for gesture recording)

struct LandmarkSnapshot: Sendable, Codable {
    let joints: [JointID: LandmarkPoint]
    let timestamp: TimeInterval

    /// Normalize the snapshot: translate wrist to origin, scale so wrist-to-middleMCP = 1.0
    func normalized() -> LandmarkSnapshot {
        guard let wrist = joints[.wrist],
              let middleMCP = joints[.middleMCP] else {
            return self
        }
        let refDist = wrist.distance(to: middleMCP)
        guard refDist > 0.001 else { return self }

        var normalized: [JointID: LandmarkPoint] = [:]
        for (key, point) in joints {
            let nx = (point.x - wrist.x) / refDist
            let ny = (point.y - wrist.y) / refDist
            normalized[key] = LandmarkPoint(x: nx, y: ny, confidence: point.confidence)
        }
        return LandmarkSnapshot(joints: normalized, timestamp: timestamp)
    }
}

// MARK: - Finger Bones (for skeleton drawing)

struct FingerBone: Sendable {
    static let thumb: [JointID] = [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]
    static let index: [JointID] = [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]
    static let middle: [JointID] = [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]
    static let ring: [JointID] = [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]
    static let little: [JointID] = [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]

    static let allFingers: [[JointID]] = [thumb, index, middle, ring, little]
}
