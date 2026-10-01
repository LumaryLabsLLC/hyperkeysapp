import AppKit
import EventEngine
import Foundation
import WindowEngine

/// What a Raycast export would add to HyperKeys, checked against what's already set up.
public struct RaycastImportPlan: Sendable {
    public struct Shortcut: Identifiable, Sendable, Equatable {
        public let id: Int
        public let key: KeyCode
        public let action: BoundAction
        /// What it was called in Raycast.
        public let raycastTitle: String
        /// How it was pressed in Raycast, e.g. "⌃⌥⇧⌘T".
        public let raycastShortcut: String
        /// False when Raycast didn't use Hyper; importing moves it to Hyper + the same key.
        public let usesHyper: Bool
        /// What Hyper + key does in HyperKeys today.
        public let replacing: BoundAction?
    }

    public struct SnippetItem: Identifiable, Sendable, Equatable {
        public let id: Int
        public let snippet: Snippet
        /// The Raycast name, when it had to change because HyperKeys already has a snippet called that.
        public let originalName: String?
        public let keyword: String?
        /// Raycast placeholders HyperKeys pastes as written, like "{argument}".
        public let unsupportedPlaceholders: [String]
    }

    public struct Skipped: Identifiable, Sendable, Equatable {
        public let id: Int
        public let title: String
        public let raycastShortcut: String
        public let reason: String
    }

    public private(set) var shortcuts: [Shortcut] = []
    public private(set) var snippets: [SnippetItem] = []
    public private(set) var skipped: [Skipped] = []
    /// Shortcuts and snippets HyperKeys already has exactly.
    public private(set) var alreadyPresent = 0

    public var isEmpty: Bool { shortcuts.isEmpty && snippets.isEmpty }
    public var keywordCount: Int { snippets.count { $0.keyword != nil } }

    public typealias AppResolver = (_ path: String) -> (bundleId: String, name: String)?

    public init(
        export: RaycastExport,
        hyperKey: KeyCode,
        existingBindings: [KeyBinding],
        existingSnippets: [Snippet],
        resolveApp: AppResolver = RaycastImportPlan.installedApp(atPath:)
    ) {
        planShortcuts(export, hyperKey: hyperKey, existing: existingBindings, resolveApp: resolveApp)
        planSnippets(export.snippets, existing: existingSnippets)
    }

    /// Hyper shortcuts that don't replace anything, one per key. The rest are opt-in.
    public var suggestedShortcuts: Set<Int> {
        var keys = Set<KeyCode>()
        var chosen = Set<Int>()
        for item in shortcuts where item.usesHyper && item.replacing == nil && !keys.contains(item.key) {
            keys.insert(item.key)
            chosen.insert(item.id)
        }
        return chosen
    }

    // MARK: - Shortcuts

    private mutating func planShortcuts(_ export: RaycastExport, hyperKey: KeyCode, existing: [KeyBinding], resolveApp: AppResolver) {
        var seen: [KeyCode: Set<BoundAction>] = [:]
        var planned: [Shortcut] = []

        for (index, hotkey) in export.hotkeys.enumerated() {
            let key = KeyCode(rawValue: UInt16(clamping: hotkey.keyCode))
            let raycastShortcut = hotkey.modifiers.symbols + (key?.displayLabel ?? "Key \(hotkey.keyCode)")
            let mapping = Self.map(hotkey.target, resolveApp: resolveApp)

            guard case .action(let action, let title) = mapping else {
                if case .skip(let title, let reason) = mapping {
                    skipped.append(Skipped(id: index, title: title, raycastShortcut: raycastShortcut, reason: reason))
                }
                continue
            }
            guard let key, key.isBindable else {
                skipped.append(Skipped(id: index, title: title, raycastShortcut: raycastShortcut, reason: "HyperKeys can’t use that key with Hyper"))
                continue
            }
            guard key != hyperKey else {
                skipped.append(Skipped(id: index, title: title, raycastShortcut: raycastShortcut, reason: "\(key.name) is your Hyper Key"))
                continue
            }

            let current = existing.first { $0.keyCode == key && $0.isEnabled }?.action
            if current == action {
                alreadyPresent += 1
                continue
            }
            // The same app or command on the same key twice (say with and without Hyper) only needs one row.
            guard seen[key, default: []].insert(action).inserted else { continue }

            let usesHyper = hotkey.modifiers == .hyper
                || (!export.hyperIncludesShift && hotkey.modifiers == [.control, .option, .command])
            planned.append(Shortcut(
                id: index,
                key: key,
                action: action,
                raycastTitle: title,
                raycastShortcut: raycastShortcut,
                usesHyper: usesHyper,
                replacing: current
            ))
        }

        shortcuts = planned.sorted { lhs, rhs in
            if lhs.usesHyper != rhs.usesHyper { return lhs.usesHyper }
            return lhs.key.displayLabel.localizedStandardCompare(rhs.key.displayLabel) == .orderedAscending
        }
    }

