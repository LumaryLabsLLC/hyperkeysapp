import CoreGraphics

public enum SyntheticEvent: Sendable {
    /// Stamped on keys HyperKeys types itself (pastes, keyword deletes), so it can ignore them.
    public static let marker: Int64 = 0x4859_4B53 // "HYKS"

    /// Presses a key in the frontmost app, marked as HyperKeys' own.
    public static func press(keyCode: CGKeyCode, flags: CGEventFlags = [], tap: CGEventTapLocation = .cghidEventTap) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: tap)
        }
    }

    /// Post a synthetic key down + key up for the given key code with optional modifier flags.
    public static func postKeyPress(keyCode: UInt16, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Post just a key down event.
    public static func postKeyDown(keyCode: UInt16, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            event.flags = flags
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Post just a key up event.
    public static func postKeyUp(keyCode: UInt16, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            event.flags = flags
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
