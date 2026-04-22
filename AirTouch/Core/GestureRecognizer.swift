import Foundation
import os.log

private let logger = Logger(subsystem: "com.airtouch", category: "gesture")

// MARK: - Gesture Event

struct GestureEvent: Sendable {
    let type: GestureEventType
    let position: CGPoint?
    let delta: Float?
}

enum GestureEventType: Sendable {
    case cursorMove
    case pinchStart(PinchFinger)
    case pinchEnd(PinchFinger)
    case scrollVertical
    case scrollHorizontal
    case dragStart
    case dragEnd
    case perfectSignStart
    case perfectSignEnd
    case openPalmRightClick
}

enum PinchFinger: String, Sendable, CaseIterable {
    case index
}

// MARK: - Gesture Recognizer

@Observable
final class GestureRecognizer: @unchecked Sendable {
    // Published state for UI
    private(set) var activePinch: PinchFinger?
    private(set) var isDragging = false
    private(set) var isScrolling = false
    var activeGestureName: String?

    // Settings
    var pinchThreshold: Double = 0.04
    var dragHoldDuration: TimeInterval = 0.8
    var scrollSpeed: Double = 1.0
    var invertScroll: Bool = false

    // Internal state
    private var processFrameCounter = 0
    private var pinchStates: [PinchFinger: PinchState] = [:]
    private var lastCursorPosition: CGPoint?
    private var cursorFreezePosition: CGPoint?

    // Perfect sign scroll state
    private var prevPerfectScrollPos: LandmarkPoint?
    private var wasPerfectScrolling = false

    // Open palm right-click state
    private var openPalmStartTime: Date?
    private var openPalmRightClickFired = false
    private var lastOpenPalmRightClickTime: Date?
    private let openPalmHoldDuration: TimeInterval = 1.0
    private let openPalmCooldown: TimeInterval = 1.5

    // Debounce
    private var lastGestureTime: [PinchFinger: Date] = [:]
    private let pinchCooldown: TimeInterval = 0.3
    private let releaseThresholdMultiplier: Float = 2.5

    // Gesture mode — mutual exclusivity
    private enum GestureMode: Equatable { case none, pointing, pinching, perfectSignScroll, openPalmRightClick }
    private var currentGestureMode: GestureMode = .none

    // MARK: - Process Frame

