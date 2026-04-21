import SwiftUI
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.airtouch", category: "pipeline")

// MARK: - App State

@MainActor
@Observable
final class AppState {
    // Sub-managers
    let settings = AppSettings()
    let cameraManager = CameraManager()
    let cursorController = CursorController()
    let gestureRecognizer = GestureRecognizer()
    let permissionManager = PermissionManager()
    let gestureStore = GestureStore()

    // Tracking state
    private(set) var isTracking = false
    private(set) var currentFrame: HandFrame?
    private(set) var framesPerSecond: Int = 0
    private(set) var handsDetected: Int = 0

    /// When true, cursor/gesture control is paused but camera+vision pipeline
    /// keeps running so `currentFrame` is still updated (needed for calibration).
    var isCalibrating = false

    /// When true, cursor/gesture events are suppressed but the camera+vision
    /// pipeline keeps running so the preview displays live landmarks.
    var isCameraPreviewOpen = false

    // Pipeline tasks
    private var fpsCounterTask: Task<Void, Never>?
    private var frameCount = 0

    // MARK: - Menu Bar Icon

    var menuBarIconName: String {
        isTracking ? "hand.raised.fill" : "hand.raised"
    }

    var statusText: String {
        if !permissionManager.isCameraAuthorized {
            return "Camera permission required"
        }
        if !permissionManager.accessibilityGranted {
            return "Accessibility permission required"
        }
        if isTracking {
            return "Tracking Active (\(framesPerSecond) fps, \(handsDetected) hand\(handsDetected == 1 ? "" : "s"))"
        }
        return "Tracking Paused"
    }

    // MARK: - Initialization

    private var hasInitialized = false

