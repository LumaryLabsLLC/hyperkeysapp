import EventEngine
import Foundation
import WindowEngine

public enum BoundAction: Codable, Sendable, Hashable {
    case launchApp(bundleId: String, appName: String)
    case triggerMenuItem(appBundleId: String, menuPath: [String])
    case showAppGroup(groupId: UUID)
    case windowAction(WindowPosition)
    /// Opens the floating App Search launcher.
    case appSearch
    /// Opens the open-apps / windows switcher grid.
    case appSwitcher
    /// Opens the Emoji & Symbols picker.
    case emojiPicker
    /// Opens a folder (or file) in Finder. Paths may start with "~".
    case openFolder(path: String)
    /// Empties the Trash, after confirming.
    case emptyTrash
    /// Opens the Snippets search panel.
    case snippets
    /// Opens Clipboard History.
    case clipboardHistory
    /// Opens the process list, to quit or force quit something.
    case killProcess
    /// Searches the menus of the app you're in and runs the item you pick.
    case menuSearch
    /// Searches GIPHY and Klipy for GIFs and clips to copy or paste.
    case gifSearch
    /// Opens a saved quicklink, by name.
    case quicklink(name: String)
    /// Lock, sleep, log out, restart, shut down, or keep the Mac awake.
    case system(SystemAction)
    case none
}

/// Things macOS itself does, with no app attached.
public enum SystemAction: String, Codable, Sendable, Hashable, CaseIterable {
    // Power & session
    case lockScreen, sleep, sleepDisplays, screenSaver, logOut, restart, shutDown
    // Staying awake
    case caffeinate
    // Audio & media
    case playPause, nextTrack, previousTrack
    case toggleMute, volumeUp, volumeDown, volume0, volume25, volume50, volume75, volume100
    case toggleMicrophone
    // Appearance & files
    case toggleDarkMode, openTrash, ejectAllDisks, toggleHiddenFiles
    // Apps
    case hideOtherApps, unhideAllApps, quitAllApps, quitOtherApps

    public var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        case .sleepDisplays: "Sleep Displays"
        case .screenSaver: "Show Screen Saver"
        case .logOut: "Log Out"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .caffeinate: "Caffeinate"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .toggleMute: "Toggle Mute"
        case .volumeUp: "Turn Volume Up"
        case .volumeDown: "Turn Volume Down"
        case .volume0: "Set Volume to 0%"
        case .volume25: "Set Volume to 25%"
        case .volume50: "Set Volume to 50%"
        case .volume75: "Set Volume to 75%"
        case .volume100: "Set Volume to 100%"
        case .toggleMicrophone: "Toggle Microphone Mute"
        case .toggleDarkMode: "Toggle System Appearance"
        case .openTrash: "Open Trash"
        case .ejectAllDisks: "Eject All Disks"
        case .toggleHiddenFiles: "Toggle Hidden Files"
        case .hideOtherApps: "Hide All Apps Except Frontmost"
        case .unhideAllApps: "Unhide All Hidden Apps"
        case .quitAllApps: "Quit All Apps"
        case .quitOtherApps: "Quit All Apps Except Frontmost"
        }
    }

    public var detail: String {
        switch self {
        case .lockScreen: "Lock your Mac"
        case .sleep: "Put your Mac to sleep"
        case .sleepDisplays: "Turn your displays off, leaving your Mac on"
        case .screenSaver: "Start the screen saver"
        case .logOut: "Log out of your account (asks first)"
        case .restart: "Restart your Mac (asks first)"
        case .shutDown: "Shut down your Mac (asks first)"
        case .caffeinate: "Keep your Mac awake, or let it sleep again"
        case .playPause: "Play or pause what's playing"
        case .nextTrack: "Skip to the next track"
        case .previousTrack: "Go back to the previous track"
        case .toggleMute: "Mute or unmute your speakers"
        case .volumeUp: "Make it louder"
        case .volumeDown: "Make it quieter"
        case .volume0, .volume25, .volume50, .volume75, .volume100: "Set the output volume"
        case .toggleMicrophone: "Mute or unmute your microphone"
        case .toggleDarkMode: "Switch between Light and Dark Mode"
        case .openTrash: "Open the Trash in Finder"
        case .ejectAllDisks: "Eject every external drive and disk image"
        case .toggleHiddenFiles: "Show or hide hidden files in Finder"
        case .hideOtherApps: "Hide every app except the one you're using"
        case .unhideAllApps: "Show every hidden app again"
        case .quitAllApps: "Quit every app (asks first)"
        case .quitOtherApps: "Quit every app except the one you're using (asks first)"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleep: "moon.fill"
        case .sleepDisplays: "display"
        case .screenSaver: "sparkles.tv"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .caffeinate: "cup.and.saucer.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .toggleMute: "speaker.slash.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .volume0, .volume25, .volume50, .volume75, .volume100: "speaker.wave.2.fill"
        case .toggleMicrophone: "mic.slash.fill"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .openTrash: "trash"
        case .ejectAllDisks: "eject.fill"
        case .toggleHiddenFiles: "eye.slash"
        case .hideOtherApps: "eye.slash.fill"
        case .unhideAllApps: "eye.fill"
        case .quitAllApps: "xmark.circle.fill"
        case .quitOtherApps: "xmark.circle"
        }
    }

    /// Words App Search also matches, besides the title and "system".
    public var keywords: [String] {
        switch self {
        case .lockScreen: ["lock"]
        case .sleep: ["suspend"]
        case .sleepDisplays: ["display off", "screen off", "turn off display"]
        case .screenSaver: ["screensaver"]
        case .logOut: ["logout", "sign out"]
        case .restart: ["reboot"]
        case .shutDown: ["shutdown", "power off", "turn off"]
        case .caffeinate: ["coffee", "awake", "stay awake", "keep awake", "prevent sleep", "amphetamine"]
        case .playPause: ["play", "pause", "music", "media"]
        case .nextTrack: ["next", "skip", "music"]
        case .previousTrack: ["previous", "back", "music"]
        case .toggleMute: ["mute", "unmute", "sound", "audio", "volume"]
        case .volumeUp, .volumeDown, .volume0, .volume25, .volume50, .volume75, .volume100: ["volume", "sound", "audio"]
        case .toggleMicrophone: ["mic", "microphone", "mute mic", "input"]
        case .toggleDarkMode: ["dark mode", "light mode", "appearance", "theme"]
        case .openTrash: ["trash", "bin"]
        case .ejectAllDisks: ["eject", "unmount", "disks", "drives", "usb"]
        case .toggleHiddenFiles: ["hidden files", "dotfiles", "show hidden", "finder"]
        case .hideOtherApps: ["hide others", "hide apps", "focus"]
        case .unhideAllApps: ["show all", "unhide"]
        case .quitAllApps: ["quit all", "close all"]
        case .quitOtherApps: ["quit others", "close others"]
        }
    }

    /// Volume presets, 0 to 1.
    public var presetVolume: Float? {
        switch self {
        case .volume0: 0
        case .volume25: 0.25
        case .volume50: 0.5
        case .volume75: 0.75
        case .volume100: 1
        default: nil
        }
    }
}

public struct KeyBinding: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var keyCode: KeyCode
    public var action: BoundAction
    public var isEnabled: Bool
    public var groupId: UUID?

    public init(
        id: UUID = UUID(),
        keyCode: KeyCode,
        action: BoundAction,
        isEnabled: Bool = true,
        groupId: UUID? = nil
    ) {
        self.id = id
        self.keyCode = keyCode
        self.action = action
        self.isEnabled = isEnabled
        self.groupId = groupId
    }
}
