import Foundation

// MARK: - One-Euro Filter

/// Implementation of the 1€ filter for smooth, low-latency signal filtering.
/// Reference: "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive Systems"
/// Géry Casiez, Nicolas Roussel, Daniel Vogel — CHI 2012
struct OneEuroFilter: Sendable {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    private var lastTimestamp: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.1, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    mutating func filter(value: Double, timestamp: Double) -> Double {
        let dt: Double
        if let last = lastTimestamp {
            dt = max(timestamp - last, 0.001) // avoid division by zero
        } else {
            dt = 1.0 / 30.0 // assume 30fps for first frame
        }
        lastTimestamp = timestamp

        // Estimate derivative
        let dx = dxFilter.hasValue ? (value - dxFilter.lastValue) / dt : 0.0
        let filteredDx = dxFilter.filter(value: dx, alpha: Self.smoothingFactor(dt: dt, cutoff: dCutoff))

        // Adaptive cutoff based on speed
        let cutoff = minCutoff + beta * abs(filteredDx)

        // Filter the value
        return xFilter.filter(value: value, alpha: Self.smoothingFactor(dt: dt, cutoff: cutoff))
    }

    mutating func reset() {
        xFilter = LowPassFilter()
        dxFilter = LowPassFilter()
        lastTimestamp = nil
    }

    private static func smoothingFactor(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

// MARK: - Low Pass Filter

struct LowPassFilter: Sendable {
    private(set) var lastValue: Double = 0.0
    private(set) var hasValue: Bool = false

    mutating func filter(value: Double, alpha: Double) -> Double {
        if hasValue {
            let result = alpha * value + (1.0 - alpha) * lastValue
            lastValue = result
            return result
        } else {
            hasValue = true
            lastValue = value
            return value
        }
    }

    mutating func reset() {
        lastValue = 0.0
        hasValue = false
    }
}

// MARK: - Landmark Smoother

/// Applies one-euro filtering to all landmarks in a hand independently
final class LandmarkSmoother: @unchecked Sendable {
    private var filtersX: [JointID: OneEuroFilter] = [:]
    private var filtersY: [JointID: OneEuroFilter] = [:]
    private var minCutoff: Double
    private var beta: Double

    init(minCutoff: Double = 1.0, beta: Double = 0.1) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    func updateParameters(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        // Reset filters so new parameters take effect cleanly
        filtersX.removeAll()
        filtersY.removeAll()
    }

    func smooth(hand: HandData, timestamp: TimeInterval) -> HandData {
        var smoothedLandmarks: [JointID: LandmarkPoint] = [:]

        for (jointID, point) in hand.landmarks {
            // Get or create filter for this joint
            if filtersX[jointID] == nil {
                filtersX[jointID] = OneEuroFilter(minCutoff: minCutoff, beta: beta)
            }
            if filtersY[jointID] == nil {
                filtersY[jointID] = OneEuroFilter(minCutoff: minCutoff, beta: beta)
            }

            let smoothX = filtersX[jointID]!.filter(value: Double(point.x), timestamp: timestamp)
            let smoothY = filtersY[jointID]!.filter(value: Double(point.y), timestamp: timestamp)

            smoothedLandmarks[jointID] = LandmarkPoint(
                x: Float(smoothX),
                y: Float(smoothY),
                confidence: point.confidence
            )
        }

        return HandData(
            chirality: hand.chirality,
            landmarks: smoothedLandmarks,
            timestamp: hand.timestamp
        )
    }

    func smoothFrame(_ frame: HandFrame) -> HandFrame {
        let smoothedHands = frame.hands.map { smooth(hand: $0, timestamp: frame.timestamp) }
        return HandFrame(timestamp: frame.timestamp, hands: smoothedHands)
    }

    func reset() {
        filtersX.removeAll()
        filtersY.removeAll()
    }
}
