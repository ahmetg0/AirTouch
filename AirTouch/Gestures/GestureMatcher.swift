import Foundation

// MARK: - Gesture Matcher

@Observable
final class GestureMatcher: @unchecked Sendable {
    private var templates: [GestureTemplate] = []
    private var lastMatchTime: [UUID: Date] = [:]

    // Circular buffer for dynamic gesture matching
    private var frameBuffer: [LandmarkSnapshot] = []
    private let maxBufferDuration: TimeInterval = 1.5
    private let maxBufferFrames = 30 // ~1.5 seconds at 20fps

    // MARK: - Update Templates

    func updateTemplates(_ templates: [GestureTemplate]) {
        self.templates = templates.filter(\.isEnabled)
    }

    // MARK: - Match Against Current Frame

    func match(frame: HandFrame) -> (GestureTemplate, Double)? {
        guard let hand = frame.dominantHand else { return nil }

        let snapshot = GestureTrainer.snapshotFromHand(hand, timestamp: frame.timestamp).normalized()

        // Add to buffer for dynamic matching
        frameBuffer.append(snapshot)
        if frameBuffer.count > maxBufferFrames {
            frameBuffer.removeFirst()
        }

        var bestMatch: (GestureTemplate, Double)?
        var bestScore = Double.infinity

        for template in templates {
            // Check cooldown
            if let lastTime = lastMatchTime[template.id],
               Date().timeIntervalSince(lastTime) < template.cooldownInterval {
                continue
            }

            let score: Double
            switch template.type {
            case .staticPose:
                score = matchStaticPose(snapshot: snapshot, template: template)
            case .dynamicMotion:
                score = matchDynamicMotion(buffer: frameBuffer, template: template)
            }

            if score < template.matchThreshold && score < bestScore {
                bestScore = score
                bestMatch = (template, score)
            }
        }

        if let match = bestMatch {
            lastMatchTime[match.0.id] = Date()
        }

        return bestMatch
    }

    // MARK: - Static Pose Matching

    /// Computes average Euclidean distance between a live snapshot and all template samples
    private func matchStaticPose(snapshot: LandmarkSnapshot, template: GestureTemplate) -> Double {
        guard !template.samples.isEmpty else { return .infinity }

        var totalDistance = 0.0
        var comparisonCount = 0

        for sample in template.samples {
            // Use the middle frame of each sample as representative
            let refIndex = sample.count / 2
            guard sample.indices.contains(refIndex) else { continue }
            let reference = sample[refIndex]

            let dist = euclideanDistance(snapshot, reference)
            totalDistance += dist
            comparisonCount += 1
        }

        guard comparisonCount > 0 else { return .infinity }
        return totalDistance / Double(comparisonCount)
    }

    // MARK: - Dynamic Motion Matching (DTW)

    /// Uses Dynamic Time Warping to compare the frame buffer against template sequences
    private func matchDynamicMotion(buffer: [LandmarkSnapshot], template: GestureTemplate) -> Double {
        guard !template.samples.isEmpty, buffer.count >= 5 else { return .infinity }

        var bestDTW = Double.infinity

        for sample in template.samples {
            guard sample.count >= 5 else { continue }
            let dtwScore = dynamicTimeWarping(seq1: buffer, seq2: sample)
            bestDTW = min(bestDTW, dtwScore)
        }

        return bestDTW
    }

    // MARK: - Distance Functions

    private func euclideanDistance(_ a: LandmarkSnapshot, _ b: LandmarkSnapshot) -> Double {
        var totalDist = 0.0
        var count = 0

        for jointID in JointID.allCases {
            guard let pa = a.joints[jointID], let pb = b.joints[jointID] else { continue }
            let dx = Double(pa.x - pb.x)
            let dy = Double(pa.y - pb.y)
            totalDist += sqrt(dx * dx + dy * dy)
            count += 1
        }

        guard count > 0 else { return .infinity }
        return totalDist / Double(count)
    }

    /// Standard DTW algorithm on sequences of landmark snapshots
    private func dynamicTimeWarping(seq1: [LandmarkSnapshot], seq2: [LandmarkSnapshot]) -> Double {
        let n = seq1.count
        let m = seq2.count

        // Use a flat array for the cost matrix
        var cost = [Double](repeating: .infinity, count: (n + 1) * (m + 1))
        let idx = { (i: Int, j: Int) -> Int in i * (m + 1) + j }

        cost[idx(0, 0)] = 0

        for i in 1...n {
            for j in 1...m {
                let d = euclideanDistance(seq1[i - 1], seq2[j - 1])
                let prev = min(cost[idx(i - 1, j)], cost[idx(i, j - 1)], cost[idx(i - 1, j - 1)])
                cost[idx(i, j)] = d + prev
            }
        }

        // Normalize by path length
        let pathLength = Double(n + m)
        return cost[idx(n, m)] / pathLength
    }

    // MARK: - Reset

    func reset() {
        frameBuffer.removeAll()
        lastMatchTime.removeAll()
    }
}
