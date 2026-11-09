import Foundation

/// Remaps the hyper key to F18 at the IOKit level via hidutil, for keys that wouldn't otherwise
/// send plain keyDown/keyUp events: Caps Lock toggles capitals, and a modifier only sends
/// flagsChanged. As F18 they work like any other hyper key.
public enum HyperKeyRemapper {
    // HID usage IDs (keyboard page 0x07)
    private static let f18HID: UInt = 0x70000006D

    /// The HID usage of a key that needs remapping to work as the hyper key, or nil.
    static func hidUsage(for key: KeyCode) -> UInt? {
        switch key {
        case .capsLock: 0x700000039
        case .rightControl: 0x7000000E4
        case .rightShift: 0x7000000E5
        case .rightOption: 0x7000000E6
        case .rightCommand: 0x7000000E7
        default: nil
        }
    }

    /// The key code the event tap sees when `key` is the hyper key.
    public static func tapKeyCode(for key: KeyCode) -> UInt16 {
        key.isRemappedToF18 ? KeyCode.f18.rawValue : key.rawValue
    }

    /// Remaps `key` to F18 if it needs it, otherwise removes the remapping.
    public static func apply(for key: KeyCode) {
        guard let source = hidUsage(for: key) else {
            disable()
            return
        }
        let json = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(source),"HIDKeyboardModifierMappingDst":\(f18HID)}]}
        """
        run(["hidutil", "property", "--set", json])
    }

    /// Remove all hidutil key remappings.
    public static func disable() {
        let json = """
        {"UserKeyMapping":[]}
        """
        run(["hidutil", "property", "--set", json])
    }

    @discardableResult
    private static func run(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension KeyCode {
    /// Whether this key arrives as F18 while it's the hyper key (Caps Lock and right-side modifiers).
    public var isRemappedToF18: Bool {
        HyperKeyRemapper.hidUsage(for: self) != nil
    }
}
