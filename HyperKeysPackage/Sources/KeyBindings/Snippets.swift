import AppKit
import Foundation

/// A piece of text you paste often. Stored in `config.json` (name, text, tags).
public struct Snippet: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var text: String
    public var tags: [String]

    public init(id: UUID = UUID(), name: String, text: String, tags: [String] = []) {
        self.id = id
        self.name = name
        self.text = text
        self.tags = tags
    }
}

/// How often and how recently a snippet was used — kept per Mac, outside `config.json`,
/// so the file only changes when you change your snippets.
public struct SnippetUsage: Codable, Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date
}

@MainActor
@Observable
public final class SnippetStore {
    public static let shared = SnippetStore()

    public private(set) var snippets: [Snippet] = []
    /// Keyed by snippet name.
    public private(set) var usage: [String: SnippetUsage] = [:]
    /// Called after the user adds, edits or deletes a snippet, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?

    private static let usageKey = "snippetUsage"

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.usageKey),
           let saved = try? JSONDecoder().decode([String: SnippetUsage].self, from: data) {
            usage = saved
        }
    }

    /// Every tag in use, alphabetically.
    public var allTags: [String] {
        Array(Set(snippets.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func snippet(id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    /// Adds a new snippet, or replaces the one with the same id.
    public func save(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            let oldName = snippets[index].name
            snippets[index] = snippet
            if oldName != snippet.name, let stats = usage.removeValue(forKey: oldName) {
                usage[snippet.name] = stats
                persistUsage()
            }
        } else {
            snippets.append(snippet)
        }
        onChange?()
    }

    /// Adds several snippets at once, saving once.
    public func add(_ newSnippets: [Snippet]) {
        snippets.append(contentsOf: newSnippets)
        onChange?()
    }

    public func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        onChange?()
    }

    /// Replaces every snippet (when `config.json` is loaded). Doesn't trigger `onChange`.
    public func replaceAll(_ newSnippets: [Snippet]) {
        snippets = newSnippets
    }

    public func recordUse(of snippet: Snippet) {
        let count = (usage[snippet.name]?.count ?? 0) + 1
        usage[snippet.name] = SnippetUsage(count: count, lastUsed: Date())
        persistUsage()
    }

    private func persistUsage() {
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: Self.usageKey)
        }
    }

    // MARK: - Placeholders

    /// The placeholders HyperKeys fills in. They're named like Raycast's, so imported snippets keep working.
    nonisolated(unsafe) private static let placeholderPattern = #/\{(clipboard|datetime|date|time|day|uuid|cursor)(?:\s+format="([^"]*)")?\}/#

    /// Fills in `{clipboard}`, `{date}`, `{time}`, `{datetime}`, `{day}` and `{uuid}` when a snippet is pasted.
    /// Dates take a format, e.g. `{date format="yyyy-MM-dd"}`. `{cursor}` is dropped.
    public nonisolated static func expand(_ text: String, clipboard: String?, now: Date = Date()) -> String {
        guard text.contains("{") else { return text }
        return text.replacing(placeholderPattern) { match in
            let name = match.output.1
            if let format = match.output.2, ["date", "time", "datetime", "day"].contains(name) {
                let formatter = DateFormatter()
                formatter.dateFormat = String(format)
                return formatter.string(from: now)
            }
            switch name {
            case "clipboard": return clipboard ?? ""
            case "date": return now.formatted(date: .abbreviated, time: .omitted)
            case "time": return now.formatted(date: .omitted, time: .shortened)
            case "datetime": return now.formatted(date: .abbreviated, time: .shortened)
            case "day": return now.formatted(.dateTime.weekday(.wide))
            case "uuid": return UUID().uuidString
            default: return "" // cursor
            }
        }
    }

    /// Placeholders in `text` that `expand` leaves as written, by name: `["{argument}"]`.
    public nonisolated static func unsupportedPlaceholders(in text: String) -> [String] {
        guard text.contains("{") else { return [] }
        var found: [String] = []
        for match in text.matches(of: #/\{([a-zA-Z][a-zA-Z-]*)([^{}]*)\}/#) {
            guard text[match.range].wholeMatch(of: placeholderPattern) == nil else { continue }
            let name = "{\(match.output.1)}"
            if !found.contains(name) { found.append(name) }
        }
        return found
    }
}
