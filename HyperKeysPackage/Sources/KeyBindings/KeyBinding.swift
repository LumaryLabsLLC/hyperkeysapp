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
    case none
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
