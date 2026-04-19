import SwiftUI

// MARK: - Landmark Overlay

/// Draws hand landmarks and skeleton connections on a Canvas
struct LandmarkOverlay: View {
    let frame: HandFrame
    let size: CGSize
    /// Actual video capture dimensions — needed to compute the correct mapping
    /// for the preview layer's `resizeAspectFill` gravity.
    var videoDimensions: CGSize = CGSize(width: 640, height: 480)

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

    /// Convert normalized Vision coordinates to screen coordinates for the overlay.
    ///
    /// The preview layer uses `resizeAspectFill`, which scales the video uniformly
    /// to fill the view and crops any overflow. When the video aspect ratio differs
    /// from the view (e.g. 16:9 camera in a 4:3 view), a naive `x * width` mapping
    /// drifts at edges because the visible video is a cropped subset of [0,1].
    ///
    /// This method computes the full display rect (potentially larger than the view)
    /// and maps landmarks into it, so the overlay aligns with the cropped preview.
    private func convertToScreen(_ point: LandmarkPoint, in size: CGSize) -> CGPoint {
        let videoAspect = videoDimensions.width / videoDimensions.height
        let viewAspect  = size.width / size.height

        let displayWidth: CGFloat
        let displayHeight: CGFloat

        if videoAspect > viewAspect {
            // Video wider than view → scale to fill height, sides are cropped
            displayHeight = size.height
            displayWidth  = size.height * videoAspect
        } else {
            // Video taller than view → scale to fill width, top/bottom cropped
            displayWidth  = size.width
            displayHeight = size.width / videoAspect
        }

        // Offset centers the (possibly oversized) display rect in the view
        let offsetX = (size.width  - displayWidth)  / 2
        let offsetY = (size.height - displayHeight) / 2

        return CGPoint(
            x: offsetX + CGFloat(point.x) * displayWidth,
            y: offsetY + (1.0 - CGFloat(point.y)) * displayHeight
        )
    }
}
