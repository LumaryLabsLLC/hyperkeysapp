import AppSwitcher
import CryptoKit
import EventEngine
import Foundation
import Shared
import WindowEngine

// MARK: - The file's shape

/// The contents of `~/.config/hyperkeys/config.json`. Written for humans: key names instead of
/// key codes, one field per kind of action, nothing that changes on its own.
///
/// ```json
/// {
///   "hyperKey": "capsLock",
///   "shortcuts": [
///     { "key": "t", "openApp": "com.mitchellh.ghostty", "name": "Ghostty" },
///     { "key": "h", "window": "leftHalf" },
///     { "key": "space", "command": "appSearch" }
///   ]
/// }
/// ```
public struct ConfigDocument: Codable, Equatable, Sendable {
    public var version: Int?
    /// "capsLock", "backtick", "tab", "keyboardHyper" (a keyboard that sends ⌃⌥⇧⌘), or any key name.
    public var hyperKey: String?
    /// "none", "small", "medium", "large", "extraLarge".
    public var windowGap: String?
    /// "hold" (⌘-Tab style) or "stayOpen" (navigate with h j k l).
    public var appSwitcher: String?
    public var doubleTapOpensWindow: Bool?
    /// The Default profile.
    public var shortcuts: [Shortcut]?
    public var profiles: [Profile]?
    /// Text to paste from the Snippets panel. `{clipboard}`, `{date}` and `{time}` are filled in.
    public var snippets: [SnippetEntry]?

    public struct SnippetEntry: Codable, Equatable, Sendable {
        public var name: String
        public var text: String
        public var tags: [String]?
    }

    public struct Profile: Codable, Equatable, Sendable {
        public var name: String
        public var shortcuts: [Shortcut]?
    }

    /// Exactly one of `openApp`, `openApps`, `window`, `menu` or `command` is expected.
    public struct Shortcut: Codable, Equatable, Sendable {
        public var key: String
        /// Bundle identifier, e.g. "com.apple.Safari".
        public var openApp: String?
        /// Several apps opened together, each optionally placed in a window layout.
        public var openApps: [GroupApp]?
        /// A window layout, e.g. "leftHalf", "center", "topRightSixth".
        public var window: String?
        public var menu: MenuCommand?
        /// A folder (or file) to open in Finder, e.g. "~/Downloads".
        public var openFolder: String?
        /// "appSearch", "appSwitcher", "emojiPicker", "snippets" or "emptyTrash".
        public var command: String?
        /// Display name for `openApp` / `openApps`.
        public var name: String?
        /// Set to false to keep a shortcut without it doing anything.
        public var enabled: Bool?
    }

    public struct GroupApp: Codable, Equatable, Sendable {
        public var app: String
        public var window: String?
    }

    public struct MenuCommand: Codable, Equatable, Sendable {
        public var app: String
        public var path: [String]
    }
}

/// Everything the config file describes, in the app's own types.
public struct ConfigSettings {
    public var bindings: [KeyBinding] = []
    public var profiles: [ActionGroup] = []
    public var appGroups: [AppGroup] = []
    public var hyperKey: KeyCode = .capsLock
    public var windowGap: WindowGap = .none
    public var switcherStaysOpen = false
    public var doubleTapOpensWindow = true
    public var snippets: [Snippet] = []

    public init(
        bindings: [KeyBinding] = [], profiles: [ActionGroup] = [], appGroups: [AppGroup] = [],
        hyperKey: KeyCode = .capsLock, windowGap: WindowGap = .none,
        switcherStaysOpen: Bool = false, doubleTapOpensWindow: Bool = true, snippets: [Snippet] = []
    ) {
        self.snippets = snippets
        self.bindings = bindings
        self.profiles = profiles
        self.appGroups = appGroups
        self.hyperKey = hyperKey
        self.windowGap = windowGap
        self.switcherStaysOpen = switcherStaysOpen
        self.doubleTapOpensWindow = doubleTapOpensWindow
    }
}

// MARK: - Conversion

public enum ConfigCodec {
    public static let currentVersion = 1

    /// Pretty-printed with sorted keys, so the file diffs cleanly in git.
    public static func encode(_ document: ConfigDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(0x0A) // trailing newline
        return data
    }

