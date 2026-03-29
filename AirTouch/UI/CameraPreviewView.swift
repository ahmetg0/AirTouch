import SwiftUI

struct CameraPreviewView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Camera feed with landmark overlay
            ZStack(alignment: .bottom) {
                if appState.cameraManager.isRunning {
                    CameraFeedLayer(session: appState.cameraManager.currentSession)
                        .frame(width: 320, height: 240)

                    if let frame = appState.currentFrame {
                        LandmarkOverlay(frame: frame, size: CGSize(width: 320, height: 240))
                    }
                } else {
                    Rectangle()
                        .fill(.black)
                        .frame(width: 320, height: 240)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.title)
                                    .foregroundStyle(.gray)
                                Text("Camera not active")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }
                }

                // Bottom status bar
                HStack {
                    // Active gesture indicator
                    if let gestureName = appState.gestureRecognizer.activeGestureName {
                        Text(gestureName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }

                    Spacer()

                    // FPS and hand count
                    Text("\(appState.framesPerSecond) fps")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))

                    if appState.handsDetected > 0 {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("\(appState.handsDetected)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5))
            }
            .frame(width: 320, height: 240)
        }
        .background(.black)
    }
}
