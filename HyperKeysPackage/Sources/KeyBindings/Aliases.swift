import Foundation

/// A short word for something App Search can run: type "gh" and Search GitHub is first.
/// For a quicklink, what you type after the alias fills its first `{argument}` ("gh swift").
public struct Alias: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var action: BoundAction

    public init(id: UUID = UUID(), text: String, action: BoundAction) {
        self.id = id
        self.text = Self.normalized(text)
        self.action = action
    }

    /// Lowercase, without spaces: a space after an alias starts the quicklink argument.
    public static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { !$0.isWhitespace })
    }
}

@MainActor
@Observable
public final class AliasStore {
    public static let shared = AliasStore()

    public private(set) var aliases: [Alias] = []
    /// Called after the user changes an alias, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init() {}

    public func alias(for action: BoundAction) -> Alias? {
        aliases.first { $0.action == action }
    }

    public func alias(matching text: String) -> Alias? {
        let text = Alias.normalized(text)
        return aliases.first { $0.text == text }
    }

    /// Adds or replaces an alias. An alias names one thing and a thing has one alias,
    /// so others with the same text or action are removed.
    public func save(_ alias: Alias) {
        guard !alias.text.isEmpty else { return }
        aliases.removeAll { $0.id != alias.id && ($0.text == alias.text || $0.action == alias.action) }
        if let index = aliases.firstIndex(where: { $0.id == alias.id }) {
            aliases[index] = alias
        } else {
            aliases.append(alias)
        }
        onChange?()
    }

    public func delete(id: UUID) {
        aliases.removeAll { $0.id == id }
        onChange?()
    }

    /// Follows a quicklink to its new name.
    public func renameQuicklink(from old: String, to new: String) {
        var changed = false
        for index in aliases.indices {
            if case .quicklink(let name) = aliases[index].action, name.caseInsensitiveCompare(old) == .orderedSame {
                aliases[index].action = .quicklink(name: new)
                changed = true
            }
        }
        if changed { onChange?() }
    }

    /// Replaces every alias (when `config.json` is loaded). Doesn't trigger `onChange`.
    public func replaceAll(_ newAliases: [Alias]) {
        aliases = newAliases
    }
}
