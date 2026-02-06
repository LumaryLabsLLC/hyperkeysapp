import AppKit
import Shared
import WindowEngine

private func groupLog(_ message: String) {
    let path = "/tmp/hyperkeys.log"
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "\(ts) [Group] \(message)\n"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

@MainActor
public enum AppGroupManager {
    /// Toggle a group: if any group app is frontmost, hide all group apps.
    /// Otherwise, launch/focus all group apps.
    public static func activate(group: AppGroup) {
        let groupBundleIds = Set(group.appBundleIdentifiers)
        let frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let groupIsFrontmost = frontmostBundleId.map { groupBundleIds.contains($0) } ?? false

        groupLog("Activate '\(group.name)': \(group.appBundleIdentifiers.count) apps, frontmost=\(frontmostBundleId ?? "nil"), groupIsFrontmost=\(groupIsFrontmost)")

        if groupIsFrontmost {
            // Hide all group apps
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                guard let bundleId = app.bundleIdentifier else { continue }
                if groupBundleIds.contains(bundleId) {
                    groupLog("Hiding \(bundleId)")
                    app.hide()
                }
            }
        } else {
            // Launch/focus all group apps
            for bundleId in group.appBundleIdentifiers {
                groupLog("Opening \(bundleId)")
                AppLauncher.launchOrFocus(bundleIdentifier: bundleId)
            }

            // Apply window positions after apps have time to launch
            if !group.windowPositions.isEmpty {
                groupLog("Scheduling window positions for \(group.windowPositions.count) apps")
                Task { @MainActor in
                    // Retry up to 5 times with increasing delays to handle slow app launches
                    var pending = group.windowPositions
                    for attempt in 1...5 {
                        let delayMs = attempt == 1 ? 500 : 400
                        try? await Task.sleep(for: .milliseconds(delayMs))
                        for (bundleId, position) in pending {
                            groupLog("Attempt \(attempt): positioning \(bundleId) → \(position.displayName)")
                            if WindowManager.moveWindow(to: position, ofApp: bundleId) {
                                pending.removeValue(forKey: bundleId)
                            }
                        }
                        if pending.isEmpty { break }
                    }
                    if !pending.isEmpty {
                        groupLog("Failed to position \(pending.count) app(s) after retries")
                    }
                }
            }
        }
    }
}
