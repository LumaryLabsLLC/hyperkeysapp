import Foundation

/// Remaps Caps Lock → F18 at the IOKit level via hidutil so it sends
/// normal keyDown/keyUp events instead of flagsChanged.
public enum CapsLockRemapper {
    // HID usage IDs (keyboard page 0x07)
    private static let capsLockHID: UInt = 0x700000039
    private static let f18HID: UInt = 0x70000006D

    /// Apply the Caps Lock → F18 remapping.
    public static func enable() {
        let json = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(capsLockHID),"HIDKeyboardModifierMappingDst":\(f18HID)}]}
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