    /// Throws with a human-readable message (including line and column for JSON syntax errors).
    public static func decode(_ data: Data) throws -> ConfigDocument {
        do {
            return try JSONDecoder().decode(ConfigDocument.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalid(describe(error))
        }
    }

    @MainActor
    public static func document(from settings: ConfigSettings) -> ConfigDocument {
        let groupsById = Dictionary(settings.appGroups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func shortcuts(_ bindings: [KeyBinding]) -> [ConfigDocument.Shortcut]? {
            let list = bindings
                .compactMap { shortcut(for: $0, groups: groupsById) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            return list.isEmpty ? nil : list
        }

        return ConfigDocument(
            version: currentVersion,
            hyperKey: settings.hyperKey.configName,
            windowGap: settings.windowGap.rawValue,
            appSwitcher: settings.switcherStaysOpen ? "stayOpen" : "hold",
            doubleTapOpensWindow: settings.doubleTapOpensWindow,
            shortcuts: shortcuts(settings.bindings) ?? [],
            profiles: settings.profiles.isEmpty ? nil : settings.profiles.map {
                ConfigDocument.Profile(name: $0.name, shortcuts: shortcuts($0.bindings))
            },
            snippets: settings.snippets.isEmpty ? nil : settings.snippets.map {
                ConfigDocument.SnippetEntry(name: $0.name, text: $0.text, tags: $0.tags.isEmpty ? nil : $0.tags)
            }
        )
    }

    /// Converts a document into settings. Problems that don't stop the rest from loading
    /// (an unknown key name, a typo in a layout) are returned as warnings.
    @MainActor
    public static func settings(from document: ConfigDocument) -> (ConfigSettings, warnings: [String]) {
        var settings = ConfigSettings()
        var warnings: [String] = []

        if let name = document.hyperKey {
            if let key = KeyCode(configName: name) {
                settings.hyperKey = key
            } else {
                warnings.append("Unknown hyperKey “\(name)” — using Caps Lock.")
            }
        }
        if let gap = document.windowGap {
            if let value = WindowGap(rawValue: gap) {
                settings.windowGap = value
            } else {
                warnings.append("Unknown windowGap “\(gap)”. Use none, small, medium, large or extraLarge.")
            }
        }
        settings.switcherStaysOpen = document.appSwitcher == "stayOpen"
        settings.doubleTapOpensWindow = document.doubleTapOpensWindow ?? true

        func bindings(_ shortcuts: [ConfigDocument.Shortcut]?, in place: String) -> [KeyBinding] {
            var seenKeys = Set<KeyCode>()
            return (shortcuts ?? []).compactMap { shortcut in
                guard let key = KeyCode(configName: shortcut.key) else {
                    warnings.append("\(place): unknown key “\(shortcut.key)”.")
                    return nil
                }
                guard seenKeys.insert(key).inserted else {
                    warnings.append("\(place): “\(shortcut.key)” is listed twice — keeping the first.")
                    return nil
                }
                guard let action = action(for: shortcut, groups: &settings.appGroups, warnings: &warnings, place: place) else {
                    return nil
                }
                return KeyBinding(keyCode: key, action: action, isEnabled: shortcut.enabled ?? true)
            }
        }

        settings.bindings = bindings(document.shortcuts, in: "shortcuts")
        settings.snippets = (document.snippets ?? []).enumerated().map { index, entry in
            Snippet(id: stableID(for: "snippet:\(index):\(entry.name)"), name: entry.name, text: entry.text, tags: entry.tags ?? [])
        }
        settings.profiles = (document.profiles ?? []).map { profile in
            ActionGroup(id: stableID(for: "profile:\(profile.name)"), name: profile.name, bindings: bindings(profile.shortcuts, in: "Profile “\(profile.name)”"))
        }
        return (settings, warnings)
    }

    // MARK: Helpers

    @MainActor
    private static func shortcut(for binding: KeyBinding, groups: [UUID: AppGroup]) -> ConfigDocument.Shortcut? {
        var shortcut = ConfigDocument.Shortcut(key: binding.keyCode.configName)
        switch binding.action {
        case .launchApp(let bundleId, let appName):
            shortcut.openApp = bundleId
            shortcut.name = appName
        case .showAppGroup(let groupId):
            guard let group = groups[groupId] else { return nil }
            shortcut.openApps = group.appBundleIdentifiers.map {
                ConfigDocument.GroupApp(app: $0, window: group.windowPositions[$0]?.rawValue)
            }
            shortcut.name = group.name
        case .windowAction(let position):
            shortcut.window = position.rawValue
        case .triggerMenuItem(let app, let path):
            shortcut.menu = ConfigDocument.MenuCommand(app: app, path: path)
        case .appSearch:
            shortcut.command = "appSearch"
        case .appSwitcher:
            shortcut.command = "appSwitcher"
        case .emojiPicker:
            shortcut.command = "emojiPicker"
        case .openFolder(let path):
            shortcut.openFolder = path
        case .emptyTrash:
            shortcut.command = "emptyTrash"
        case .snippets:
            shortcut.command = "snippets"
        case .none:
            return nil
        }
        if !binding.isEnabled {
            shortcut.enabled = false
        }
        return shortcut
    }

    @MainActor
    private static func action(
        for shortcut: ConfigDocument.Shortcut, groups: inout [AppGroup], warnings: inout [String], place: String
    ) -> BoundAction? {
        let label = "\(place) “\(shortcut.key)”"
        if let bundleId = shortcut.openApp {
            let name = shortcut.name ?? AppInfo.resolve(bundleId: bundleId)?.name ?? bundleId
            return .launchApp(bundleId: bundleId, appName: name)
        }
        if let apps = shortcut.openApps {
            var positions: [String: WindowPosition] = [:]
            for app in apps {
                guard let window = app.window else { continue }
                if let position = WindowPosition(rawValue: window) {
                    positions[app.app] = position
                } else {
                    warnings.append("\(label): unknown window layout “\(window)”.")
                }
            }
            let ids = apps.map(\.app)
            let name = shortcut.name ?? ids.compactMap { AppInfo.resolve(bundleId: $0)?.name }.joined(separator: " + ")
            let group = AppGroup(id: stableID(for: "group:\(place):\(shortcut.key)"), name: name, appBundleIdentifiers: ids, windowPositions: positions)
            groups.append(group)
            return .showAppGroup(groupId: group.id)
        }
        if let window = shortcut.window {
            guard let position = WindowPosition(rawValue: window) else {
                warnings.append("\(label): unknown window layout “\(window)”.")
                return nil
            }
            return .windowAction(position)
        }
        if let menu = shortcut.menu {
            return .triggerMenuItem(appBundleId: menu.app, menuPath: menu.path)
        }
        if let folder = shortcut.openFolder {
            return .openFolder(path: folder)
        }
        if let command = shortcut.command {
            switch command {
            case "appSearch": return .appSearch
            case "appSwitcher": return .appSwitcher
            case "emojiPicker": return .emojiPicker
            case "snippets": return .snippets
            case "emptyTrash": return .emptyTrash
            default:
                warnings.append("\(label): unknown command “\(command)”. Use appSearch, appSwitcher, emojiPicker, snippets or emptyTrash.")
                return nil
            }
        }
        warnings.append("\(label) has no action (openApp, openApps, window, menu, openFolder or command).")
        return nil
    }

    /// The same name always gives the same id, so reloading the file (or loading it on another Mac)
    /// keeps profiles and groups recognisable — the active profile survives a reload.
    static func stableID(for name: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(name.utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            // JSON syntax errors carry "around line N, column M" in the underlying error.
            if let underlying = context.underlyingError as NSError?,
               let detail = underlying.userInfo["NSDebugDescription"] as? String {
                return detail
            }
            return context.debugDescription
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])) is missing."
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case invalid(String)
    case iCloudDriveUnavailable
    case managedElsewhere(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message):
            message
        case .iCloudDriveUnavailable:
            "iCloud Drive isn't turned on. Turn it on in System Settings › your name › iCloud, then try again."
        case .managedElsewhere(let path):
            "config.json is a link to \(path). Sync it from there (for example with your dotfiles), or remove the link to use iCloud."
        }
    }
}
