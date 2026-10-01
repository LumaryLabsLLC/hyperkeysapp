import AppKit
import AppSwitcher
import EventEngine
import Shared
import SwiftUI

// MARK: - Model

/// One tile in the switcher: a single window (or a windowless app), or a stack of an app's windows.
struct SwitcherItem: Identifiable {
    let windows: [OpenWindowEntry]

    var id: String { isStack ? "stack-\(pid)" : windows[0].id }
    var app: AppInfo { windows[0].app }
    var pid: pid_t { windows[0].pid }
    var isStack: Bool { windows.count > 1 }
    /// The app's most recently used window.
    var frontWindow: OpenWindowEntry { windows[0] }
}

@MainActor
@Observable
final class AppSwitcherModel {
    static let columns = 5

    enum Move {
        case next, previous, up, down
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    /// True while the hyper key is held (⌘-Tab style): just the grid, release to switch.
    var isHoldMode = false
    /// Stay-open mode only: "/" was pressed and typing now filters the grid.
    var isFiltering = false
    /// Stay-open mode only: "f" was pressed and each tile shows a letter to jump to (like Vimium).
    var isHinting = false
    /// Letters typed so far while hinting.
    var hintInput = ""

    /// Home row first, like Vimium, so the most common jumps are the easiest to type.
    static let hintAlphabet = Array("asdfjklghqweruiopzxcvbnmty")
    private(set) var items: [SwitcherItem] = []
    /// The app whose stack is opened up to show its individual windows.
    private(set) var expandedApp: AppInfo?
    private var expandedPid: pid_t?
    private var all: [OpenWindowEntry] = []

    var isExpanded: Bool { expandedPid != nil }

    /// Loads windows in most-recently-used order and pre-selects the most recent *other* app,
    /// so a quick tap flips back to it like ⌘-Tab.
    func load() {
        load(entries: OpenWindows.entries())
    }

    func load(entries: [OpenWindowEntry]) {
        all = entries
        isFiltering = false
        isHinting = false
        hintInput = ""
        expandedPid = nil
        expandedApp = nil
        query = ""
        rebuild()
        if let current = items.first?.pid {
            selection = items.firstIndex { $0.pid != current } ?? 0
        } else {
            selection = 0
        }
    }

    var selectedItem: SwitcherItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    /// Opens a stack to show that app's windows.
    func expand(_ item: SwitcherItem) {
        expandedPid = item.pid
        expandedApp = item.app
        rebuild()
        selection = 0
    }

    /// Back from an opened stack to all apps, keeping that app selected.
    func collapse() {
        let pid = expandedPid
        expandedPid = nil
        expandedApp = nil
        rebuild()
        selection = items.firstIndex { $0.pid == pid } ?? 0
    }

    func move(_ move: Move) {
        guard !items.isEmpty else { return }
        switch move {
        case .next:
            selection = (selection + 1) % items.count
        case .previous:
            selection = (selection - 1 + items.count) % items.count
        case .down, .up:
            // Stay in the same column; stop at the edges.
            let target = selection + (move == .down ? Self.columns : -Self.columns)
            if items.indices.contains(target) {
                selection = target
            }
        }
    }

    /// One label per tile: single letters when they suffice, otherwise two-letter pairs
    /// (all the same length, so no label is a prefix of another).
    var hintLabels: [String] {
        let alphabet = Self.hintAlphabet
        if items.count <= alphabet.count {
            return alphabet.prefix(items.count).map { String($0) }
        }
        var labels: [String] = []
        for first in alphabet {
            for second in alphabet {
                labels.append(String([first, second]))
                if labels.count == items.count { return labels }
            }
        }
        return labels
    }

    private func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matches: (OpenWindowEntry) -> Bool = { entry in
            needle.isEmpty
                || entry.app.name.localizedCaseInsensitiveContains(needle)
                || (entry.windowTitle?.localizedCaseInsensitiveContains(needle) ?? false)
        }

        if let expandedPid {
            items = all.filter { $0.pid == expandedPid && matches($0) }.map { SwitcherItem(windows: [$0]) }
        } else if !needle.isEmpty {
            // Searching shows matching windows individually, so stacks open up.
            items = all.filter(matches).map { SwitcherItem(windows: [$0]) }
        } else {
            // One tile per app; apps with several windows become a stack.
            var order: [pid_t] = []
            var byApp: [pid_t: [OpenWindowEntry]] = [:]
            for entry in all {
                if byApp[entry.pid] == nil { order.append(entry.pid) }
                byApp[entry.pid, default: []].append(entry)
            }
            items = order.compactMap { byApp[$0].map(SwitcherItem.init(windows:)) }
        }
    }
}

