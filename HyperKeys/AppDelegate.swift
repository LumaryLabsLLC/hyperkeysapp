import AppKit
import EventEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Toggle dock icon visibility. When `show` is true, the app appears in the Dock.
    static func setDockIconVisible(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        CapsLockRemapper.disable()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleSettingsWindow),
            name: Notification.Name.toggleSettingsWindow,
            object: nil
        )
    }

    @objc private func toggleSettingsWindow() {
        MainActor.assumeIsolated {
            if let window = NSApp.windows.first(where: { $0.title == "HyperKeys Settings" }) {
                if window.isVisible {
                    window.close()
                } else {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                AppState.openSettingsWindow?()
            }
        }
    }
}
