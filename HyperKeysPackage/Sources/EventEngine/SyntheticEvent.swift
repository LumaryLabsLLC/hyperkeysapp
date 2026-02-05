import CoreGraphics

public enum SyntheticEvent: Sendable {
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
