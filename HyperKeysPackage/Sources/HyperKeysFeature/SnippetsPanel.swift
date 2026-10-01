import AppKit
import KeyBindings
import SwiftUI

// MARK: - Model

struct SnippetSection: Identifiable {
    let title: String
    let snippets: [Snippet]

    var id: String { title }
}

@MainActor
@Observable
final class SnippetsPanelModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    /// nil shows every tag.
    var tag: String? {
        didSet {
            guard tag != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    var targetAppName: String?
    private(set) var focusRequest = 0
    private(set) var sections: [SnippetSection] = []
    /// All visible snippets in display order, for keyboard navigation.
    private(set) var items: [Snippet] = []

    let store: SnippetStore

    init(store: SnippetStore = .shared) {
        self.store = store
    }

    func prepare() {
        query = ""
        tag = nil
        rebuild()
        selection = 0
        requestFocus()
    }

    func requestFocus() {
        focusRequest += 1
    }

    var selectedSnippet: Snippet? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    func rebuild(now: Date = Date()) {
        var pool = store.snippets
        if let tag {
            pool = pool.filter { $0.tags.contains(tag) }
        }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            // Name matches first, then tags, then the text itself.
            let ranked = pool.compactMap { snippet -> (Snippet, Int)? in
                let name = snippet.name.lowercased()
                if snippet.keyword?.lowercased() == needle { return (snippet, 4) }
                if name.hasPrefix(needle) { return (snippet, 3) }
                if name.contains(needle) { return (snippet, 2) }
                if snippet.tags.contains(where: { $0.lowercased().contains(needle) }) { return (snippet, 1) }
                if snippet.text.lowercased().contains(needle) { return (snippet, 0) }
                return nil
            }
            let sorted = ranked.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
            sections = [SnippetSection(title: "Results", snippets: sorted.map(\.0))]
        } else {
            sections = Self.groupedByLastUse(pool, usage: store.usage, now: now)
        }
        sections.removeAll { $0.snippets.isEmpty }
        items = sections.flatMap(\.snippets)
    }

    /// Today / This Week / Earlier by when each snippet was last pasted, then the ones never used.
    static func groupedByLastUse(_ snippets: [Snippet], usage: [String: SnippetUsage], now: Date) -> [SnippetSection] {
        let calendar = Calendar.current
        var today: [Snippet] = [], week: [Snippet] = [], earlier: [Snippet] = [], unused: [Snippet] = []

        let byRecency = snippets.sorted { (usage[$0.name]?.lastUsed ?? .distantPast) > (usage[$1.name]?.lastUsed ?? .distantPast) }
        for snippet in byRecency {
            guard let lastUsed = usage[snippet.name]?.lastUsed else {
                unused.append(snippet)
                continue
            }
            if calendar.isDate(lastUsed, inSameDayAs: now) {
                today.append(snippet)
            } else if let days = calendar.dateComponents([.day], from: lastUsed, to: now).day, days < 7 {
                week.append(snippet)
            } else {
                earlier.append(snippet)
            }
        }
        unused.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return [
            SnippetSection(title: "Today", snippets: today),
            SnippetSection(title: "This Week", snippets: week),
            SnippetSection(title: "Earlier", snippets: earlier),
            SnippetSection(title: today.isEmpty && week.isEmpty && earlier.isEmpty ? "Snippets" : "Not Used Yet", snippets: unused),
        ]
    }
}

// MARK: - Controller

/// Raycast-style snippet search. Return pastes into the app you were in; ⌘Return copies.
@MainActor
public final class SnippetsPanelController {
    public static let shared = SnippetsPanelController()

    let model = SnippetsPanelModel()
    private var host: FloatingPanelHost?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    public func warmUp() {
        _ = makeHostIfNeeded()
    }

    public func show(returningTo app: NSRunningApplication? = nil) {
        let host = makeHostIfNeeded()
        model.prepare()
        host.show(returningTo: app)
        model.targetAppName = host.previousApp?.localizedName
        DispatchQueue.main.async { [model] in
            model.requestFocus()
        }
    }

    public func hide() {
        host?.hide(restoringFocus: true)
    }

    func insert(_ snippet: Snippet, paste: Bool) {
        let app = host?.previousApp
        let store = model.store
        host?.hide(restoringFocus: true)
        Task {
            // Asks for any {argument}s, reads {selection}, fills in the rest.
            guard let text = await PlaceholderFiller.fill(snippet.text, title: snippet.name, app: app) else { return }
            store.recordUse(of: snippet)
            TextPaster.deliver(text, paste: paste)
        }
    }

    /// Opens the Snippets page to create a new snippet, or edit one.
    func openEditor(for snippet: Snippet?) {
        NavigationRequests.shared.snippet = snippet.map { .edit($0.id) } ?? .create
        HyperKeysWindow.open(on: .snippets)
        DispatchQueue.main.async { [weak self] in
            self?.host?.hide(restoringFocus: false)
        }
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = SnippetsPanelView(
            model: model,
            onInsert: { [weak self] snippet, paste in self?.insert(snippet, paste: paste) },
            onNew: { [weak self] in self?.openEditor(for: nil) }
        )
        let host = FloatingPanelHost(width: SnippetsPanelView.width, rootView: root)
        host.topFraction = 0.18
        host.settingsPane = .snippets
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        switch event.keyCode {
        case 53: // escape
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 125: model.moveSelection(by: 1); return true
        case 126: model.moveSelection(by: -1); return true
        case 36, 76: // return, enter
            if let snippet = model.selectedSnippet {
                insert(snippet, paste: !flags.contains(.command))
            }
            return true
        default:
            break
        }

        if flags == .command, characters == "n" {
            openEditor(for: nil)
            return true
        }
        if flags == .command, characters == "e", let snippet = model.selectedSnippet {
            openEditor(for: snippet)
            return true
        }
        if flags == .control, characters == "n" {
            model.moveSelection(by: 1)
            return true
        }
        if flags == .control, characters == "p" {
            model.moveSelection(by: -1)
            return true
        }
        return false
    }
}
