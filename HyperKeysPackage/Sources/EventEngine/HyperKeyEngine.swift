import CoreGraphics
import Foundation

/// Callback when a hyper key combo is activated.
public typealias HyperKeyAction = @Sendable (KeyCode) -> Void

/// File logger shared with EventTapManager.
private func engineLog(_ message: String) {
    let path = "/tmp/hyperkeys.log"
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "\(ts) [Engine] \(message)\n"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

/// State machine that turns a configurable key into a Hyper key.
///
/// States:
///   - idle: normal operation
///   - potentialHyper: hyper key was pressed, waiting to see if another key follows
///   - hyperActive: hyper key is held and at least one other key was pressed
public final class HyperKeyEngine: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case potentialHyper(timestamp: CFAbsoluteTime)
        case hyperActive
    }

    private let tapTimeout: CFAbsoluteTime = 0.2 // 200ms
    private var state: State = .idle
    public var hyperKeyCode: UInt16 = KeyCode.tab.rawValue
    public var onHyperKeyActivated: HyperKeyAction?

    public init() {}

    /// Process a CGEvent. Returns nil to suppress the event, or the event to pass through.
    public func process(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isHyperKey = keyCode == hyperKeyCode
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch (state, type) {

        // IDLE: Hyper key down → enter potential hyper state
        case (.idle, .keyDown) where isHyperKey && !isRepeat:
            engineLog("idle → potentialHyper (hyperKey down, keyCode=\(keyCode))")
            state = .potentialHyper(timestamp: CFAbsoluteTimeGetCurrent())
            return nil // suppress hyper key down

        // IDLE: Any other key → pass through
        case (.idle, _):
            return event

        // POTENTIAL HYPER: Another key pressed → activate hyper mode
        case (.potentialHyper, .keyDown) where !isHyperKey && !isRepeat:
            state = .hyperActive
            if let kc = KeyCode(rawValue: keyCode) {
                engineLog("potentialHyper → hyperActive: Hyper+\(kc.displayLabel) (keyCode=\(keyCode))")
                onHyperKeyActivated?(kc)
            } else {
                engineLog("potentialHyper → hyperActive: unknown keyCode=\(keyCode)")
            }
            return nil // suppress the combo key

        // POTENTIAL HYPER: Hyper key up → was it a quick tap?
        case (.potentialHyper(let timestamp), .keyUp) where isHyperKey:
            let elapsed = CFAbsoluteTimeGetCurrent() - timestamp
            state = .idle
            engineLog("potentialHyper → idle (hyperKey up, elapsed=\(String(format: "%.3f", elapsed))s, tap=\(elapsed < tapTimeout))")
            if elapsed < tapTimeout {
                // Quick tap — emit the original key
                SyntheticEvent.postKeyPress(keyCode: hyperKeyCode)
            }
            return nil // suppress key up (we emitted synthetic if needed)

        // POTENTIAL HYPER: Hyper key repeat → treat as hyper hold
        case (.potentialHyper, .keyDown) where isHyperKey && isRepeat:
            state = .hyperActive
            return nil

        // POTENTIAL HYPER: flags changed or other events → pass through
        case (.potentialHyper, _):
            return event

        // HYPER ACTIVE: Another key pressed → execute action
        case (.hyperActive, .keyDown) where !isHyperKey && !isRepeat:
            if let kc = KeyCode(rawValue: keyCode) {
                engineLog("hyperActive: repeat Hyper+\(kc.displayLabel) (keyCode=\(keyCode))")
                onHyperKeyActivated?(kc)
            }
            return nil

        // HYPER ACTIVE: Hyper key up → return to idle
        case (.hyperActive, .keyUp) where isHyperKey:
            engineLog("hyperActive → idle (hyperKey up)")
            state = .idle
            return nil // swallow hyper key up

        // HYPER ACTIVE: Other key up → suppress
        case (.hyperActive, .keyUp) where !isHyperKey:
            return nil

        // HYPER ACTIVE: Hyper key repeat → suppress
        case (.hyperActive, .keyDown) where isHyperKey:
            return nil

        // Everything else → pass through
        default:
            return event
        }
    }

    public func reset() {
        state = .idle
    }

    public var currentState: State { state }
}
