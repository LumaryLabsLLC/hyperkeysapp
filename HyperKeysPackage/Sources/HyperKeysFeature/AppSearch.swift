import AppKit
import AppSwitcher
import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI
import WindowEngine

// MARK: - Items

/// Something App Search can run that isn't an app: a HyperKeys tool, a window layout, …
struct LauncherCommand: Identifiable {
    enum Icon {
        case symbol(String, Color)
        case windowLayout(WindowPosition)
        /// The Finder icon of a file, folder or app.
        case file(String)
        /// A quicklink's own icon (the website's, once fetched).
        case quicklink(Quicklink)
        /// Whatever a shortcut for the same action shows (an alias to a menu command, say).
        case binding(BindingPresentation)
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: Icon
    var keywords: [String] = []
    /// What the row says it is ("Command", "Quicklink").
    var typeLabel = "Command"
    var actionTitle = "Run Command"
    /// The binding that runs the same thing, so its Hyper shortcut can be shown.
    var action: BoundAction?
    /// Listed when nothing is typed (otherwise only found by searching).
    var isSuggested = false
    /// Lock, sleep, shut down and the like: listed together in the System section.
    var isSystem = false
    /// Listed in the Quicklinks section of the home screen.
    var isQuicklink = false
    /// Only found by its alias, not by its title.
    var isAliasOnly = false
    /// Runs after the launcher closes. Receives the app that was in front before it opened.
    let run: @MainActor (NSRunningApplication?) -> Void
    /// For quicklinks with an `{argument}`: runs with the text typed after its alias ("gh swift").
    var runWithArgument: (@MainActor (NSRunningApplication?, String) -> Void)?
}

enum LauncherItem: Identifiable {
    case app(AppInfo)
    case command(LauncherCommand)
    /// A folder you gave a Hyper shortcut. The path is as written in the config ("~/Downloads").
    case folder(path: String)

    var id: String {
        switch self {
        case .app(let app): "app-\(app.bundleIdentifier)"
        case .command(let command): "command-\(command.id)"
        case .folder(let path): "folder-\(path)"
        }
    }

    var title: String {
        switch self {
        case .app(let app): app.name
        case .command(let command): command.title
        case .folder(let path): Self.folderName(path)
        }
    }

    var typeLabel: String {
        switch self {
        case .app: "Application"
        case .command(let command): command.typeLabel
        case .folder: "Folder"
        }
    }

    var actionTitle: String {
        switch self {
        case .app: "Open Application"
        case .command(let command): command.actionTitle
        case .folder: "Open Folder"
        }
    }

    static func folderName(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded == NSHomeDirectory() ? "Home" : FileManager.default.displayName(atPath: expanded)
    }
}

struct LauncherSection: Identifiable {
    let title: String?
    let items: [LauncherItem]