    enum Mapping: Equatable {
        case action(BoundAction, title: String)
        case skip(title: String, reason: String)
    }

    static func map(_ target: RaycastExport.Hotkey.Target, resolveApp: AppResolver) -> Mapping {
        switch target {
        case .raycast:
            return .action(.appSearch, title: "Raycast")

        case .app(let path):
            let fallbackName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let app = resolveApp(path) else {
                return .skip(title: fallbackName, reason: "Not installed on this Mac")
            }
            return .action(.launchApp(bundleId: app.bundleId, appName: app.name), title: app.name)

        case .quicklink(let name, let link):
            if let path = localPath(link) {
                return .action(.openFolder(path: path), title: name)
            }
            return .skip(title: name, reason: "HyperKeys shortcuts can’t open web links")

        case .command(let extensionId, let id, let title):
            let name = title ?? readableName(id: id, extensionId: extensionId)
            let command = normalized(id)
            let all = normalized(extensionId) + command

            if all.contains("clipboardhistory") {
                return .skip(title: name, reason: "HyperKeys doesn’t keep clipboard history")
            }
            if all.contains("emoji") {
                return .action(.emojiPicker, title: name)
            }
            if command.hasSuffix("searchsnippets") || extensionId == "e:r:snippets" && command.hasSuffix("snippets") {
                return .action(.snippets, title: name)
            }
            if command.hasSuffix("emptytrash") {
                return .action(.emptyTrash, title: name)
            }
            if command.hasSuffix("switchwindows") || command.hasSuffix("switchwindow") {
                return .action(.appSwitcher, title: name)
            }
            if all.contains("windowmanagement") {
                if let position = windowPosition(command) {
                    return .action(.windowAction(position), title: name)
                }
                return .skip(title: name, reason: "No matching window layout in HyperKeys")
            }
            return .skip(title: name, reason: "Nothing like it in HyperKeys")
        }
    }

    /// Raycast window commands by name, longest first so "almost-maximize" isn't read as "maximize".
    /// The ones HyperKeys has no layout for map to nil.
    private static let windowCommands: [(name: String, position: WindowPosition?)] = {
        let table: [String: WindowPosition?] = [
            "lefthalf": .leftHalf, "righthalf": .rightHalf, "tophalf": .topHalf, "bottomhalf": .bottomHalf,
            "centerhalf": nil,
            "topleftquarter": .topLeftQuarter, "toprightquarter": .topRightQuarter,
            "bottomleftquarter": .bottomLeftQuarter, "bottomrightquarter": .bottomRightQuarter,
            "firstthird": .firstThird, "centerthird": .centerThird, "lastthird": .lastThird,
            "firsttwothirds": .firstTwoThirds, "centertwothirds": nil, "lasttwothirds": .lastTwoThirds,
            "firstfourth": .firstFourth, "secondfourth": .secondFourth, "thirdfourth": .thirdFourth, "lastfourth": .lastFourth,
            "firstthreefourths": nil, "centerthreefourths": nil, "lastthreefourths": nil,
            "topleftsixth": .topLeftSixth, "topcentersixth": .topCenterSixth, "toprightsixth": .topRightSixth,
            "bottomleftsixth": .bottomLeftSixth, "bottomcentersixth": .bottomCenterSixth, "bottomrightsixth": .bottomRightSixth,
            "maximize": .fullScreen, "almostmaximize": nil,
            "maximizewidth": .maximizeWidth, "maximizeheight": .maximizeHeight,
            "center": .center, "reasonablesize": .reasonableSize,
            "togglefullscreen": nil, "restore": nil,
        ]
        return table.map { ($0.key, $0.value) }.sorted { $0.name.count > $1.name.count }
    }()

