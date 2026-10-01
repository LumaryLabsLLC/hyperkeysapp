import EventEngine
import Foundation

/// Live, observable state of the hyper key, used for in-app feedback
/// (menu bar icon, the "try it" panel, flashing keys on the keyboard).
@MainActor
@Observable
public final class HyperKeyStatus {
    public var isHyperKeyDown = false
    public var isPaused = false
    /// The most recent hyper combo key pressed, bound or not.
    public private(set) var lastTriggeredKey: KeyCode?
    /// Total combos pressed this session; changes on every press, even repeats of the same key.
    public private(set) var triggerCount = 0
    /// Per-key press counts, so views can react only when *their* key fires.
    public private(set) var triggerCounts: [KeyCode: Int] = [:]

    public init() {}

    public func recordTrigger(_ keyCode: KeyCode) {
        lastTriggeredKey = keyCode
        triggerCount += 1
        triggerCounts[keyCode, default: 0] += 1
    }
}

extension KeyCode {
    /// Whether this key can be paired with the hyper key, given the current hyper key choice.
    public func isAssignable(hyperKey: KeyCode) -> Bool {
        self != hyperKey && isBindable && self != .capsLock && self != .f18
    }
}
