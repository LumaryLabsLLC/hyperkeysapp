import AppKit
import EventEngine
import KeyBindings
import SwiftUI

// MARK: - Model

struct ClipboardSection: Identifiable {
    let title: String
    let items: [ClipboardItem]

    var id: String { title }
}

@MainActor
@Observable
final class ClipboardHistoryPanelModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    /// nil shows every kind.
    var kindFilter: ClipboardItem.Kind? {
        didSet {
            guard kindFilter != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    var targetAppName: String?
    private(set) var focusRequest = 0
    private(set) var sections: [ClipboardSection] = []
    /// All visible items in display order, for keyboard navigation and ⌘1–9.
    private(set) var items: [ClipboardItem] = []

    let store: ClipboardHistoryStore
    @ObservationIgnored private var images: [UUID: NSImage] = [:]

    init(store: ClipboardHistoryStore = .shared) {
        self.store = store
    }

    func prepare() {
        query = ""
        kindFilter = nil
        images.removeAll()
        rebuild()
        selection = 0
        requestFocus()
    }

    func requestFocus() {
        focusRequest += 1
    }

    var selectedItem: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    /// Keeps the selection on the same row after the list changes underneath it.
    func rebuildKeepingSelection() {
        let selectedId = selectedItem?.id
        rebuild()
        if let selectedId, let index = items.firstIndex(where: { $0.id == selectedId }) {
            selection = index
        } else {
            selection = min(selection, max(items.count - 1, 0))
        }
    }

    func rebuild(now: Date = Date()) {
        var pool = store.items
        if let kindFilter {
            pool = pool.filter { $0.kind == kindFilter }
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            pool = pool.filter { Self.matches($0, needle) }
        }
        sections = Self.sections(pool, now: now).filter { !$0.items.isEmpty }
        items = sections.flatMap(\.items)
    }

    static func matches(_ item: ClipboardItem, _ needle: String) -> Bool {
        item.text.localizedCaseInsensitiveContains(needle)
            || (item.sourceName?.localizedCaseInsensitiveContains(needle) ?? false)
            || item.kind.title.localizedCaseInsensitiveContains(needle)
    }

    /// Pinned first, then Today / Yesterday / This Week / Earlier, newest first within each.
    static func sections(_ items: [ClipboardItem], now: Date) -> [ClipboardSection] {
        let calendar = Calendar.current
        var pinned: [ClipboardItem] = [], today: [ClipboardItem] = [], yesterday: [ClipboardItem] = []
        var week: [ClipboardItem] = [], earlier: [ClipboardItem] = []
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        for item in items.sorted(by: { $0.copiedAt > $1.copiedAt }) {
            if item.isPinned {
                pinned.append(item)
            } else if calendar.isDate(item.copiedAt, inSameDayAs: now) {
                today.append(item)
            } else if calendar.isDate(item.copiedAt, inSameDayAs: dayBefore) {
                yesterday.append(item)
            } else if let days = calendar.dateComponents([.day], from: item.copiedAt, to: now).day, days < 7 {
                week.append(item)
            } else {
                earlier.append(item)
            }
        }
        return [
            ClipboardSection(title: "Pinned", items: pinned),
            ClipboardSection(title: "Today", items: today),
            ClipboardSection(title: "Yesterday", items: yesterday),
            ClipboardSection(title: "This Week", items: week),
            ClipboardSection(title: "Earlier", items: earlier),
        ]
    }

    /// The picture for an image item, loaded once per showing.
    func image(for item: ClipboardItem) -> NSImage? {
        if let cached = images[item.id] { return cached }
        guard let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        images[item.id] = image
        return image
    }
}

// MARK: - Controller

/// Raycast-style clipboard history. Return pastes into the app you were in; ⌘Return copies.
@MainActor
public final class ClipboardHistoryPanelController {
    public static let shared = ClipboardHistoryPanelController()

    let model = ClipboardHistoryPanelModel()
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

    func insert(_ item: ClipboardItem, paste: Bool) {
        let store = model.store
        host?.hide(restoringFocus: true)
        ClipboardWriter.write(item, imageURL: store.imageURL(for: item))
        store.markUsed(id: item.id)
        if paste {
            TextPaster.pasteSoon()
        }
    }

    func togglePin(_ item: ClipboardItem) {
        model.store.togglePin(id: item.id)
        model.rebuildKeepingSelection()
    }

    func delete(_ item: ClipboardItem) {
        model.store.delete(id: item.id)
        model.rebuildKeepingSelection()
    }

    func openSettings() {
        HyperKeysWindow.open(on: .clipboard)
        DispatchQueue.main.async { [weak self] in
            self?.host?.hide(restoringFocus: false)
        }
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = ClipboardHistoryPanelView(
            model: model,
            onInsert: { [weak self] item, paste in self?.insert(item, paste: paste) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let host = FloatingPanelHost(width: ClipboardHistoryPanelView.width, rootView: root)
        host.topFraction = 0.18
        host.settingsPane = .clipboard
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
            if let item = model.selectedItem {
                insert(item, paste: !flags.contains(.command))
            }
            return true
        case 51 where flags == .command: // ⌘⌫
            if let item = model.selectedItem {
                delete(item)
            }
            return true
        default:
            break
        }

        if flags == .command, characters == "p", let item = model.selectedItem {
            togglePin(item)
            return true
        }
        // ⌘1–⌘9 paste the item in that position.
        if flags == .command, let digit = Int(characters), (1...9).contains(digit) {
            if model.items.indices.contains(digit - 1) {
                insert(model.items[digit - 1], paste: true)
            }
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
