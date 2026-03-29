import Vision
import CoreMedia

// MARK: - Hand Tracking Engine

/// Processes camera frames for hand pose detection.
/// Uses a single VNSequenceRequestHandler for efficient continuous video processing.
nonisolated final class HandTrackingEngine: @unchecked Sendable {
    private let confidenceThreshold: Float = 0.6
    private let sequenceHandler = VNSequenceRequestHandler()

    /// Process a camera frame synchronously and return detected hand poses.
    /// Must be called on the camera output queue to keep the sample buffer valid.
    func processFrame(_ sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) -> HandFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            return nil
        }

        guard let results = request.results, !results.isEmpty else {
            return nil
        }

        let hands = results.compactMap { observation -> HandData? in
            extractHandData(from: observation, timestamp: timestamp)
        }

        guard !hands.isEmpty else { return nil }

        return HandFrame(timestamp: timestamp, hands: hands)
    }

    // MARK: - Private

    private func extractHandData(
        from observation: VNHumanHandPoseObservation,
        timestamp: TimeInterval
    ) -> HandData? {
        var landmarks: [JointID: LandmarkPoint] = [:]

        for jointID in JointID.allCases {
            guard let point = try? observation.recognizedPoint(jointID.visionJointName) else {
                continue
            }
            guard point.confidence >= confidenceThreshold else {
                continue
            }
            landmarks[jointID] = LandmarkPoint(
                x: Float(point.location.x),
                y: Float(point.location.y),
                confidence: point.confidence
            )
        }

        // Need at minimum the wrist and a few fingertips to be useful
        guard landmarks[.wrist] != nil,
              landmarks.count >= 10 else {
            return nil
        }

        let chirality: HandChirality
        switch observation.chirality {
        case .left: chirality = .left
        case .right: chirality = .right
        default: chirality = .unknown
        }

        return HandData(
            chirality: chirality,
            landmarks: landmarks,
            timestamp: timestamp
        )
    }
}