    func processFrame(_ frame: HandFrame, settings: AppSettings) -> [GestureEvent] {
        var events: [GestureEvent] = []

        processFrameCounter += 1

        pinchThreshold = settings.pinchThreshold
        dragHoldDuration = settings.dragHoldDuration
        scrollSpeed = settings.scrollSpeed
        invertScroll = settings.invertScroll

        guard let hand = frame.dominantHand else {
            endAllGestures(&events)
            prevPerfectScrollPos = nil
            wasPerfectScrolling = false
            currentGestureMode = .none
            return events
        }

        // Detect hand poses — only require index extended (not strict pointing)
        // so pinch detection works regardless of other finger states
        let isPointing = hand.isIndexExtended

        // Perfect sign (👌): thumb + index pinch with middle, ring, little all extended
        let isPerfectSign: Bool = {
            guard let thumbTip = hand.thumbTip, let indexTip = hand.indexTip else { return false }
            let dist = thumbTip.distance(to: indexTip)
            return dist < Float(pinchThreshold) * 2.0 && hand.isMiddleExtended && hand.isRingExtended && hand.isLittleExtended
        }()

        // Open palm: all fingers extended (no pinch)
        let isOpenPalm = hand.isOpenPalm && !isPerfectSign

        // Determine gesture mode — priority: perfectSign > openPalm > activePinch > pointing > none
        let newMode: GestureMode
        if isPerfectSign {
            newMode = .perfectSignScroll
        } else if isOpenPalm {
            newMode = .openPalmRightClick
        } else if activePinch != nil {
            newMode = .pinching
        } else if isPointing {
            newMode = .pointing
        } else {
            newMode = .none
        }

        let modeChanged = newMode != currentGestureMode
        if modeChanged {
            // Clean up previous mode's state
            if currentGestureMode == .pinching && newMode != .pinching {
                if let finger = activePinch {
                    events.append(GestureEvent(type: .pinchEnd(finger), position: lastCursorPosition, delta: nil))
                    activePinch = nil
                }
                if isDragging {
                    events.append(GestureEvent(type: .dragEnd, position: lastCursorPosition, delta: nil))
                    isDragging = false
                }
                pinchStates.removeAll()
            }
            currentGestureMode = newMode
        }

        // --- 1. Cursor movement — only in pointing or pinching mode (frozen during scroll/palm) ---
        if (newMode == .pointing || newMode == .pinching), let indexTip = hand.indexTip {
            let cursorPoint = CGPoint(x: CGFloat(indexTip.x), y: CGFloat(indexTip.y))
            let isCurrentlyPinching = activePinch != nil
            let freezing = !isCurrentlyPinching && shouldFreezeCursor(hand: hand)
            let position = freezing ? (cursorFreezePosition ?? cursorPoint) : cursorPoint
            if !freezing { cursorFreezePosition = cursorPoint }
            events.append(GestureEvent(type: .cursorMove, position: position, delta: nil))
            lastCursorPosition = position
        }

        // --- 2. Pinch detection (index only) — only in pointing or pinching mode ---
        if newMode == .pointing || newMode == .pinching {
            detectPinches(hand: hand, events: &events)
        }

        // --- 3. Drag detection — only in pinching mode ---
        if newMode == .pinching {
            detectDrag(events: &events)
        }

        // --- 4. Open palm (hold 1s) = right click ---
        if newMode == .openPalmRightClick {
            detectOpenPalmRightClick(events: &events)
        } else {
            openPalmStartTime = nil
            openPalmRightClickFired = false
        }

        // --- 5. Perfect sign (👌) = continuous scroll ---
        if newMode == .perfectSignScroll {
            if !wasPerfectScrolling {
                prevPerfectScrollPos = nil
                events.append(GestureEvent(type: .perfectSignStart, position: nil, delta: nil))
            }
            wasPerfectScrolling = true
            detectPerfectSignScroll(hand: hand, events: &events)
        } else {
            if wasPerfectScrolling {
                events.append(GestureEvent(type: .perfectSignEnd, position: nil, delta: nil))
            }
            wasPerfectScrolling = false
            prevPerfectScrollPos = nil
            if isScrolling { isScrolling = false }
        }

        return events
    }

    // MARK: - Pinch Detection

    private func detectPinches(hand: HandData, events: inout [GestureEvent]) {
        guard let thumbTip = hand.thumbTip else { return }

        let fingerTips: [(PinchFinger, LandmarkPoint?)] = [
            (.index, hand.indexTip)
        ]

        for (finger, tip) in fingerTips {
            guard let fingerTip = tip else { continue }

            let distance = thumbTip.distance(to: fingerTip)
            let threshold = Float(pinchThreshold)
            let state = pinchStates[finger] ?? PinchState()

            if distance < threshold * 1.5 {
                let newCount = state.consecutiveFrames + 1
                let alreadyConfirmed = state.isPinched
                let nowConfirmed = alreadyConfirmed || newCount >= 1
                pinchStates[finger] = PinchState(
                    isPinched: nowConfirmed,
                    consecutiveFrames: newCount,
                    startTime: state.startTime ?? Date()
                )

                if newCount >= 1 && !alreadyConfirmed {
                    if let lastTime = lastGestureTime[finger],
                       Date().timeIntervalSince(lastTime) < pinchCooldown {
                        continue
                    }
                    activePinch = finger
                    events.append(GestureEvent(type: .pinchStart(finger), position: lastCursorPosition, delta: nil))
                }
            } else if distance > threshold * releaseThresholdMultiplier {
                if state.isPinched {
                    if isDragging && finger == .index {
                        isDragging = false
                        events.append(GestureEvent(type: .dragEnd, position: lastCursorPosition, delta: nil))
                    }
                    events.append(GestureEvent(type: .pinchEnd(finger), position: lastCursorPosition, delta: nil))
                    lastGestureTime[finger] = Date()
                    if activePinch == finger { activePinch = nil }
                }
                pinchStates[finger] = PinchState()
            }
        }
    }

    // MARK: - Drag Detection

