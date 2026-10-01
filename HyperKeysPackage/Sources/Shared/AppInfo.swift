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
        path.isEmpty ? AppIconCache.icon(forBundleId: bundleIdentifier) : AppIconCache.icon(forPath: path)
    }

    /// Builds an `AppInfo` for an installed app, or nil if the bundle id can't be resolved.
    @MainActor
    public static func resolve(bundleId: String) -> AppInfo? {
        guard let path = AppIconCache.path(forBundleId: bundleId) else { return nil }
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        return AppInfo(bundleIdentifier: bundleId, name: name, path: path)
    }
}