    static func windowPosition(_ command: String) -> WindowPosition? {
        windowCommands.first { command.hasSuffix($0.name) }?.position ?? nil
    }

    /// Lowercased letters and digits only, so "left-half", "leftHalf" and "left_half" all read the same.
    static func normalized(_ string: String) -> String {
        String(string.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// "e:r:window-management::left-half" → "Left Half"; "searchSnippets" → "Search Snippets".
    static func readableName(id: String, extensionId: String) -> String {
        let source = id.isEmpty ? extensionId : id
        let last = source.split(whereSeparator: { ":/.".contains($0) }).last.map(String.init) ?? source
        var words: [String] = []
        var current = ""
        for char in last {
            if char == "-" || char == "_" || char == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if char.isUppercase, let previous = current.last, previous.isLowercase {
                words.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { words.append(current) }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? "Raycast command" : name
    }

    /// A Raycast quicklink that points at something on disk, as a path HyperKeys can open.
    static func localPath(_ link: String) -> String? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.contains("{") else { return nil } // quicklinks that ask for input
        if link.hasPrefix("/") || link.hasPrefix("~") {
            return link
        }
        if let url = URL(string: link), url.isFileURL {
            return (url.path as NSString).abbreviatingWithTildeInPath
        }
        return nil
    }

    /// Finds an app from the path Raycast saved, then by name, since paths differ between Macs.
    public static func installedApp(atPath path: String) -> (bundleId: String, name: String)? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var bundle = Bundle(url: url)
        if bundle?.bundleIdentifier == nil {
            let fileName = url.lastPathComponent
            let candidates = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", "~/Applications"]
            bundle = candidates.lazy
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).appendingPathComponent(fileName) }
                .compactMap(Bundle.init(url:))
                .first { $0.bundleIdentifier != nil }
        }
        guard let bundle, let bundleId = bundle.bundleIdentifier else { return nil }
        let name = (FileManager.default.displayName(atPath: bundle.bundlePath) as NSString).deletingPathExtension
        return (bundleId, name)
    }

    // MARK: - Snippets

    private mutating func planSnippets(_ incoming: [RaycastExport.Snippet], existing: [Snippet]) {
        var taken = Set(existing.map { $0.name.lowercased() })
        var known = Set(existing.map { "\($0.name)\u{0}\($0.text)" })

        for (index, raycast) in incoming.enumerated() {
            var name = raycast.name
            if name.isEmpty {
                name = String(raycast.text.split(separator: "\n").first?.prefix(40) ?? "Snippet")
            }
            guard known.insert("\(name)\u{0}\(raycast.text)").inserted else {
                alreadyPresent += 1
                continue
            }

            var finalName = name
            if taken.contains(name.lowercased()) {
                finalName = "\(name) (Raycast)"
                var counter = 2
                while taken.contains(finalName.lowercased()) {
                    finalName = "\(name) (Raycast \(counter))"
                    counter += 1
                }
            }
            taken.insert(finalName.lowercased())

            snippets.append(SnippetItem(
                id: index,
                snippet: Snippet(name: finalName, text: raycast.text),
                originalName: finalName == name ? nil : name,
                keyword: raycast.keyword,
                unsupportedPlaceholders: SnippetStore.unsupportedPlaceholders(in: raycast.text)
            ))
        }
    }

    // MARK: - Importing

    /// Adds the chosen shortcuts to the active profile and the chosen snippets to the snippet list.
    @MainActor
    @discardableResult
    public func apply(
        shortcuts chosenShortcuts: Set<Int>,
        snippets chosenSnippets: Set<Int>,
        bindingStore: BindingStore,
        snippetStore: SnippetStore
    ) -> (shortcuts: Int, snippets: Int) {
        let newBindings = shortcuts.filter { chosenShortcuts.contains($0.id) }.map { (key: $0.key, action: $0.action) }
        let newSnippets = snippets.filter { chosenSnippets.contains($0.id) }.map(\.snippet)
        if !newBindings.isEmpty {
            bindingStore.assign(newBindings)
        }
        if !newSnippets.isEmpty {
            snippetStore.add(newSnippets)
        }
        return (newBindings.count, newSnippets.count)
    }
}
