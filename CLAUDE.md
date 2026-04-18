# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

AirTouch is a macOS menu-bar app that turns camera-based hand tracking into mouse and keyboard events. Bundle ID `com.ahmetgundogdu.AirTouch`, Swift 5, `MACOSX_DEPLOYMENT_TARGET = 26.2`. There is no package manifest, Makefile, or test target — the project is pure Xcode.

## Build & Run

```bash
# Open in Xcode
open AirTouch.xcodeproj

# Command-line build (Debug)
xcodebuild -project AirTouch.xcodeproj -scheme AirTouch -configuration Debug build

# Clean
xcodebuild -project AirTouch.xcodeproj -scheme AirTouch clean
```

The app requires two runtime permissions to function: **Camera** (checked by `PermissionManager`) and **Accessibility** (checked via `AXIsProcessTrusted`). Accessibility must be re-granted every time the built binary changes location/signature; `AppState.initialize()` starts a polling task to pick this up without a relaunch.

There are no unit/UI tests in the repo.

## Architecture

The app is a SwiftUI `MenuBarExtra` + three `Window` scenes (settings, camera preview, onboarding) defined in `AirTouchApp.swift`. All scenes share a single `@Observable AppState` injected via `.environment`.

### Frame pipeline (the hot path)

`AppState.startPipeline()` wires together the real-time loop. Understanding this pipeline is essential before changing anything in `Core/`:

1. **`CameraManager`** runs an `AVCaptureSession` on a background queue and invokes the `onFrame` closure per `CMSampleBuffer`. The camera feed is horizontally mirrored at capture time so Vision coordinates are already in "user space".
2. **`HandTrackingEngine`** runs synchronously on the camera queue using a single long-lived `VNSequenceRequestHandler` + `VNDetectHumanHandPoseRequest` (max 2 hands, confidence ≥ 0.6). It returns a `HandFrame` or `nil`. Keeping this on the camera queue is intentional — moving Vision off it will invalidate the sample buffer.
3. **`LatestFrameBox`** (os_unfair_lock) holds only the most recent frame; old frames are dropped rather than queued.
4. **`AtomicFlag` (testAndSet)** gates the dispatch to the main thread. If the main actor is still processing a previous frame, the camera closure *drops* the new frame instead of stacking `DispatchQueue.main.async` blocks. Any change here risks cursor lag / event stacking — preserve the "one in flight at a time" invariant.
5. On the main actor, `GestureRecognizer.processFrame` converts the `HandFrame` into zero or more `GestureEvent`s.
6. `AppState.handleGestureEvent` dispatches events to `CursorController`, which posts `CGEvent`s. Accessibility permission is re-checked here; events are dropped (with a log line) if it is revoked mid-session.

`isCalibrating` is a special pause: the camera/vision pipeline keeps running so `currentFrame` updates for the calibration UI, but gesture recognition and cursor events are suppressed.

### Gesture recognition model

`Core/GestureRecognizer.swift` implements **only** the two built-in, hardcoded gestures and owns their state machine:

- **Pinch cursor** — thumb+index pinch moves the cursor via `indexTip`; opening past `pinchThreshold * releaseThresholdMultiplier` emits `leftClick`. Uses `pinchConfirmFrames` debounce, a cooldown timer, and a "freeze" state (`shouldFreezeCursor`) to stop cursor drift at the moment of click.
- **Perfect sign scroll (👌)** — thumb+index pinched *while* middle/ring/little are extended; `middleTip` motion becomes scroll deltas.

The two modes are mutually exclusive via `GestureMode` with priority `perfectSign > pinchCursor > none`. Adding a third built-in gesture means extending this enum and the mode-transition logic, not bolting on a parallel detector.

`Gestures/` (`GestureMatcher`, `GestureTrainer`, `GestureStore`) is a **separate**, user-trainable gesture system with persisted `GestureTemplate`s, static-pose + DTW dynamic-motion matching, and per-template cooldowns. As of now this subsystem is **not wired into `AppState`'s live pipeline** — it exists for the Training UI (`UI/Training/TrainingView.swift`) and the custom-gesture list (`UI/Settings/GestureListView.swift`). If you're plumbing custom gestures into live tracking, the integration point is `AppState.startPipeline`'s main-thread closure, alongside the existing `gestureRecognizer.processFrame` call.

### Coordinate spaces

There are three and mixing them up is the most common bug vector:

1. **Vision space** — normalized `[0,1]`, origin bottom-left. This is what `LandmarkPoint` stores.
2. **Screen space** — AppKit points, origin top-left. `CursorController.mapToScreen` flips Y and applies either the saved `CalibrationTransform` or `CalibrationTransform.simpleLinearMapping(sensitivity:)`.
3. **Calibrated screen space** — produced by `CalibrationTransform` (a homography matrix persisted in `AppSettings.calibrationData`). Loaded on launch in `AppState.initialize`.

The camera is pre-mirrored, so `CursorController` only flips Y, never X.

### Settings & persistence

`AppSettings` is an `@Observable` façade over `UserDefaults` with `.clamped(to:default:)` on every getter — when adding a new setting, follow this pattern so a zeroed default doesn't collapse the value to an invalid range. `resetToDefaults()` nukes the entire persistent domain, so anything you add there will be reset too. `syncSettings()` is the single point that pushes settings into `CursorController` before each pipeline start; add new cursor-affecting settings there.

### UI layout

- `UI/MenuBarView.swift` — content of the `MenuBarExtra` dropdown.
- `UI/Settings/` — tabbed settings window (General, Controls, Calibration, Gestures).
- `UI/OnboardingView.swift` — first-run flow gated by `AppSettings.hasCompletedOnboarding`.
- `UI/Helpers/CameraFeedLayer.swift` + `LandmarkOverlay.swift` — camera preview rendering and skeleton drawing (bone lists live in `HandFrame.FingerBone`).

The settings window toggles `NSApp.setActivationPolicy` between `.regular` and `.accessory` on appear/disappear so the app behaves as a menu-bar utility except while its window is open.

## Conventions worth preserving

- Types touched by the camera queue are marked `nonisolated` + `@unchecked Sendable` and guard their state with `os_unfair_lock` or atomics (`LatestFrameBox`, `AtomicFlag`, `HandTrackingEngine`). Do not introduce Swift actors into the hot path — the current design is deliberately lock-based for latency.
- `@Observable` (not `ObservableObject`) is used throughout; views take state via `.environment(appState)` / `@Environment(AppState.self)`.
- Logging uses `os.Logger` under subsystem `com.airtouch` with categories like `pipeline` and `gesture`.
- `JointID` mirrors `VNHumanHandPoseObservation.JointName` so that landmark data is `Codable` (needed for `GestureTemplate` persistence). Keep them in sync when Vision adds joints.
