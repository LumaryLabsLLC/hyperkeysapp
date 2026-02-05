import AppKit

public struct AppInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let name: String
    public let path: String

    public init(bundleIdentifier: String, name: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }

    @MainActor
    public var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: path)
    }
}
