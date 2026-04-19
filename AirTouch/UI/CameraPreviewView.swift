import SwiftUI

struct CameraPreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let previewWidth: CGFloat = 640
    private let previewHeight: CGFloat = 480

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with close button
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .background(.black)

            // Camera feed with landmark overlay
            ZStack(alignment: .bottom) {
                if appState.cameraManager.isRunning {
                    CameraFeedLayer(session: appState.cameraManager.currentSession)
                        .frame(width: previewWidth, height: previewHeight)

                    if let frame = appState.currentFrame {
                        LandmarkOverlay(
                            frame: frame,
                            size: CGSize(width: previewWidth, height: previewHeight),
                            videoDimensions: appState.cameraManager.videoDimensions
                        )
                    }
                } else {
                    Rectangle()
                        .fill(.black)
                        .frame(width: previewWidth, height: previewHeight)
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
            .frame(width: previewWidth, height: previewHeight)
        }
        .background(.black)
        .onAppear { appState.isCameraPreviewOpen = true }
        .onDisappear { appState.isCameraPreviewOpen = false }
    }
}