    private func detectDrag(events: inout [GestureEvent]) {
        guard let indexState = pinchStates[.index], indexState.isPinched,
              let startTime = indexState.startTime else {
            if isDragging {
                isDragging = false
                events.append(GestureEvent(type: .dragEnd, position: lastCursorPosition, delta: nil))
            }
            return
        }

        let holdDuration = Date().timeIntervalSince(startTime)
        if holdDuration >= dragHoldDuration && !isDragging {
            isDragging = true
            events.append(GestureEvent(type: .dragStart, position: lastCursorPosition, delta: nil))
        }
    }

    // MARK: - Open Palm Right Click

    private func detectOpenPalmRightClick(events: inout [GestureEvent]) {
        if openPalmStartTime == nil {
            openPalmStartTime = Date()
            openPalmRightClickFired = false
            activeGestureName = "Open Palm…"
        }

        guard !openPalmRightClickFired, let startTime = openPalmStartTime else { return }

        let holdDuration = Date().timeIntervalSince(startTime)
        if holdDuration >= openPalmHoldDuration {
            if let lastTime = lastOpenPalmRightClickTime,
               Date().timeIntervalSince(lastTime) < openPalmCooldown { return }
            openPalmRightClickFired = true
            lastOpenPalmRightClickTime = Date()
            activeGestureName = "Right Click"
            events.append(GestureEvent(type: .openPalmRightClick, position: lastCursorPosition, delta: nil))
        }
    }

    // MARK: - Perfect Sign Scroll (👌)

    private func detectPerfectSignScroll(hand: HandData, events: inout [GestureEvent]) {
        guard let middleTip = hand.middleTip else { return }

        defer { prevPerfectScrollPos = middleTip }

        guard let prev = prevPerfectScrollPos else { return }

        let deltaY = middleTip.y - prev.y
        let deltaX = middleTip.x - prev.x
        let minDelta: Float = 0.001

        if abs(deltaY) > minDelta {
            isScrolling = true
            let scrollDelta = (invertScroll ? deltaY : -deltaY) * Float(scrollSpeed) * 800.0
            events.append(GestureEvent(type: .scrollVertical, position: nil, delta: scrollDelta))
            activeGestureName = "Scroll"
        }

        if abs(deltaX) > minDelta {
            isScrolling = true
            let scrollDelta = deltaX * Float(scrollSpeed) * 800.0
            events.append(GestureEvent(type: .scrollHorizontal, position: nil, delta: scrollDelta))
            activeGestureName = "Scroll"
        }

        if abs(deltaY) <= minDelta && abs(deltaX) <= minDelta {
            isScrolling = false
        }
    }

    // MARK: - Cursor Freeze

    private func shouldFreezeCursor(hand: HandData) -> Bool {
        guard let thumbTip = hand.thumbTip, let indexTip = hand.indexTip else { return false }
        let distance = thumbTip.distance(to: indexTip)
        let threshold = Float(pinchThreshold)
        return distance < threshold * 1.5
    }

    // MARK: - Reset

    private func endAllGestures(_ events: inout [GestureEvent]) {
        if let finger = activePinch {
            events.append(GestureEvent(type: .pinchEnd(finger), position: lastCursorPosition, delta: nil))
            activePinch = nil
        }
        if isDragging {
            events.append(GestureEvent(type: .dragEnd, position: lastCursorPosition, delta: nil))
            isDragging = false
        }
        if wasPerfectScrolling {
            events.append(GestureEvent(type: .perfectSignEnd, position: nil, delta: nil))
            wasPerfectScrolling = false
        }
        isScrolling = false
        pinchStates.removeAll()
        openPalmStartTime = nil
        openPalmRightClickFired = false
        activeGestureName = nil
    }

    func reset() {
        activePinch = nil
        isDragging = false
        isScrolling = false
        activeGestureName = nil
        pinchStates.removeAll()
        prevPerfectScrollPos = nil
        lastGestureTime.removeAll()
        cursorFreezePosition = nil
        wasPerfectScrolling = false
        openPalmStartTime = nil
        openPalmRightClickFired = false
        currentGestureMode = .none
    }
}

// MARK: - Pinch State

private struct PinchState {
    var isPinched: Bool = false
    var consecutiveFrames: Int = 0
    var startTime: Date?
}
