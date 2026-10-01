import AppKit
import EventEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Toggle dock icon visibility. When `show` is true, the app appears in the Dock.
    @MainActor
    static func setDockIconVisible(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            NSApp.activate()
        }
    }

    @MainActor
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(AppState.mainWindowID) == true }
    }

    /// Puts the main window in front of every other app's windows.
    /// `NSApp.activate()` alone is only a request on macOS 14+ and can lose to the app the user
    /// was just in, which left the window opening behind everything.
    @MainActor
    static func bringMainWindowToFront() {
        NSApp.activate()
        // `openWindow` may only create the window on the next turn of the run loop.
        DispatchQueue.main.async {
            guard let window = mainWindow else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
        }
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

    /// Re-launching the app (Finder, Spotlight, Dock) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppState.openMainWindow?()
        }
        return true
    }

    @objc private func toggleSettingsWindow() {
        MainActor.assumeIsolated {
            if let window = Self.mainWindow, window.isVisible {
                // Close only when it's already in front; otherwise bring it forward.
                if window.isKeyWindow, NSApp.isActive {
                    window.close()
                } else {
                    Self.bringMainWindowToFront()
                }
            } else {
                AppState.openMainWindow?()
            }
        }
    }
}