// MARK: - Controller

/// A grid of open apps and their windows, in one of two styles (see `Preferences.switcherStaysOpen`):
/// - Hold to switch (default, like ⌘-Tab): hold Hyper, tap the shortcut to move, release to switch.
///   A quick tap jumps straight back to the previous app.
/// - Stay open: the shortcut opens the grid; move with h j k l / arrows / Tab, Return switches,
///   Esc closes, "/" filters. Opening it from the menu bar always uses this style.
@MainActor
public final class AppSwitcherController {
    public static let shared = AppSwitcherController()

    let model = AppSwitcherModel()
    static let width: CGFloat = AppSwitcherView.gridWidth
    /// Like ⌘-Tab, a quick tap-and-release switches without the grid ever flashing on screen.
    private static let revealDelay: Duration = .milliseconds(110)

    /// Whether the physical hyper key is down right now; provided by the app layer.
    public var isHyperKeyDown: () -> Bool = { true }
    /// Whether Shift + switcher key steps backwards (not when Shift is part of the hyper key).
    public var reversesWithShift: () -> Bool = { true }

    private var host: FloatingPanelHost?
    private var isHoldSession = false
    private var revealTask: Task<Void, Never>?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    /// True while hyper combos should go to the switcher instead of running shortcuts.
    public var isCapturingHyperKeys: Bool {
        isHoldSession || isVisible
    }

    public func warmUp() {
        _ = makeHostIfNeeded()
    }

    // MARK: Hyper key input

    /// The switcher shortcut was pressed with the hyper key held.
    public func shortcutPressed() {
        if isCapturingHyperKeys {
            model.move(backwards ? .previous : .next)
            return
        }
        if Preferences.isSwitcherStayOpen {
            show()
        } else {
            beginHoldSession()
        }
    }

    /// Hyper combos while the switcher is up. Returns true when consumed, so no other shortcut runs.
    public func handleHeldKey(_ key: KeyCode, switcherKey: KeyCode?) -> Bool {
        guard isCapturingHyperKeys else { return false }
        // Hints work even if Hyper is still held when the letters are typed.
        if !isHoldSession, model.isHinting, key != .escape {
            if key == .delete {
                removeHintCharacter()
            } else if let character = key.displayLabel.lowercased().first, key.displayLabel.count == 1 {
                typeHintCharacter(character)
            }
            return true
        }
        if !isHoldSession, key == .f {
            startHinting()
            return true
        }
        if let move = move(for: key, switcherKey: switcherKey) {
            model.move(move)
        } else if key == .escape {
            isHoldSession ? endHoldSession() : back()
        } else if key == .slash, !isHoldSession {
            // "/" pressed before letting go of Hyper still starts filtering.
            startFiltering()
        } else if key == .returnKey || key == .space {
            if let item = model.selectedItem { activate(item) }
        }
        // Everything else is swallowed so nothing fires mid-switch.
        return true
    }

    /// Auto-repeat of a held combo key: holding Tab (or h j k l, arrows) keeps moving.
    public func handleRepeat(_ key: KeyCode, switcherKey: KeyCode?) {
        guard isCapturingHyperKeys, let move = move(for: key, switcherKey: switcherKey) else { return }
        model.move(move)
    }

    /// The hyper key was released: in hold-to-switch style, switch to the selection.
    public func hyperKeyReleased() {
        guard isHoldSession else { return }
        // Like ⌘-Tab, releasing on a stack brings back that app's most recent window.
        let entry = model.selectedItem?.frontWindow
        endHoldSession()
        if let entry {
            OpenWindows.focus(entry)
        }
    }

    private var backwards: Bool {
        reversesWithShift() && NSEvent.modifierFlags.contains(.shift)
    }

    private func move(for key: KeyCode, switcherKey: KeyCode?) -> AppSwitcherModel.Move? {
        switch key {
        case switcherKey, .tab: backwards ? .previous : .next
        case .grave, .h, .leftArrow: .previous
        case .l, .rightArrow: .next
        case .j, .downArrow: .down
        case .k, .upArrow: .up
        default: nil
        }
    }

    // MARK: Hold-to-switch session