    var id: String { title ?? "results" }
}

// MARK: - Model

/// Search state for the launcher: query, ranked results and keyboard selection.
/// Results are computed once per keystroke and stored, so rendering stays cheap.
@MainActor
@Observable
final class AppSearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            recompute()
        }
    }
    var selection = 0
    /// Bumped each time the panel opens so the view re-focuses the search field.
    private(set) var focusRequest = 0
    private(set) var sections: [LauncherSection] = []
    /// All items in display order, for keyboard navigation.
    private(set) var items: [LauncherItem] = []

    private(set) var recentIds: [String] = []
    /// Item id → key, for showing an existing Hyper shortcut next to apps and commands.
    private(set) var shortcuts: [String: KeyCode] = [:]
    private(set) var hyperKey: KeyCode = .capsLock
    /// Item id → its regular shortcut (⇧⌘V), shown like the Hyper ones.
    private(set) var combos: [String: KeyCombo] = [:]
    /// Item id → its alias, shown next to the title.
    private(set) var aliasLabels: [String: String] = [:]
    /// While the query is an alias plus text ("gh swift"): the quicklink it opens and the text.
    private(set) var aliasArgument: (itemId: String, text: String)?
    private var aliasItems: [String: LauncherItem] = [:]

    let provider = InstalledAppProvider.shared
    private var runningIds: Set<String> = []
    private var candidates: [AppInfo] = []
    private var commands: [LauncherCommand] = []
    /// Folders with a Hyper shortcut in the active profile, in keyboard order.
    private(set) var folders: [String] = []
    private static let maxRecents = 8
    private static let maxRecentsShown = 5
    private static let maxResults = 30

    func prepare(bindingStore: BindingStore?, commands: [LauncherCommand], aliases: [Alias] = [], hotkeys: [GlobalShortcut] = []) {
        prepare(
            bindings: bindingStore?.activeBindings ?? [],
            hyperKey: bindingStore?.hyperKeyCode ?? .capsLock,
            commands: commands,
            aliases: aliases,
            hotkeys: hotkeys,
            commandKey: { action in bindingStore?.keyCode(for: action) }
        )
    }

    func prepare(
        bindings: [KeyBinding], hyperKey: KeyCode, commands: [LauncherCommand], aliases: [Alias] = [],
        hotkeys: [GlobalShortcut] = [], commandKey: (BoundAction) -> KeyCode? = { _ in nil }
    ) {
        provider.loadIfNeeded()
        self.commands = commands
        self.hyperKey = hyperKey
        let running = InstalledAppProvider.runningApps()
        runningIds = Set(running.map(\.bundleIdentifier))
        var seen = Set<String>()
        candidates = (running + provider.apps).filter { seen.insert($0.bundleIdentifier).inserted }
        recentIds = UserDefaults.standard.stringArray(forKey: Preferences.appSearchRecents) ?? []

        shortcuts = [:]
        folders = []
        do {
            for binding in bindings where binding.isEnabled {
                switch binding.action {
                case .launchApp(let bundleId, _):
                    shortcuts["app-\(bundleId)"] = binding.keyCode
                case .showAppGroup(let groupId):
                    // A one-app group is just that app opened into a window position.
                    if let group = AppGroupStore.shared.group(id: groupId), group.appBundleIdentifiers.count == 1 {
                        let id = "app-\(group.appBundleIdentifiers[0])"
                        shortcuts[id] = shortcuts[id] ?? binding.keyCode
                    }
                case .openFolder(let path):
                    // Only folders that still exist; the same folder on two keys is listed once.
                    let id = LauncherItem.folder(path: path).id
                    guard shortcuts[id] == nil,
                          FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) else { continue }
                    folders.append(path)
                    shortcuts[id] = binding.keyCode
                default:
                    break
                }
            }
            for command in commands {
                if let action = command.action, let key = commandKey(action) {
                    shortcuts[LauncherItem.command(command).id] = key
                }
            }
        }

        combos = [:]
        for hotkey in hotkeys where hotkey.isEnabled {
            if let item = item(for: hotkey.action) {
                combos[item.id] = hotkey.combo
            }
        }

        aliasItems = [:]
        aliasLabels = [:]
        for alias in aliases {
            guard let item = item(for: alias.action) else { continue }
            aliasItems[alias.text] = item
            aliasLabels[item.id] = alias.text
        }
        query = ""
        recompute()
    }

    /// The row that runs `action`: the app, the folder, or the command.
    private func item(for action: BoundAction) -> LauncherItem? {
        switch action {
        case .launchApp(let bundleId, _):
            return candidates.first { $0.bundleIdentifier == bundleId }.map(LauncherItem.app)
        case .openFolder(let path) where folders.contains(path):
            return .folder(path: path)
        default:
            // Prefer the regular command over the alias-only one made for the same action.
            let matching = commands.filter { $0.action == action }
            return (matching.first { !$0.isAliasOnly } ?? matching.first).map(LauncherItem.command)
        }
    }

    func requestFocus() {
        focusRequest += 1
    }

    var selectedItem: LauncherItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
    }

    func noteOpened(_ app: AppInfo) {
        var recents = recentIds.filter { $0 != app.bundleIdentifier }
        recents.insert(app.bundleIdentifier, at: 0)
        recentIds = Array(recents.prefix(Self.maxRecents))
        UserDefaults.standard.set(recentIds, forKey: Preferences.appSearchRecents)
    }

    /// Refreshes the recent-apps list (used by the settings page).
    func loadRecents() {
        recentIds = UserDefaults.standard.stringArray(forKey: Preferences.appSearchRecents) ?? []
    }

    func clearRecents() {
        recentIds = []
        UserDefaults.standard.removeObject(forKey: Preferences.appSearchRecents)
        recompute()
    }

    /// The System section on the home screen: the everyday ones. Searching "system" finds the rest.
    private var systemCommands: [LauncherCommand] {
        let order = [
            "system-lockScreen", "system-sleep", "caffeinate", "kill-process",
            "empty-trash", "system-logOut", "system-restart", "system-shutDown",
        ]
        return order.compactMap { id in commands.first { $0.id == id } }
    }

    private func recompute() {
        selection = 0
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()

        guard !needle.isEmpty else {
            // Home: apps you've opened from here, your folder shortcuts, then HyperKeys' own commands.
            let recents = recentIds.prefix(Self.maxRecentsShown).compactMap { id in
                candidates.first { $0.bundleIdentifier == id }
            }
            sections = [
                LauncherSection(title: "Recent", items: recents.map(LauncherItem.app)),
                LauncherSection(title: "Folders", items: folders.map { LauncherItem.folder(path: $0) }),
                LauncherSection(title: "Quicklinks", items: commands.filter(\.isQuicklink).map(LauncherItem.command)),
                LauncherSection(title: "Commands", items: commands.filter { $0.isSuggested && !$0.isSystem }.map(LauncherItem.command)),
                LauncherSection(title: "System", items: systemCommands.map(LauncherItem.command)),
            ].filter { !$0.items.isEmpty }
            items = sections.flatMap(\.items)
            return
        }

        var scored: [(item: LauncherItem, score: Int)] = []
        // "gh swift": an alias, then the text for its quicklink's argument.
        aliasArgument = nil
        if let space = needle.firstIndex(of: " "),
           let item = aliasItems[String(needle[..<space])],
           case .command(let command) = item, command.runWithArgument != nil {
            let typed = query.trimmingCharacters(in: .whitespaces)
            let text = typed[typed.index(after: typed.firstIndex(of: " ") ?? typed.startIndex)...]
                .trimmingCharacters(in: .whitespaces)
            aliasArgument = (item.id, text)
            scored.append((item, 3000))
        }
        func aliasScore(_ id: String) -> Int? {
            guard let alias = aliasLabels[id], aliasArgument?.itemId != id else { return nil }
            if alias == needle { return 2000 }
            return alias.hasPrefix(needle) ? 950 : nil
        }

        for app in candidates {
            let id = LauncherItem.app(app).id
            let alias = aliasScore(id)
            guard var score = Self.score(app.name.lowercased(), query: needle) ?? alias else { continue }
            if runningIds.contains(app.bundleIdentifier) { score += 25 }
            if let index = recentIds.firstIndex(of: app.bundleIdentifier) { score += 60 - index * 5 }
            scored.append((.app(app), max(score, alias ?? 0)))
        }
        for path in folders {
            // Match the folder's name or its path ("down" → Downloads, "dev/proj" → ~/Developer/projects).
            let scores = [LauncherItem.folderName(path), path, "folder"].compactMap { Self.score($0.lowercased(), query: needle) }
            let alias = aliasScore(LauncherItem.folder(path: path).id)
            if let best = [scores.max().map { $0 + 20 }, alias].compactMap(\.self).max() {
                scored.append((.folder(path: path), best))
            }
        }
        for command in commands {
            let names = command.isAliasOnly ? [] : [command.title] + command.keywords
            let scores = names.compactMap { Self.score($0.lowercased(), query: needle) }
            let alias = aliasScore(LauncherItem.command(command).id)
            if let best = [scores.max(), alias].compactMap(\.self).max() {
                scored.append((.command(command), best))
            }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score
                ? lhs.score > rhs.score
                : lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
        }
        items = Array(scored.prefix(Self.maxResults).map(\.item))
        sections = [LauncherSection(title: nil, items: items)]
    }

    /// Higher is better; nil means no match. Exact > prefix > word prefix > initials > substring > in-order letters.
    static func score(_ name: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if name == query { return 1000 }
        if name.hasPrefix(query) { return 900 - name.count }

        let words = name.split { $0 == " " || $0 == "-" || $0 == "." || $0 == "_" }
        if words.contains(where: { $0.hasPrefix(query) }) { return 750 - name.count }

        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(query) { return 700 - name.count }

        if name.contains(query) { return 500 - name.count }

        var remaining = Substring(name)
        for character in query {
            guard let index = remaining.firstIndex(of: character) else { return nil }
            remaining = remaining[remaining.index(after: index)...]
        }
        return 200 - name.count
    }
}

