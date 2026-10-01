import AppKit
import Foundation
import IOKit.pwr_mgt

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

    /// Runs a system action. Log Out, Restart and Shut Down show macOS's own confirmation;
    /// quitting every app asks first.
    public static func run(_ action: SystemAction) {
        switch action {
        case .lockScreen: lockScreen()
        case .sleep: runTool("/usr/bin/pmset", ["sleepnow"])
        case .sleepDisplays: runTool("/usr/bin/pmset", ["displaysleepnow"])
        case .screenSaver:
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        case .logOut: askLoginWindow(LoginWindowEvent.logOut)
        case .restart: askLoginWindow(LoginWindowEvent.showRestartDialog)
        case .shutDown: askLoginWindow(LoginWindowEvent.showShutdownDialog)
        case .caffeinate: Caffeinate.shared.toggle()
        case .playPause: SystemAudio.press(.playPause)
        case .nextTrack: SystemAudio.press(.next)
        case .previousTrack: SystemAudio.press(.previous)
        case .toggleMute: SystemAudio.toggleMute()
        case .volumeUp: SystemAudio.changeVolume(by: SystemAudio.step)
        case .volumeDown: SystemAudio.changeVolume(by: -SystemAudio.step)
        case .volume0, .volume25, .volume50, .volume75, .volume100:
            if let level = action.presetVolume { SystemAudio.setPreset(level) }
        case .toggleMicrophone: SystemAudio.toggleMicrophone()
        case .toggleDarkMode: toggleDarkMode()
        case .openTrash: openTrash()
        case .ejectAllDisks: ejectAllDisks()
        case .toggleHiddenFiles: toggleHiddenFiles()
        case .hideOtherApps:
            let frontmost = NSWorkspace.shared.frontmostApplication
            regularApps().filter { $0 != frontmost }.forEach { $0.hide() }
        case .unhideAllApps: regularApps().forEach { $0.unhide() }
        case .quitAllApps: quitApps(keeping: nil)
        case .quitOtherApps: quitApps(keeping: NSWorkspace.shared.frontmostApplication)
        }
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }

    // MARK: Appearance & files

    /// System Events flips Dark Mode. The first time, macOS asks to let HyperKeys control System Events.
    private static func toggleDarkMode() {
        let script = NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil {
            NSSound.beep()
        }
    }

    private static func openTrash() {
        let trash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    /// Ejects external drives and disk images; leaves internal disks and network shares alone.
    private static func ejectAllDisks() {
        let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let paths = volumes.compactMap { url -> String? in
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsRootFileSystem != true,
                  values.volumeIsEjectable == true || values.volumeIsRemovable == true
            else { return nil }
            return url.path
        }
        guard !paths.isEmpty else {
            NSSound.beep()
            return
        }
        // Ejecting can take a few seconds per disk, so it runs in the background.
        Task.detached {
            for path in paths {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                process.arguments = ["eject", path]
                process.standardOutput = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }
    }

    /// Flips Finder's "show all files" setting and relaunches Finder so it takes effect.
    private static func toggleHiddenFiles() {
        let showing = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", showing ? "false" : "true"]
        try? write.run()
        write.waitUntilExit()
        runTool("/usr/bin/killall", ["Finder"])
    }

    // MARK: Apps

    /// Apps with a Dock icon, other than HyperKeys.
    private static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0 != NSRunningApplication.current
        }
    }

    /// Asks once, then asks each app to quit (so they can offer to save). Finder stays.
    private static func quitApps(keeping kept: NSRunningApplication?) {
        let apps = regularApps().filter { $0 != kept && $0.bundleIdentifier != "com.apple.finder" }
        guard !apps.isEmpty else { return }

        let alert = NSAlert()
        if let kept, let name = kept.localizedName {
            alert.messageText = "Quit every app except \(name)?"
        } else {
            alert.messageText = "Quit every app?"
        }
        alert.informativeText = "\(apps.count) app\(apps.count == 1 ? "" : "s") will quit. Apps with unsaved changes ask before closing."
        alert.addButton(withTitle: "Quit Apps")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        apps.forEach { $0.terminate() }
        kept?.activate()
    }

    /// Locks right away, like ⌃⌘Q.
    public static func lockScreen() {
        typealias LockScreen = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: LockScreen.self)()
            return
        }
        // Fall back to the Lock Screen keyboard shortcut.
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0x0C, keyDown: isDown) // Q
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Apple events loginwindow understands (see Apple's QA1134).
    private enum LoginWindowEvent {
        static let coreClass: AEEventClass = 0x6165_7674 // 'aevt'
        static let logOut: AEEventID = 0x6C6F_676F // 'logo': "Are you sure you want to log out?"
        static let showRestartDialog: AEEventID = 0x7272_7374 // 'rrst'
        static let showShutdownDialog: AEEventID = 0x7273_646E // 'rsdn'
    }

    /// Asks loginwindow to show its dialog, the same one as the Apple menu.
    private static func askLoginWindow(_ eventID: AEEventID) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: LoginWindowEvent.coreClass, eventID: eventID, targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            try event.sendEvent(options: [.noReply], timeout: 10)
        } catch {
            NSLog("[HyperKeys] loginwindow didn't take the request: \(error.localizedDescription)")
            NSSound.beep()
        }
    }
}

/// Keeps the Mac (and its display) awake until turned off or HyperKeys quits.
@MainActor
@Observable
public final class Caffeinate {
    public static let shared = Caffeinate()

    public private(set) var isActive = false
    @ObservationIgnored private var assertionID = IOPMAssertionID(0)

    public init() {}

    public func toggle() {
        isActive ? stop() : start()
    }

    public func start() {
        guard !isActive else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "HyperKeys is keeping your Mac awake (Caffeinate)" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
    }

    public func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        isActive = false
    }
}