    private func beginHoldSession() {
        isHoldSession = true
        model.isHoldMode = true
        model.load()

        // Hyper already released (a quick tap): switch straight to the previous app.
        guard isHyperKeyDown() else {
            hyperKeyReleased()
            return
        }

        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            guard let self, !Task.isCancelled, self.isHoldSession else { return }
            self.makeHostIfNeeded().show(takingFocus: false)
        }
    }

    private func endHoldSession() {
        isHoldSession = false
        revealTask?.cancel()
        revealTask = nil
        host?.hide(restoringFocus: false)
        model.isHoldMode = false
    }

    // MARK: Stay-open style

    /// Opens the grid until something is chosen (also used by the menu bar and "Try It").
    public func show(returningTo app: NSRunningApplication? = nil) {
        if isHoldSession { endHoldSession() }
        let host = makeHostIfNeeded()
        model.isHoldMode = false
        // Read window order before the panel itself takes focus.
        model.load()
        host.show(returningTo: app)
    }

    public func hide() {
        host?.hide(restoringFocus: true)
    }

    /// Click or Return on a tile: a stack opens to show its windows (except mid hold-to-switch,
    /// where it switches to the app's front window); a single window is switched to.
    func activate(_ item: SwitcherItem) {
        if item.isStack, !isHoldSession {
            model.expand(item)
        } else {
            choose(item.frontWindow)
        }
    }

    /// Esc: leave hints or the filter, then an opened stack, then close.
    private func back() {
        if model.isHinting {
            stopHinting()
        } else if model.isFiltering {
            model.isFiltering = false
            model.query = ""
        } else if model.isExpanded {
            model.collapse()
        } else {
            hide()
        }
    }

    func choose(_ entry: OpenWindowEntry) {
        if isHoldSession {
            isHoldSession = false
            revealTask?.cancel()
            model.isHoldMode = false
        }
        host?.hide(restoringFocus: false)
        OpenWindows.focus(entry)
    }

    // MARK: Vimium-style hints

    private func startHinting() {
        model.isFiltering = false
        model.hintInput = ""
        model.isHinting = !model.items.isEmpty
    }

    private func stopHinting() {
        model.isHinting = false
        model.hintInput = ""
    }

    private func typeHintCharacter(_ character: Character) {
        let typed = model.hintInput + String(character)
        let labels = model.hintLabels
        guard labels.contains(where: { $0.hasPrefix(typed) }) else {
            NSSound.beep()
            return
        }
        model.hintInput = typed
        guard let index = labels.firstIndex(of: typed) else { return }

        let item = model.items[index]
        model.selection = index
        stopHinting()
        if item.isStack {
            // Open the stack and go straight to hints for its windows.
            model.expand(item)
            startHinting()
        } else {
            choose(item.frontWindow)
        }
    }

    private func removeHintCharacter() {
        if model.hintInput.isEmpty {
            stopHinting()
        } else {
            model.hintInput.removeLast()
        }
    }

    private func startFiltering() {
        stopHinting()
        model.isFiltering = true
        // The field appears and focuses itself; make sure the panel is the key window for typing.
        host?.panel.makeKey()
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = AppSwitcherView(
            model: model,
            onActivate: { [weak self] in self?.activate($0) },
            onBack: { [weak self] in self?.back() }
        )
        let host = FloatingPanelHost(width: Self.width, rootView: root)
        host.topFraction = 0.24
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    /// Plain key presses while the stay-open grid has focus.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if model.isHinting {
            switch event.keyCode {
            case 53: stopHinting()          // escape
            case 51: removeHintCharacter()  // delete
            default:
                if let character = characters.lowercased().first, character.isLetter {
                    typeHintCharacter(character)
                }
            }
            return true
        }

        // Always: arrows, Tab, Return, Escape.
        switch event.keyCode {
        case 53: // escape
            back()
            return true
        case 48: // tab
            model.move(flags.contains(.shift) ? .previous : .next)
            return true
        case 123: model.move(.previous); return true
        case 124: model.move(.next); return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        case 36, 76: // return, enter
            if let item = model.selectedItem { activate(item) }
            return true
        case 51 where model.isExpanded && !model.isFiltering: // delete: back to all apps
            model.collapse()
            return true
        default:
            break
        }

        // While filtering, everything else is typing.
        guard !model.isFiltering else { return false }

        switch characters {
        case "h": model.move(.previous)
        case "l": model.move(.next)
        case "j": model.move(.down)
        case "k": model.move(.up)
        case "f": startHinting()
        case "/":
            startFiltering()
        default:
            break
        }
        return true
    }
}
