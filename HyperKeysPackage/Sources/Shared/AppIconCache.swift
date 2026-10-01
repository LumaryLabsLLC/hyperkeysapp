import AppKit

/// Caches app icons and bundle-id lookups so views can ask for them on every render.
@MainActor
public enum AppIconCache {
    private static let icons = NSCache<NSString, NSImage>()
    private static var pathsByBundleId: [String: String] = [:]

    public static func icon(forPath path: String) -> NSImage {
        if let cached = icons.object(forKey: path as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(icon, forKey: path as NSString)
        return icon
    }

    public static func icon(forBundleId bundleId: String) -> NSImage? {
        path(forBundleId: bundleId).map(icon(forPath:))
    }

    public static func path(forBundleId bundleId: String) -> String? {
        if let cached = pathsByBundleId[bundleId] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        pathsByBundleId[bundleId] = url.path
        return url.path
    }
}
