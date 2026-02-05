import EventEngine
import Foundation
import WindowEngine

public enum BoundAction: Codable, Sendable, Hashable {
    case launchApp(bundleId: String, appName: String)
    case triggerMenuItem(appBundleId: String, menuPath: [String])
    case showAppGroup(groupId: UUID)
    case windowAction(WindowPosition)
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