// MARK: - Controller

@MainActor
public final class AppSearchController {
    public static let shared = AppSearchController()

    /// Used to show existing shortcuts next to apps and commands.
    public var bindingStore: BindingStore?
    /// Live status, for the Pause / Resume command; provided by the app layer.
    public var status: HyperKeyStatus?
    /// Pauses or resumes all shortcuts; provided by the app layer.
    public var onSetPaused: ((Bool) -> Void)?
    /// Runs any action, for aliases to things App Search doesn't list (a menu command, say).
    public var perform: ((BoundAction) -> Void)?

    let model = AppSearchModel()
    static let width: CGFloat = 640
    private var host: FloatingPanelHost?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    /// Builds the panel ahead of time so the first Hyper + Space is instant.
    public func warmUp() {
        InstalledAppProvider.shared.loadIfNeeded()
        _ = makeHostIfNeeded()
    }

    public func show() {
        let host = makeHostIfNeeded()
        model.prepare(
            bindingStore: bindingStore, commands: makeCommands(),
            aliases: AliasStore.shared.aliases, hotkeys: GlobalShortcutStore.shared.shortcuts
        )
        host.show()
        // Focus once the panel is actually key, otherwise the first keystrokes can be lost.
        DispatchQueue.main.async { [model] in
            model.requestFocus()
        }
    }

