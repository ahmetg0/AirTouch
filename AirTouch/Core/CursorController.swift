import CoreGraphics
import AppKit

// MARK: - Cursor Controller

@Observable
final class CursorController: @unchecked Sendable {
    private(set) var lastCursorPosition: CGPoint = .zero
    private(set) var isDragging = false

    var cursorSpeed: Double = 1.0
    var scrollSpeed: Double = 1.0
    var sensitivity: Double = 1.0
    var calibrationTransform: CalibrationTransform?

    // MARK: - Coordinate Mapping

    /// Convert a normalized camera point (0-1, origin bottom-left) to screen coordinates
    func mapToScreen(normalizedPoint: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame

        // Flip Y (Vision: bottom-left origin → screen: top-left origin)
        // Camera is already mirrored by CameraManager
        let flippedPoint = CGPoint(x: normalizedPoint.x, y: 1.0 - normalizedPoint.y)

        if let transform = calibrationTransform {
            return transform.apply(to: flippedPoint)
        }

        let transform = CalibrationTransform.simpleLinearMapping(
            screenWidth: screenFrame.width,
            screenHeight: screenFrame.height,
            sensitivity: sensitivity
        )
        return transform.apply(to: flippedPoint)
    }

    // MARK: - Cursor Movement

    func moveCursor(to normalizedPoint: CGPoint) {
        let screenPoint = mapToScreen(normalizedPoint: normalizedPoint)
        let clampedPoint = clampToScreen(screenPoint)
        lastCursorPosition = clampedPoint

        if isDragging {
            postMouseEvent(.leftMouseDragged, at: clampedPoint, button: .left)
        } else {
            postMouseEvent(.mouseMoved, at: clampedPoint, button: .left)
        }
    }

    // MARK: - Click Events

    func leftClick() {
        let pos = lastCursorPosition
        postMouseEvent(.leftMouseDown, at: pos, button: .left)
        postMouseEvent(.leftMouseUp, at: pos, button: .left)
    }

    func rightClick() {
        let pos = lastCursorPosition
        postMouseEvent(.rightMouseDown, at: pos, button: .right)
        postMouseEvent(.rightMouseUp, at: pos, button: .right)
    }

    func middleClick() {
        let pos = lastCursorPosition
        postMouseEvent(.otherMouseDown, at: pos, button: .center)
        postMouseEvent(.otherMouseUp, at: pos, button: .center)
    }

    func doubleClick() {
        let pos = lastCursorPosition
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: pos, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: 2)
            event.post(tap: .cghidEventTap)
        }
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: pos, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: 2)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Drag Events

    func startDrag() {
        isDragging = true
        postMouseEvent(.leftMouseDown, at: lastCursorPosition, button: .left)
    }

    func endDrag() {
        isDragging = false
        postMouseEvent(.leftMouseUp, at: lastCursorPosition, button: .left)
    }

    // MARK: - Scroll Events

    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        let scaledDeltaY = Int32(Double(deltaY) * scrollSpeed)
        let scaledDeltaX = Int32(Double(deltaX) * scrollSpeed)

        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 2, wheel1: scaledDeltaY, wheel2: scaledDeltaX, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keyboard Events

    func postKeyCombo(modifiers: [ModifierKey], keyCode: Int) {
        var flags = CGEventFlags()
        for mod in modifiers {
            flags.insert(mod.cgEventFlag)
        }

        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Action Execution

    func executeAction(_ action: GestureAction) {
        switch action {
        case .leftClick:
            leftClick()
        case .rightClick:
            rightClick()
        case .middleClick:
            middleClick()
        case .doubleClick:
            doubleClick()
        case .scrollUp:
            scroll(deltaY: -10)
        case .scrollDown:
            scroll(deltaY: 10)
        case .keyCombo(let modifiers, let keyCode):
            postKeyCombo(modifiers: modifiers, keyCode: keyCode)
        case .missionControl:
            // F3 key (Mission Control)
            postKeyCombo(modifiers: [], keyCode: 0x63) // kVK_F3 = 0x63 = 99
        case .appExpose:
            // Ctrl + Down Arrow
            postKeyCombo(modifiers: [.control], keyCode: 0x7D)
        case .launchpad:
            // F4 key (Launchpad on some Macs) — more reliable to use key combo
            postKeyCombo(modifiers: [], keyCode: 0x76) // kVK_F4 = 0x76 = 118
        case .spotlight:
            postKeyCombo(modifiers: [.command], keyCode: 0x31) // Cmd+Space
        case .playPause:
            postMediaKey(keyCode: 16) // NX_KEYTYPE_PLAY = 16
        case .nextTrack:
            postMediaKey(keyCode: 17) // NX_KEYTYPE_NEXT
        case .previousTrack:
            postMediaKey(keyCode: 18) // NX_KEYTYPE_PREVIOUS
        case .volumeUp:
            postMediaKey(keyCode: 0)  // NX_KEYTYPE_SOUND_UP
        case .volumeDown:
            postMediaKey(keyCode: 1)  // NX_KEYTYPE_SOUND_DOWN
        case .screenshotArea:
            postKeyCombo(modifiers: [.command, .shift], keyCode: 0x05) // Cmd+Shift+4
        case .lockScreen:
            postKeyCombo(modifiers: [.command, .control], keyCode: 0x0C) // Cmd+Ctrl+Q
        case .showDesktop:
            // F11 key
            postKeyCombo(modifiers: [], keyCode: 0x67) // kVK_F11 = 0x67 = 103
        case .none:
            break
        }
    }

    // MARK: - Private Helpers

    private func postMouseEvent(_ type: CGEventType, at position: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: position, mouseButton: button) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postMediaKey(keyCode: Int) {
        // Media keys use NX_KEYTYPE system events via CGEvent
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (keyCode << 16) | (0xa << 8),
            data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (keyCode << 16) | (0xb << 8),
            data2: -1
        )
        if let event = keyDown?.cgEvent {
            event.post(tap: .cghidEventTap)
        }
        if let event = keyUp?.cgEvent {
            event.post(tap: .cghidEventTap)
        }
    }

    private func clampToScreen(_ point: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return point }
        let frame = screen.frame
        return CGPoint(
            x: max(frame.minX, min(point.x, frame.maxX - 1)),
            y: max(frame.minY, min(point.y, frame.maxY - 1))
        )
    }
}
