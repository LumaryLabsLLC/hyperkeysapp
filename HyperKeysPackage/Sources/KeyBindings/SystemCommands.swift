import AppKit
import Foundation

/// macOS actions that aren't about a particular app.
@MainActor
public enum SystemCommands {
    /// Opens a folder (or file) in Finder. "~" is expanded.
    public static func open(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Asks first — it can't be undone — then has Finder empty the Trash.
    public static func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Everything in the Trash will be deleted permanently. You can't undo this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Finder does the deleting (and plays its sound). The first time, macOS asks to let
        // HyperKeys control Finder.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        try? process.run()
    }
}
