import Foundation

public struct ActionGroup: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var bindings: [KeyBinding]

    public init(id: UUID = UUID(), name: String, icon: String = "keyboard", bindings: [KeyBinding] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bindings = bindings
    }
}