    public func hide() {
        host?.hide(restoringFocus: true)
    }

    func run(_ item: LauncherItem) {
        switch item {
        case .app(let app):
            open(app)
        case .command(let command):
            let previousApp = host?.previousApp
            let argument = model.aliasArgument.flatMap { $0.itemId == item.id ? $0.text : nil }
            // Commands that open another panel or move a window manage focus themselves.
            host?.hide(restoringFocus: false)
            if let argument, let runWithArgument = command.runWithArgument {
                runWithArgument(previousApp, argument)
            } else {
                command.run(previousApp)
            }
        case .folder(let path):
            host?.hide(restoringFocus: false)
            SystemCommands.open(path: path)
        }
    }

    func open(_ app: AppInfo) {
        host?.hide(restoringFocus: false)
        model.noteOpened(app)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
    }

    func reveal(_ app: AppInfo) {
        host?.hide(restoringFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func openSettings() {
        // Open the window while HyperKeys still has focus, then close the panel.
        HyperKeysWindow.open(on: .appSearch)
        DispatchQueue.main.async { [weak self] in
            self?.host?.hide(restoringFocus: false)
        }
    }

    // MARK: Commands

    func makeCommands() -> [LauncherCommand] {
        let isPaused = status?.isPaused ?? false
        var commands: [LauncherCommand] = [
            LauncherCommand(
                id: "emoji", title: "Emoji & Symbols", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.emojiPicker.symbol, ActionKind.emojiPicker.color),
                keywords: ["emoji", "symbols", "characters", "emoticon", "smiley"],
                action: .emojiPicker, isSuggested: true
            ) { previousApp in
                EmojiPickerController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "switcher", title: "Switch Apps", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.appSwitcher.symbol, ActionKind.appSwitcher.color),
                keywords: ["switcher", "windows", "app switcher", "tab"],
                action: .appSwitcher, isSuggested: true
            ) { previousApp in
                AppSwitcherController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "snippets", title: "Search Snippets", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.snippets.symbol, ActionKind.snippets.color),
                keywords: ["snippets", "text", "paste", "templates"],
                action: .snippets, isSuggested: true
            ) { previousApp in
                SnippetsPanelController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "clipboard", title: "Clipboard History", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.clipboardHistory.symbol, ActionKind.clipboardHistory.color),
                keywords: ["clipboard", "history", "copied", "paste", "pasteboard"],
                action: .clipboardHistory, isSuggested: true
            ) { previousApp in
                ClipboardHistoryPanelController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "menu-search", title: "Search Menu Items", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.menuSearch.symbol, ActionKind.menuSearch.color),
                keywords: ["menu", "menu bar", "menu items", "commands", "actions"],
                action: .menuSearch, isSuggested: true
            ) { previousApp in
                MenuSearchController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "gif-search", title: "Search GIFs", subtitle: "HyperKeys",
                icon: .symbol(ActionKind.gifSearch.symbol, ActionKind.gifSearch.color),
                keywords: ["gif", "gifs", "giphy", "klipy", "clips", "meme", "reaction", "sticker"],
                action: .gifSearch, isSuggested: true
            ) { previousApp in
                GifSearchController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "new-snippet", title: "Create Snippet", subtitle: "HyperKeys",
                icon: .symbol("plus", ActionKind.snippets.color),
                keywords: ["new snippet", "add snippet", "snippets"]
            ) { _ in
                NavigationRequests.shared.snippet = .create
                HyperKeysWindow.open(on: .snippets)
            },
            LauncherCommand(
                id: "empty-trash", title: "Empty Trash", subtitle: "System",
                icon: .symbol(ActionKind.emptyTrash.symbol, ActionKind.emptyTrash.color),
                keywords: ["trash", "bin", "recycle bin", "delete", "system"],
                action: .emptyTrash, isSystem: true
            ) { previousApp in
                SystemCommands.emptyTrash()
                previousApp?.activate()
            },
            LauncherCommand(
                id: "kill-process", title: "Kill Process", subtitle: "System",
                icon: .symbol(ActionKind.killProcess.symbol, ActionKind.killProcess.color),
                keywords: ["kill", "process", "processes", "quit", "force quit", "activity monitor", "cpu", "memory", "system"],
                action: .killProcess, isSystem: true
            ) { previousApp in
                KillProcessController.shared.show(returningTo: previousApp)
            },
            LauncherCommand(
                id: "caffeinate",
                title: Caffeinate.shared.isActive ? "Decaffeinate" : "Caffeinate",
                subtitle: Caffeinate.shared.isActive ? "Keeping your Mac awake" : "Keep your Mac awake",
                icon: .symbol(SystemAction.caffeinate.symbol, .brown),
                keywords: ["caffeinate", "decaffeinate"] + SystemAction.caffeinate.keywords + ["system"],
                action: .system(.caffeinate), isSystem: true
            ) { previousApp in
                Caffeinate.shared.toggle()
                previousApp?.activate()
            },
            LauncherCommand(
                id: "settings", title: "HyperKeys Settings", subtitle: "HyperKeys",
                icon: .symbol("gearshape.fill", .gray),
                keywords: ["settings", "preferences", "configure", "shortcuts", "hyperkeys"],
                isSuggested: true
            ) { _ in
                HyperKeysWindow.open?()
            },
            LauncherCommand(
                id: "pause", title: isPaused ? "Resume Shortcuts" : "Pause Shortcuts", subtitle: "HyperKeys",
                icon: .symbol(isPaused ? "play.fill" : "pause.fill", isPaused ? .green : .orange),
                keywords: ["pause", "resume", "disable", "enable", "turn off", "turn on"],
                isSuggested: true
            ) { [weak self] previousApp in
                previousApp?.activate()
                self?.onSetPaused?(!isPaused)
            },
            LauncherCommand(
                id: "quit", title: "Quit HyperKeys", subtitle: "HyperKeys",
                icon: .symbol("power", .red),
                keywords: ["quit", "exit"]
            ) { _ in
                NSApp.terminate(nil)
            },
        ]

        for action in SystemAction.allCases where action != .caffeinate {
            commands.append(LauncherCommand(
                id: "system-\(action.rawValue)", title: action.title, subtitle: "System",
                icon: .symbol(action.symbol, ActionKind.system.color),
                keywords: action.keywords + ["system"],
                action: .system(action), isSystem: true
            ) { previousApp in
                previousApp?.activate()
                SystemCommands.run(action)
            })
        }

        for quicklink in QuicklinkStore.shared.quicklinks {
            var command = LauncherCommand(
                id: "quicklink-\(quicklink.id.uuidString)", title: quicklink.name, subtitle: quicklink.displayLink,
                icon: .quicklink(quicklink),
                keywords: [quicklink.displayLink, "quicklink", "link"],
                typeLabel: "Quicklink", actionTitle: "Open Quicklink",
                action: .quicklink(name: quicklink.name), isQuicklink: true
            ) { previousApp in
                QuicklinkRunner.open(quicklink, from: previousApp)
            }
            if !Placeholders.arguments(in: quicklink.link).isEmpty {
                command.runWithArgument = { previousApp, text in
                    QuicklinkRunner.open(quicklink, from: previousApp, argument: text)
                }
            }
            commands.append(command)
        }

        // Every window layout, found by searching ("left half", "center", …).
        for position in WindowPosition.allCases {
            commands.append(LauncherCommand(
                id: "window-\(position.rawValue)", title: position.displayName, subtitle: "Window Layout",
                icon: .windowLayout(position),
                keywords: ["window", "move", "snap", "resize", position.category.displayName],
                action: .windowAction(position)
            ) { previousApp in
                guard let previousApp else { return }
                previousApp.activate()
                if let bundleId = previousApp.bundleIdentifier {
                    WindowManager.moveWindow(to: position, ofApp: bundleId)
                }
            })
        }
        commands += aliasOnlyCommands(besides: commands)
        return commands
    }

    /// Aliases can name anything a shortcut can. Those App Search doesn't otherwise list
    /// (a menu command, a group of apps, a folder without a shortcut) get a row of their own,
    /// found only by the alias. Apps are left to the app list.
    func aliasOnlyCommands(besides commands: [LauncherCommand], aliases: [Alias] = AliasStore.shared.aliases) -> [LauncherCommand] {
        let listed = Set(commands.compactMap(\.action))
        return aliases.compactMap { alias in
            if case .launchApp = alias.action { return nil }
            guard !listed.contains(alias.action), let presentation = BindingPresentation(alias.action) else { return nil }
            let action = alias.action
            return LauncherCommand(
                id: "alias-\(alias.id.uuidString)", title: presentation.title, subtitle: presentation.summary,
                icon: .binding(presentation), typeLabel: presentation.kind.title, actionTitle: "Run",
                action: action, isAliasOnly: true
            ) { [weak self] previousApp in
                previousApp?.activate()
                self?.perform?(action)
            }
        }
    }

    // MARK: Panel

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = AppSearchLauncherView(
            model: model,
            onRun: { [weak self] in self?.run($0) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let host = FloatingPanelHost(width: Self.width, rootView: root)
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // escape
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 125: // down
            model.moveSelection(by: 1)
            return true
        case 126: // up
            model.moveSelection(by: -1)
            return true
        case 36, 76: // return, enter
            guard let item = model.selectedItem else { return true }
            if flags.contains(.command), case .app(let app) = item {
                reveal(app)
            } else if flags.contains(.command), case .folder(let path) = item {
                host?.hide(restoringFocus: false)
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
            } else {
                run(item)
            }
            return true
        default:
            // Emacs-style ⌃N / ⌃P, as in Raycast and Spotlight.
            if flags == .control, event.charactersIgnoringModifiers == "n" {
                model.moveSelection(by: 1)
                return true
            }
            if flags == .control, event.charactersIgnoringModifiers == "p" {
                model.moveSelection(by: -1)
                return true
            }
            return false
        }
    }
}
