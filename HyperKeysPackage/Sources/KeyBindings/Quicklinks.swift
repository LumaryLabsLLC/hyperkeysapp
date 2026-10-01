import AppKit
import Foundation

/// A saved link: a website, a folder or file, or an app deeplink. Placeholders like
/// `{argument}` and `{clipboard}` are filled in when it's opened.
public struct Quicklink: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var link: String
    /// Bundle id of the app to open it with; nil uses the default for the link.
    public var openWith: String?

    public init(id: UUID = UUID(), name: String, link: String, openWith: String? = nil) {
        self.id = id
        self.name = name
        self.link = link
        self.openWith = openWith
    }

    /// A file or folder on this Mac rather than a web address.
    public var isLocal: Bool {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.lowercased().hasPrefix("file:")
    }

    /// The file or folder path, for local links.
    public var localPath: String? {
        guard isLocal else { return nil }
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("file:") {
            return URL(string: trimmed)?.path
        }
        return (trimmed as NSString).expandingTildeInPath
    }

    /// The website's host ("github.com") for web links; nil for local ones and app links.
    public var host: String? {
        guard !isLocal else { return nil }
        let cleaned = link.replacingOccurrences(of: #"\{[^}]*\}"#, with: "x", options: .regularExpression)
        guard let url = URL(string: cleaned), let scheme = url.scheme?.lowercased() else {
            return URL(string: "https://" + cleaned)?.host()
        }
        return scheme == "http" || scheme == "https" ? url.host() : nil
    }

    /// The host for web links ("github.com"), or the path for local ones.
    public var displayLink: String {
        if isLocal { return link }
        let cleaned = link.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
        return URL(string: cleaned)?.host() ?? link
    }

    /// The app that opens it: the chosen one, or the default for links like it.
    @MainActor
    public var openingAppURL: URL? {
        if let openWith, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: openWith) {
            return url
        }
        if isLocal { return nil }
        let cleaned = link.replacingOccurrences(of: #"\{[^}]*\}"#, with: "x", options: .regularExpression)
        let probe = URL(string: cleaned).flatMap { $0.scheme == nil ? nil : $0 } ?? URL(string: "https://example.com")!
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }
}

@MainActor
@Observable
public final class QuicklinkStore {
    public static let shared = QuicklinkStore()

    public private(set) var quicklinks: [Quicklink] = []
    /// Called after the user adds, edits or deletes a quicklink, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init() {}

    public func quicklink(named name: String) -> Quicklink? {
        quicklinks.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func quicklink(id: UUID) -> Quicklink? {
        quicklinks.first { $0.id == id }
    }

    /// Adds a new quicklink, or replaces the one with the same id.
    public func save(_ quicklink: Quicklink) {
        if let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) {
            quicklinks[index] = quicklink
        } else {
            quicklinks.append(quicklink)
        }
        onChange?()
    }

    public func add(_ newQuicklinks: [Quicklink]) {
        quicklinks.append(contentsOf: newQuicklinks)
        onChange?()
    }

    public func delete(id: UUID) {
        quicklinks.removeAll { $0.id == id }
        onChange?()
    }

    /// Replaces every quicklink (when `config.json` is loaded). Doesn't trigger `onChange`.
    public func replaceAll(_ newQuicklinks: [Quicklink]) {
        quicklinks = newQuicklinks
    }
}
