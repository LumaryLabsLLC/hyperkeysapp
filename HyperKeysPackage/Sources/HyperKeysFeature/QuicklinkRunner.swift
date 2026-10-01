import AppKit
import KeyBindings
import Shared

/// Opens quicklinks: asks for any `{argument}`s, fills in the rest, then opens the link.
@MainActor
public enum QuicklinkRunner {
    /// From a shortcut or deeplink: the quicklink with this name.
    public static func open(named name: String) {
        guard let quicklink = QuicklinkStore.shared.quicklink(named: name) else {
            NSSound.beep()
            return
        }
        open(quicklink, from: NSWorkspace.shared.frontmostApplication)
    }

    /// `argument` fills the first `{argument}` (typed after an alias in App Search); any others are asked for.
    public static func open(_ quicklink: Quicklink, from app: NSRunningApplication?, argument: String? = nil) {
        Task {
            let icon = icon(for: quicklink)
            var preset: [String: String] = [:]
            if let argument, let first = Placeholders.arguments(in: quicklink.link).first {
                preset[first.name] = argument
            }
            guard let link = await PlaceholderFiller.fill(
                quicklink.link, title: quicklink.name, icon: icon, app: app, encodesValues: !quicklink.isLocal,
                presetArguments: preset
            ) else { return }
            open(link: link, isLocal: quicklink.isLocal, with: quicklink.openWith)
        }
    }

    /// The site's icon for web links (once fetched), the Finder icon for local ones,
    /// otherwise the icon of the app that opens it.
    static func icon(for quicklink: Quicklink) -> NSImage? {
        if let path = quicklink.localPath {
            return AppIconCache.icon(forPath: path)
        }
        if let host = quicklink.host, let favicon = FaviconCache.shared.icon(forHost: host) {
            return favicon
        }
        return quicklink.openingAppURL.map { AppIconCache.icon(forPath: $0.path) }
    }

    /// The URL a filled-in link opens: a file URL for local paths, https:// added when there's no scheme.
    static func url(for link: String, isLocal: Bool) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLocal {
            if trimmed.lowercased().hasPrefix("file:") { return URL(string: trimmed) }
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        guard let url = URL(string: trimmed) else { return nil }
        return url.scheme == nil ? URL(string: "https://" + trimmed) : url
    }

    static func open(link: String, isLocal: Bool, with bundleId: String?) {
        guard let url = url(for: link, isLocal: isLocal) else {
            NSSound.beep()
            return
        }
        if let bundleId, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
