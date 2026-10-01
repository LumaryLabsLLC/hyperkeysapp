import Foundation

/// The parts of a Raycast export HyperKeys can use: snippets and command hotkeys.
public struct RaycastExport: Sendable, Equatable {
    public struct Snippet: Sendable, Equatable {
        public var name: String
        public var text: String
        public var keyword: String?

        public init(name: String, text: String, keyword: String? = nil) {
            self.name = name
            self.text = text
            self.keyword = keyword
        }
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
        public static let hyper: Modifiers = [.control, .option, .shift, .command]

        /// ⌃⌥⇧⌘, in the order macOS menus use.
        public var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    public struct Hotkey: Sendable, Equatable {
        public enum Target: Sendable, Equatable {
            /// Raycast's own "open Raycast" hotkey.
            case raycast
            case app(path: String)
            case quicklink(name: String, link: String)
            case command(extensionId: String, id: String, title: String?)
        }

        public var target: Target
        /// macOS virtual key code.
        public var keyCode: Int
        public var modifiers: Modifiers

        public init(target: Target, keyCode: Int, modifiers: Modifiers) {
            self.target = target
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    public var snippets: [Snippet]
    public var hotkeys: [Hotkey]
    /// Raycast's own Hyper Key can leave Shift out; then ⌃⌥⌘ shortcuts are Hyper shortcuts too.
    public var hyperIncludesShift: Bool

    public init(snippets: [Snippet] = [], hotkeys: [Hotkey] = [], hyperIncludesShift: Bool = true) {
        self.snippets = snippets
        self.hotkeys = hotkeys
        self.hyperIncludesShift = hyperIncludesShift
    }

    // MARK: - Parsing

    /// Accepts the Export Snippets array, or the decrypted Settings & Data object.
    static func parse(_ json: Any) throws -> RaycastExport {
        if let array = json as? [[String: Any]] {
            let snippets = parseSnippets(array)
            guard !snippets.isEmpty || array.isEmpty else { throw RaycastImportError.unreadable }
            return RaycastExport(snippets: snippets)
        }
        guard let root = json as? [String: Any] else { throw RaycastImportError.unreadable }

        var export = RaycastExport(snippets: findSnippets(in: root, depth: 0))
        let settings = root["settings"] as? [String: Any]
        guard settings != nil || root["commands"] != nil || !export.snippets.isEmpty else {
            throw RaycastImportError.unreadable
        }
        let general = settings?["general"] as? [String: Any]

        if let code = general?["hyperKeyCode"] as? String, !code.isEmpty, code != "none",
           general?["hyperKeyIncludeShift"] as? Bool == false {
            export.hyperIncludesShift = false
        }

        if let shortcut = parseHotkey(general?["globalHotkey"]) {
            export.hotkeys.append(Hotkey(target: .raycast, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers))
        }

        let quicklinks = parseQuicklinks(root["quicklinks"])
        let commands = settings?["commands"] as? [[String: Any]] ?? root["commands"] as? [[String: Any]] ?? []
        for command in commands {
            guard let shortcut = parseHotkey(command["macosHotkey"] ?? command["hotkey"]) else { continue }
            let extensionId = command["extensionId"] as? String ?? ""
            let id = command["id"] as? String ?? ""
            export.hotkeys.append(Hotkey(
                target: target(extensionId: extensionId, id: id, command: command, quicklinks: quicklinks),
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ))
        }
        return export
    }

    private static func target(extensionId: String, id: String, command: [String: Any], quicklinks: [Quicklink]) -> Hotkey.Target {
        if extensionId == "e:r:applications", let range = id.range(of: "::=::") {
            let path = String(id[range.upperBound...])
            if !path.isEmpty { return .app(path: path) }
        }
        if extensionId.localizedCaseInsensitiveContains("quicklink"),
           let quicklink = quicklinks.first(where: { !$0.id.isEmpty && id.contains($0.id) }) {
            return .quicklink(name: quicklink.name, link: quicklink.link)
        }
        let title = (command["title"] ?? command["name"] ?? command["commandName"]) as? String
        return .command(extensionId: extensionId, id: id, title: title)
    }

    // MARK: Snippets

    private static func parseSnippets(_ entries: [[String: Any]]) -> [Snippet] {
        entries.compactMap { entry in
            guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
            let name = (entry["name"] as? String ?? entry["title"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let keyword = (entry["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Snippet(name: name, text: text, keyword: keyword?.isEmpty == false ? keyword : nil)
        }
    }

    /// Snippets sit under a "snippets" key — `snippets.snippets` today, other spots in older exports.
    private static func findSnippets(in object: [String: Any], depth: Int) -> [Snippet] {
        guard depth < 4 else { return [] }
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            if key.localizedCaseInsensitiveContains("snippets"), let entries = value as? [[String: Any]] {
                let snippets = parseSnippets(entries)
                if !snippets.isEmpty { return snippets }
            }
            if let child = value as? [String: Any] {
                let snippets = findSnippets(in: child, depth: depth + 1)
                if !snippets.isEmpty { return snippets }
            }
        }
        return []
    }

    // MARK: Quicklinks

    private struct Quicklink {
        var id: String
        var name: String
        var link: String
    }

    private static func parseQuicklinks(_ value: Any?) -> [Quicklink] {
        let entries = value as? [[String: Any]] ?? (value as? [String: Any])?["quicklinks"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String, let link = entry["link"] as? String else { return nil }
            let id = entry["id"] as? String ?? (entry["id"] as? NSNumber)?.stringValue ?? ""
            return Quicklink(id: id, name: name, link: link)
        }
    }

    // MARK: Hotkeys

    /// `{"kind": {"shortcut": {"key": {"type": "LayoutIndependent", "code": 17}, "modifiers": [{"modifier": "Meta"}]}}}`,
    /// or the older `"Command-Option-17"` string.
    static func parseHotkey(_ value: Any?) -> (keyCode: Int, modifiers: Modifiers)? {
        if let string = value as? String {
            let parts = string.split(separator: "-").map(String.init)
            guard let last = parts.last, let code = Int(last) else { return nil }
            var modifiers: Modifiers = []
            for part in parts.dropLast() {
                guard let modifier = modifier(named: part) else { return nil }
                modifiers.insert(modifier)
            }
            return (code, modifiers)
        }

        guard let dict = value as? [String: Any] else { return nil }
        let shortcut = (dict["kind"] as? [String: Any])?["shortcut"] as? [String: Any] ?? dict["shortcut"] as? [String: Any]
        guard let shortcut,
              let key = shortcut["key"] as? [String: Any],
              (key["type"] as? String).map({ $0 == "LayoutIndependent" }) ?? true,
              let code = key["code"] as? Int
        else { return nil }

        var modifiers: Modifiers = []
        for entry in shortcut["modifiers"] as? [Any] ?? [] {
            let name = (entry as? [String: Any])?["modifier"] as? String ?? entry as? String ?? ""
            if let modifier = modifier(named: name) { modifiers.insert(modifier) }
        }
        return (code, modifiers)
    }

    private static func modifier(named name: String) -> Modifiers? {
        switch name.lowercased() {
        case "meta", "command", "cmd": .command
        case "ctrl", "control": .control
        case "alt", "option", "opt": .option
        case "shift": .shift
        default: nil
        }
    }
}
