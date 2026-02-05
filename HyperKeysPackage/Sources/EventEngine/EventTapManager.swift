import CoreGraphics
import Foundation

/// Simple file logger for debugging event tap issues.
nonisolated(unsafe) private let debugLog: @Sendable (String) -> Void = {
    let path = "/tmp/hyperkeys.log"
    // Truncate on first write each launch
    FileManager.default.createFile(atPath: path, contents: nil)
    return { message in
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "\(ts) \(message)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    }
}()

/// Manages the CGEventTap for intercepting keyboard events.
public final class EventTapManager: @unchecked Sendable {
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    public let engine = HyperKeyEngine()

    private var isRunning = false

    public init() {}

    /// Whether the tap failed to create (permission issue).
    public private(set) var needsPermission = false

    public func start() {
        guard !isRunning else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue)

        debugLog("Creating event tap... hyperKeyCode=\(engine.hyperKeyCode)")

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("FAILED to create event tap — requesting Input Monitoring permission")
            needsPermission = true
            CGRequestListenEventAccess()
            return
        }

        machPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // Add to the main run loop (always running in an AppKit app)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        needsPermission = false
        debugLog("Event tap created and added to main run loop, enabled=\(CGEvent.tapIsEnabled(tap: tap))")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        machPort = nil
        runLoopSource = nil
    }

    /// Re-enable the tap if the system disabled it.
    func reenable() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }
}

nonisolated(unsafe) private var callbackLogCounter: Int = 0

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()

    let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    callbackLogCounter += 1

    // Always log hyper key (Tab=48) events; log first 100 of others
    if kc == manager.engine.hyperKeyCode || callbackLogCounter <= 100 {
        debugLog("CB #\(callbackLogCounter): type=\(type.rawValue) keyCode=\(kc)")
    }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        debugLog("Event tap was disabled (type=\(type.rawValue)), re-enabling")
        manager.reenable()
        return Unmanaged.passRetained(event)
    }

    if let result = manager.engine.process(type: type, event: event) {
        return Unmanaged.passRetained(result)
    }
    return nil
}
