import SwiftUI

struct TrainingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var existingTemplate: GestureTemplate?

    @State private var step: TrainingStep = .configure
    @State private var gestureName = ""
    @State private var gestureType: GestureType = .staticPose
    @State private var gestureAction: GestureAction = .none
    @State private var threshold: Double = 0.08
    @State private var trainer = GestureTrainer()
    @State private var testResult: String?

    enum TrainingStep {
        case configure
        case record
        case test
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            stepIndicator
                .padding()

            Divider()

            // Content
            switch step {
            case .configure:
                configureStep
            case .record:
                recordStep
            case .test:
                testStep
            }

            Divider()

            // Navigation
            bottomBar
                .padding()
        }
        .onAppear {
            if let template = existingTemplate {
                gestureName = template.name
                gestureType = template.type
                gestureAction = template.action
                threshold = template.matchThreshold
                step = .record
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 24) {
            StepBadge(number: 1, title: "Configure", isActive: step == .configure, isComplete: step != .configure)
            StepBadge(number: 2, title: "Record", isActive: step == .record, isComplete: step == .test)
            StepBadge(number: 3, title: "Test", isActive: step == .test, isComplete: false)
        }
    }

    // MARK: - Configure Step

    private var configureStep: some View {
        Form {
            Section("Gesture Details") {
                TextField("Gesture Name", text: $gestureName)

                Picker("Action", selection: $gestureAction) {
                    ForEach(GestureAction.allSimpleActions, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                Picker("Type", selection: $gestureType) {
                    ForEach(GestureType.allCases, id: \.self) { type in
                        VStack(alignment: .leading) {
                            Text(type.rawValue)
                        }.tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Text(gestureType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Record Step

    private var recordStep: some View {
        VStack(spacing: 16) {
            // Camera preview with landmarks
            ZStack {
                CameraFeedLayer(session: appState.cameraManager.currentSession)
                    .frame(width: 320, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let frame = appState.currentFrame {
                    LandmarkOverlay(frame: frame, size: CGSize(width: 320, height: 240))
                }
            }
            .frame(width: 320, height: 240)

            // Instructions
            if trainer.isRecording {
                VStack(spacing: 8) {
                    ProgressView(value: trainer.recordingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 250)
                    Text("Recording... Hold your gesture steady")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(gestureType == .staticPose
                     ? "Hold your gesture and press Record"
                     : "Press and hold Record while performing the gesture")
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            // Record button
            HStack(spacing: 16) {
                Button {
                    if gestureType == .staticPose {
                        trainer.startStaticRecording {
                            appState.currentFrame
                        }
                    } else {
                        if trainer.isRecording {
                            trainer.stopDynamicRecording()
                        } else {
                            trainer.startDynamicRecording {
                                appState.currentFrame
                            }
                        }
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(trainer.isRecording ? .gray : .red)
                            .frame(width: 16, height: 16)
                        Text(trainer.isRecording ? "Recording..." : "Record")
                    }
                    .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(trainer.isRecording ? .gray : .red)
                .disabled(trainer.isRecording && gestureType == .staticPose)

                Button("Clear All") {
                    trainer.clearAllSamples()
                }
                .disabled(trainer.recordedSamples.isEmpty)
            }

            // Sample count
            Text("Samples recorded: \(trainer.sampleCount) / \(gestureType.recommendedSamples)")
                .font(.caption)
                .foregroundStyle(trainer.sampleCount >= gestureType.minimumSamples ? .green : .secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Test Step

    private var testStep: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraFeedLayer(session: appState.cameraManager.currentSession)
                    .frame(width: 320, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let frame = appState.currentFrame {
                    LandmarkOverlay(frame: frame, size: CGSize(width: 320, height: 240))
                }

                // Match feedback
                if let result = testResult {
                    Text(result)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.green.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 320, height: 240)

            Text("Perform your gesture to test it")
                .font(.callout)
                .foregroundStyle(.secondary)

            Slider(value: $threshold, in: 0.02...0.2, step: 0.01) {
                Text("Sensitivity")
            } minimumValueLabel: {
                Text("Strict").font(.caption2)
            } maximumValueLabel: {
                Text("Loose").font(.caption2)
            }
            .frame(width: 300)

            Spacer()
        }
        .padding()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }

            Spacer()

            switch step {
            case .configure:
                Button("Next") {
                    // Ensure camera is running for recording
                    if !appState.cameraManager.isRunning {
                        appState.cameraManager.startSession()
                    }
                    step = .record
                }
                .buttonStyle(.borderedProminent)
                .disabled(gestureName.isEmpty)

            case .record:
                Button("Back") { step = .configure }

                Button("Next") { step = .test }
                    .buttonStyle(.borderedProminent)
                    .disabled(trainer.sampleCount < gestureType.minimumSamples)

            case .test:
                Button("Back") { step = .record }

                Button("Save Gesture") {
                    saveGesture()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Save

    private func saveGesture() {
        if var existing = existingTemplate {
            // Update existing template
            existing.name = gestureName
            existing.action = gestureAction
            existing.matchThreshold = threshold
            existing.samples = trainer.recordedSamples
            appState.gestureStore.update(existing)
        } else {
            // Create new template
            if let template = trainer.buildTemplate(
                name: gestureName,
                type: gestureType,
                action: gestureAction,
                threshold: threshold
            ) {
                appState.gestureStore.add(template)
            }
        }
        dismiss()
    }
}

// MARK: - Step Badge

struct StepBadge: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? .blue : (isComplete ? .green : .gray.opacity(0.3)))
                    .frame(width: 24, height: 24)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}
