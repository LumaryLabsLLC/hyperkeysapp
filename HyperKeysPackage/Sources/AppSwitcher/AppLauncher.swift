import AppKit
import Shared

private func launcherLog(_ message: String) {
    let path = "/tmp/hyperkeys.log"
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "\(ts) [Launcher] \(message)\n"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

@MainActor
public enum AppLauncher {
    /// Toggle an app: hide if frontmost, otherwise launch/focus/reopen.
    public static func toggleApp(bundleIdentifier: String) {
        // If frontmost, hide it
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           running.isActive {
            launcherLog("Hiding active app: \(bundleIdentifier)")
            running.hide()
            return
        }

        // Otherwise, use openApplication which handles all cases:
        // - Not running → launches it
        // - Running but hidden → unhides + activates
        // - Running, no windows → sends reopen event (creates new window)
        // - Running, has windows → activates
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            launcherLog("Could not find app URL for: \(bundleIdentifier)")
            return
        }
        launcherLog("Opening app: \(bundleIdentifier) from \(url.path)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error {
                launcherLog("Failed to open \(bundleIdentifier): \(error.localizedDescription)")
            } else {
                launcherLog("Opened \(bundleIdentifier) (pid=\(app?.processIdentifier ?? -1))")
            }
        }
    }

    /// Launch or focus only (no hide toggle). Used by app groups.
    public static func launchOrFocus(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            launcherLog("launchOrFocus: Could not find app URL for: \(bundleIdentifier)")
            return
        }
        launcherLog("launchOrFocus: Opening \(bundleIdentifier)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error {
                launcherLog("launchOrFocus: Failed to open \(bundleIdentifier): \(error.localizedDescription)")
            }
        }
    }

    /// Hide an app by bundle identifier.
    public static func hide(bundleIdentifier: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.hide()
        }
    }
}
