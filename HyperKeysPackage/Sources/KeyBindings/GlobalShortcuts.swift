import EventEngine
import Foundation

/// A regular shortcut (like ⌥Space or ⇧⌘V) that runs an action from anywhere,
/// alongside the Hyper shortcuts.
public struct GlobalShortcut: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var combo: KeyCombo
    public var action: BoundAction
    public var isEnabled: Bool

    public init(id: UUID = UUID(), combo: KeyCombo, action: BoundAction, isEnabled: Bool = true) {
        self.id = id
        self.combo = combo
        self.action = action
        self.isEnabled = isEnabled
    }
}

@MainActor
@Observable
public final class GlobalShortcutStore {
    public static let shared = GlobalShortcutStore()

    public private(set) var shortcuts: [GlobalShortcut] = []
    /// Called after the user changes a shortcut, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?
    /// Called after any change, including loading `config.json`, so shortcuts can be registered.
    @ObservationIgnored public var onUpdate: (() -> Void)?

    public init() {}

    /// The shortcut that runs `action`, if there is one.
    public func shortcut(for action: BoundAction) -> GlobalShortcut? {
        shortcuts.first { $0.action == action }
    }

    /// Gives `action` this shortcut (or none). A shortcut runs one thing, so whatever used it before loses it.
    public func set(_ combo: KeyCombo?, for action: BoundAction) {
        shortcuts.removeAll { $0.action == action || $0.combo == combo }
        if let combo {
            shortcuts.append(GlobalShortcut(combo: combo, action: action))
        }
        changed()
    }

    /// Adds or replaces a shortcut; another shortcut on the same keys is removed.
    public func save(_ shortcut: GlobalShortcut) {
        shortcuts.removeAll { $0.id != shortcut.id && $0.combo == shortcut.combo }
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
        } else {
            shortcuts.append(shortcut)
        }
        changed()
    }

    public func delete(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        changed()
    }

    /// Follows a quicklink to its new name.
    public func renameQuicklink(from old: String, to new: String) {
        var changed = false
        for index in shortcuts.indices {
            if case .quicklink(let name) = shortcuts[index].action, name.caseInsensitiveCompare(old) == .orderedSame {
                shortcuts[index].action = .quicklink(name: new)
                changed = true
            }
        }
        if changed { self.changed() }
    }

    /// Replaces every shortcut (when `config.json` is loaded). Doesn't trigger `onChange`.
    public func replaceAll(_ newShortcuts: [GlobalShortcut]) {
        shortcuts = newShortcuts
        onUpdate?()
    }

    private func changed() {
        onChange?()
        onUpdate?()
    }
}
