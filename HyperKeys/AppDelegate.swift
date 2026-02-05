import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Toggle dock icon visibility. When `show` is true, the app appears in the Dock.
    static func setDockIconVisible(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we start as an accessory (no Dock icon), since LSUIElement = YES
    }
}
