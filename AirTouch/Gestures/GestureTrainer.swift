import Foundation

// MARK: - Gesture Trainer

@Observable
final class GestureTrainer: @unchecked Sendable {
    private(set) var isRecording = false
    private(set) var recordedSamples: [[LandmarkSnapshot]] = []
    private(set) var currentRecordingFrames: [LandmarkSnapshot] = []
    private(set) var recordingProgress: Double = 0

    private var recordingStartTime: Date?
    private var recordingTimer: Task<Void, Never>?

    // Configuration
    let staticCaptureDuration: TimeInterval = 2.0
    let staticSnapshotCount = 15
    let dynamicMaxDuration: TimeInterval = 1.5
    let dynamicFPS: Double = 20.0

    var sampleCount: Int { recordedSamples.count }

    // MARK: - Static Pose Recording

    /// Start recording a static pose (auto-captures 15 frames over 2 seconds)
    func startStaticRecording(frameProvider: @escaping () -> HandFrame?) {
        guard !isRecording else { return }
        isRecording = true
        currentRecordingFrames = []
        recordingProgress = 0
        recordingStartTime = Date()

        recordingTimer = Task { @MainActor in
            let interval = staticCaptureDuration / Double(staticSnapshotCount)

            for i in 0..<staticSnapshotCount {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))

                if let frame = frameProvider(), let hand = frame.dominantHand {
                    let snapshot = Self.snapshotFromHand(hand, timestamp: frame.timestamp)
                    currentRecordingFrames.append(snapshot)
                }
                recordingProgress = Double(i + 1) / Double(staticSnapshotCount)
            }

            if !currentRecordingFrames.isEmpty {
                // Normalize all snapshots
                let normalized = currentRecordingFrames.map { $0.normalized() }
                recordedSamples.append(normalized)
            }
            isRecording = false
        }
    }

    // MARK: - Dynamic Motion Recording

    /// Start recording a dynamic motion (records until stopped, max 1.5s)
    func startDynamicRecording(frameProvider: @escaping () -> HandFrame?) {
        guard !isRecording else { return }
        isRecording = true
        currentRecordingFrames = []
        recordingProgress = 0
        recordingStartTime = Date()

        recordingTimer = Task { @MainActor in
            let frameInterval = 1.0 / dynamicFPS

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(recordingStartTime ?? Date())
                if elapsed >= dynamicMaxDuration { break }

                if let frame = frameProvider(), let hand = frame.dominantHand {
                    let snapshot = Self.snapshotFromHand(hand, timestamp: elapsed)
                    currentRecordingFrames.append(snapshot)
                }

                recordingProgress = min(elapsed / dynamicMaxDuration, 1.0)
                try? await Task.sleep(for: .milliseconds(Int(frameInterval * 1000)))
            }

            finalizeDynamicRecording()
        }
    }

    func stopDynamicRecording() {
        recordingTimer?.cancel()
        finalizeDynamicRecording()
    }

    private func finalizeDynamicRecording() {
        if currentRecordingFrames.count >= 5 {
            let normalized = currentRecordingFrames.map { $0.normalized() }
            recordedSamples.append(normalized)
        }
        isRecording = false
    }

    // MARK: - Sample Management

    func clearAllSamples() {
        recordedSamples.removeAll()
        currentRecordingFrames.removeAll()
        recordingProgress = 0
    }

    func removeSample(at index: Int) {
        guard recordedSamples.indices.contains(index) else { return }
        recordedSamples.remove(at: index)
    }

    /// Build a GestureTemplate from recorded samples
    func buildTemplate(
        name: String,
        type: GestureType,
        action: GestureAction,
        threshold: Double = 0.08
    ) -> GestureTemplate? {
        guard !recordedSamples.isEmpty else { return nil }

        return GestureTemplate(
            name: name,
            type: type,
            action: action,
            samples: recordedSamples,
            matchThreshold: threshold
        )
    }

    // MARK: - Helpers

    static func snapshotFromHand(_ hand: HandData, timestamp: TimeInterval) -> LandmarkSnapshot {
        var joints: [JointID: LandmarkPoint] = [:]
        for (jointID, point) in hand.landmarks {
            joints[jointID] = point
        }
        return LandmarkSnapshot(joints: joints, timestamp: timestamp)
    }
}
