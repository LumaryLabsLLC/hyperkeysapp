import AppKit
import SwiftUI

// MARK: - Model

@MainActor
@Observable
final class EmojiPickerModel {
    static let columns = 8
    private static let recentCount = 16

    enum Move {
        case left, right, up, down, top, bottom
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    /// nil shows all categories.
    var category: String? {
        didSet {
            guard category != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    /// Vim-style normal mode: the search field lets go of the keyboard and h j k l move.
    var isNavigating = false
    /// Name of the app the emoji will be pasted into.
    var targetAppName: String?
    private(set) var focusRequest = 0

    private(set) var sections: [EmojiCategory] = []
    /// Index of each section's first item in the flattened list.
    private(set) var sectionOffsets: [Int] = []
    private(set) var categoryNames: [String] = []
    private(set) var isLoaded = false

    private var flat: [EmojiItem] = []
    /// Global item indices, one array per visual row, for up/down movement across sections.
    private var rows: [[Int]] = []
    private var catalog: [EmojiCategory] = []
    private var byCharacter: [String: EmojiItem] = [:]
    private var isLoading = false

    func loadIfNeeded() {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { EmojiCatalog.load() }.value
            catalog = loaded
            categoryNames = loaded.map(\.name)
            byCharacter = Dictionary(loaded.flatMap(\.items).map { ($0.character, $0) }, uniquingKeysWith: { first, _ in first })
            isLoaded = true
            isLoading = false
            rebuild()
        }
    }

    /// Fresh state each time the picker opens.
    func prepare() {
        loadIfNeeded()
        isNavigating = false
        query = ""
        category = nil
        rebuild()
        selection = 0
        focusRequest += 1
    }

    func requestFocus() {
        focusRequest += 1
    }

    var selectedItem: EmojiItem? {
        flat.indices.contains(selection) ? flat[selection] : nil
    }

    var totalCount: Int { flat.count }

    func move(_ move: Move) {
        guard !flat.isEmpty else { return }
        switch move {
        case .left:
            selection = max(selection - 1, 0)
        case .right:
            selection = min(selection + 1, flat.count - 1)
        case .top:
            selection = 0
        case .bottom:
            selection = flat.count - 1
        case .up, .down:
            guard let row = rows.firstIndex(where: { $0.contains(selection) }),
                  let column = rows[row].firstIndex(of: selection) else { return }
            let target = row + (move == .down ? 1 : -1)
            guard rows.indices.contains(target) else { return }
            selection = rows[target][min(column, rows[target].count - 1)]
        }
    }

    func recordUse(_ item: EmojiItem) {
        EmojiRecents.record(item.character)
    }

    private func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = category.map { name in catalog.filter { $0.name == name } } ?? catalog

        var result: [EmojiCategory]
        if !needle.isEmpty {
            // Best matches first, nudging up ones you've used lately; ties keep catalog order.
            let recentRank = Dictionary(EmojiRecents.all().enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            var scored: [(item: EmojiItem, score: Int, order: Int)] = []
            for (order, item) in pool.flatMap(\.items).enumerated() {
                if var score = Self.score(item, needle) {
                    if let rank = recentRank[item.character] {
                        score += max(15 - rank / 2, 5)
                    }
                    scored.append((item, score, order))
                }
            }
            scored.sort { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.order < rhs.order
            }
            result = [EmojiCategory(name: "Results", items: scored.map(\.item))]
        } else if category != nil {
            result = pool
        } else {
            let recent = EmojiRecents.all().prefix(Self.recentCount).compactMap { byCharacter[$0] }
            result = (recent.isEmpty ? [] : [EmojiCategory(name: "Recently Used", items: recent)]) + catalog
        }

        sections = result.filter { !$0.items.isEmpty }
        flat = sections.flatMap(\.items)
        sectionOffsets = []
        rows = []
        var offset = 0
        for section in sections {
            sectionOffsets.append(offset)
            for start in stride(from: 0, to: section.items.count, by: Self.columns) {
                rows.append(Array((offset + start)..<(offset + min(start + Self.columns, section.items.count))))
            }
            offset += section.items.count
        }
    }

    /// Higher is better; nil means no match.
    static func score(_ item: EmojiItem, _ needle: String) -> Int? {
        if item.name == needle { return 100 }
        if item.name.hasPrefix(needle) { return 80 }
        if item.name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 60 }
        if item.keywords.contains(needle) { return 55 }
        if item.keywords.contains(where: { $0.hasPrefix(needle) }) { return 40 }
        if item.name.contains(needle) { return 30 }
        if item.keywords.contains(where: { $0.contains(needle) }) { return 20 }
        return nil
    }
}

// MARK: - Controller

/// Raycast-style Emoji & Symbols picker. Return pastes into the app you were in; ⌘Return copies.
@MainActor
public final class EmojiPickerController {
    public static let shared = EmojiPickerController()

    let model = EmojiPickerModel()
    private var host: FloatingPanelHost?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    /// Loads the emoji and builds the panel ahead of time so the first open is instant.
    public func warmUp() {
        model.loadIfNeeded()
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

    /// Pastes the emoji into the previous app, or just copies it.
    func insert(_ item: EmojiItem, paste: Bool) {
        model.recordUse(item)
        // Hand focus back to the app you were in, then paste there.
        host?.hide(restoringFocus: true)
        TextPaster.deliver(item.character, paste: paste)
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = EmojiPickerView(model: model, onInsert: { [weak self] item, paste in
            self?.insert(item, paste: paste)
        })
        let host = FloatingPanelHost(width: EmojiPickerView.width, rootView: root)
        host.topFraction = 0.18
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    /// Waiting for the second "g" of "gg".
    private var pendingG = false

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if model.isNavigating {
            return handleNormalModeKey(event, flags: flags)
        }
        switch event.keyCode {
        case 53: // escape: leave the search field for vim-style navigation
            setNavigating(true)
            return true
        case 123: model.move(.left); return true
        case 124: model.move(.right); return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        case 36, 76: // return, enter
            if let item = model.selectedItem {
                insert(item, paste: !flags.contains(.command))
            }
            return true
        default:
            return false
        }
    }

    /// Normal mode: h j k l move, gg / G jump, / or i search, Return or p paste, y copy, Esc closes.
    private func handleNormalModeKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let wasPendingG = pendingG
        pendingG = false

        switch event.keyCode {
        case 53: hide(); return true // escape
        case 123: model.move(.left); return true
        case 124: model.move(.right); return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        case 36, 76: // return, enter
            if let item = model.selectedItem {
                insert(item, paste: !flags.contains(.command))
            }
            return true
        default:
            break
        }

        // Let ⌘-shortcuts (⌘, for settings and the like) through.
        guard !flags.contains(.command) else { return false }

        switch event.characters ?? "" {
        case "h": model.move(.left)
        case "j": model.move(.down)
        case "k": model.move(.up)
        case "l": model.move(.right)
        case "G": model.move(.bottom)
        case "g":
            if wasPendingG {
                model.move(.top)
            } else {
                pendingG = true
            }
        case "/", "i":
            setNavigating(false)
        case "p":
            if let item = model.selectedItem { insert(item, paste: true) }
        case "y":
            if let item = model.selectedItem { insert(item, paste: false) }
        default:
            break
        }
        return true
    }

    private func setNavigating(_ navigating: Bool) {
        pendingG = false
        model.isNavigating = navigating
        if navigating {
            // Take keyboard focus away from the search field so letters become motions.
            host?.panel.makeFirstResponder(nil)
        } else {
            model.requestFocus()
        }
    }
}