    func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Load calibration and sync settings — fast UserDefaults reads only.
        if let calibData = settings.calibrationData {
            cursorController.calibrationTransform = CalibrationTransform(matrix: calibData.matrix)
        }
        syncSettings()
    }

    // MARK: - Toggle Tracking

    func toggleTracking() {
        if isTracking {
            stopPipeline()
        } else {
            startPipeline()
        }
    }

    // MARK: - Pipeline

    func startPipeline() {
        guard permissionManager.isCameraAuthorized else { return }
        guard !isTracking else { return }

        logger.info("Starting pipeline — accessibilityGranted=\(self.permissionManager.accessibilityGranted)")

        syncSettings()
        isTracking = true

        // Start FPS counter
        fpsCounterTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                framesPerSecond = frameCount
                frameCount = 0
            }
        }

        let frameBox = LatestFrameBox()
        weak let weakSelf = self
        let engine = HandTrackingEngine()
        let smoother = LandmarkSmoother(minCutoff: settings.smoothingMinCutoff, beta: settings.smoothingBeta)

        // Flag to prevent stacking: when true, a main-thread dispatch is already
        // queued and hasn't started processing yet — skip further dispatches.
        let processingFlag = AtomicFlag()

        cameraManager.onFrame = { sampleBuffer in
            autoreleasepool {
                let timestamp = CACurrentMediaTime()
                let frame = engine.processFrame(sampleBuffer, timestamp: timestamp)

                if let frame {
                    let smoothed = smoother.smoothFrame(frame)
                    frameBox.store(smoothed)
                } else {
                    smoother.reset()
                    frameBox.clear()
                }

                // Drop this frame if the main thread hasn't finished processing
                // the previous one yet — prevents event stacking.
                guard processingFlag.testAndSet() else { return }

                DispatchQueue.main.async {
                    defer { processingFlag.clear() }

                    // Bridge GCD main queue → MainActor isolation so the
                    // runtime doesn't trap on @MainActor property access.
                    MainActor.assumeIsolated {
                        guard let appState = weakSelf, appState.isTracking else { return }

                        if let latestFrame = frameBox.load() {
                            appState.frameCount += 1
                            appState.handsDetected = latestFrame.hands.count
                            appState.currentFrame = latestFrame

                            // Skip gesture recognition during calibration or preview
                            guard !appState.isCalibrating && !appState.isCameraPreviewOpen else { return }

                            let events = appState.gestureRecognizer.processFrame(latestFrame, settings: appState.settings)

                            for event in events {
                                appState.handleGestureEvent(event)
                            }
                        } else {
                            appState.handsDetected = 0
                            appState.currentFrame = nil
                        }
                    }
                }
            }
        }

        // Start camera
        cameraManager.startSession()
    }

    func stopPipeline() {
        fpsCounterTask?.cancel()
        fpsCounterTask = nil

        cameraManager.stopSession()
        gestureRecognizer.reset()

        isTracking = false
        handsDetected = 0
        framesPerSecond = 0
        currentFrame = nil
    }

    // MARK: - Event Handling

    private func handleGestureEvent(_ event: GestureEvent) {
        guard permissionManager.accessibilityGranted else {
            logger.warning("Event dropped — accessibility not granted")
            return
        }

        switch event.type {
        case .cursorMove:
            if let pos = event.position {
                cursorController.moveCursor(to: pos)
            }

        case .pinchStart(let finger):
            let action = actionForPinch(finger)
            if action != .none && !gestureRecognizer.isDragging {
                cursorController.executeAction(action)
            }
            gestureRecognizer.activeGestureName = "Pinch (\(finger.rawValue.capitalized))"

        case .pinchEnd:
            gestureRecognizer.activeGestureName = nil

        case .scrollVertical:
            if let delta = event.delta {
                cursorController.scroll(deltaY: Int32(delta))
            }
            gestureRecognizer.activeGestureName = "Scroll"

        case .scrollHorizontal:
            if let delta = event.delta {
                cursorController.scroll(deltaY: 0, deltaX: Int32(delta))
            }

        case .dragStart:
            cursorController.startDrag()
            gestureRecognizer.activeGestureName = "Drag"

        case .dragEnd:
            cursorController.endDrag()
            gestureRecognizer.activeGestureName = nil

        case .perfectSignStart, .perfectSignEnd:
            break // scroll events come through scrollVertical/scrollHorizontal

        case .openPalmRightClick:
            cursorController.rightClick()
        }
    }

    private func actionForPinch(_ finger: PinchFinger) -> GestureAction {
        switch finger {
        case .index: return .leftClick
        case .middle: return .rightClick
        }
    }

    // MARK: - Settings Sync

    func syncSettings() {
        cursorController.cursorSpeed = settings.cursorSpeed
        cursorController.scrollSpeed = settings.scrollSpeed
        cursorController.sensitivity = settings.sensitivity
    }
}

// MARK: - Latest Frame Box

/// Thread-safe box for passing the latest processed frame from the camera queue to the main thread.
nonisolated final class LatestFrameBox: @unchecked Sendable {
    private var _frame: HandFrame?
    private var _lock = os_unfair_lock()

    func store(_ frame: HandFrame) {
        os_unfair_lock_lock(&_lock)
        _frame = frame
        os_unfair_lock_unlock(&_lock)
    }

    func clear() {
        os_unfair_lock_lock(&_lock)
        _frame = nil
        os_unfair_lock_unlock(&_lock)
    }

    func load() -> HandFrame? {
        os_unfair_lock_lock(&_lock)
        let frame = _frame
        os_unfair_lock_unlock(&_lock)
        return frame
    }
}

// MARK: - Atomic Flag

/// Thread-safe boolean flag for cross-queue "is main thread still processing?" checks.
/// Prevents gesture event stacking when frame processing can't keep up.
nonisolated final class AtomicFlag: @unchecked Sendable {
    private var _value: Int32 = 0
    private var _lock = os_unfair_lock()

    /// Attempt to set the flag. Returns true if it was previously clear (i.e. we "won").
    /// Returns false if already set (main thread is still busy — drop this frame).
    func testAndSet() -> Bool {
        os_unfair_lock_lock(&_lock)
        let wasZero = _value == 0
        if wasZero { _value = 1 }
        os_unfair_lock_unlock(&_lock)
        return wasZero
    }

    /// Clear the flag (main thread is done processing).
    func clear() {
        os_unfair_lock_lock(&_lock)
        _value = 0
        os_unfair_lock_unlock(&_lock)
    }
}
