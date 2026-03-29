import SwiftUI

// MARK: - Landmark Overlay

/// Draws hand landmarks and skeleton connections on a Canvas
struct LandmarkOverlay: View {
    let frame: HandFrame
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            for hand in frame.hands {
                drawSkeleton(context: &context, hand: hand, size: canvasSize)
                drawJoints(context: &context, hand: hand, size: canvasSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Draw Skeleton Lines

    private func drawSkeleton(context: inout GraphicsContext, hand: HandData, size: CGSize) {
        for finger in FingerBone.allFingers {
            var path = Path()
            var started = false

            for jointID in finger {
                guard let point = hand.landmarks[jointID] else { continue }
                let screenPoint = convertToScreen(point, in: size)

                if !started {
                    path.move(to: screenPoint)
                    started = true
                } else {
                    path.addLine(to: screenPoint)
                }
            }

            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        }

        // Draw palm connections (MCP joints)
        let mcpJoints: [JointID] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        var palmPath = Path()
        var palmStarted = false
        for jointID in mcpJoints {
            guard let point = hand.landmarks[jointID] else { continue }
            let screenPoint = convertToScreen(point, in: size)
            if !palmStarted {
                palmPath.move(to: screenPoint)
                palmStarted = true
            } else {
                palmPath.addLine(to: screenPoint)
            }
        }
        context.stroke(palmPath, with: .color(.white.opacity(0.5)), lineWidth: 1.0)
    }

    // MARK: - Draw Joint Dots

    private func drawJoints(context: inout GraphicsContext, hand: HandData, size: CGSize) {
        for (jointID, point) in hand.landmarks {
            let screenPoint = convertToScreen(point, in: size)

            let dotSize: CGFloat
            let color: Color

            switch jointID {
            case .indexTip:
                // Cursor control finger — green, larger
                dotSize = 6
                color = .green
            case .thumbTip:
                // Thumb — yellow for pinch feedback
                dotSize = 5
                color = .yellow
            case .middleTip, .ringTip, .littleTip:
                dotSize = 4
                color = .white
            default:
                dotSize = 3
                color = .white.opacity(0.8)
            }

            let rect = CGRect(
                x: screenPoint.x - dotSize / 2,
                y: screenPoint.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert normalized Vision coordinates to screen coordinates for the overlay
    /// Vision: (0,0) bottom-left to (1,1) top-right
    /// Screen: (0,0) top-left to (width,height) bottom-right
    /// Camera is already mirrored by CameraManager/PreviewLayer
    private func convertToScreen(_ point: LandmarkPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(point.x) * size.width,
            y: (1.0 - CGFloat(point.y)) * size.height
        )
    }
}
