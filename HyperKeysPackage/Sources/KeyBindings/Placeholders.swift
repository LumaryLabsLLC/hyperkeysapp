import Foundation

/// An `{argument}` a snippet or quicklink asks for before it's used.
public struct ArgumentField: Equatable, Sendable, Identifiable {
    /// Key for the value; unnamed arguments are numbered.
    public var name: String
    /// What the prompt shows.
    public var label: String
    public var defaultValue: String?
    /// When set, the prompt offers a choice instead of a text field.
    public var options: [String]

    public var id: String { name }
}

/// What placeholders are filled in from.
public struct PlaceholderContext {
    /// Clipboard texts, newest first: the current clipboard, then older copies (`offset=1`, `offset=2`…).
    public var clipboard: [String]
    public var selection: String?
    public var arguments: [String: String]
    public var now: Date
    /// Another snippet's text, by name.
    public var snippet: (String) -> String?
    /// Percent-encode inserted values (for web links), unless `| raw`.
    public var encodesValues: Bool

    public init(
        clipboard: [String] = [], selection: String? = nil, arguments: [String: String] = [:],
        now: Date = Date(), snippet: @escaping (String) -> String? = { _ in nil }, encodesValues: Bool = false
    ) {
        self.clipboard = clipboard
        self.selection = selection
        self.arguments = arguments
        self.now = now
        self.snippet = snippet
        self.encodesValues = encodesValues
    }
}

/// Raycast-style dynamic placeholders: `{clipboard}`, `{date offset="+2d" format="yyyy-MM-dd"}`,
/// `{argument name="query"}`, `{selection | uppercase}` and friends.
public enum Placeholders {
    public static let supportedNames: Set<String> = [
        "clipboard", "snippet", "cursor", "date", "time", "datetime", "day", "uuid", "selection", "argument",
    ]
    /// Raycast placeholders HyperKeys recognizes but can't fill (left as written).
    static let knownUnsupported: Set<String> = ["browser-tab", "calculator"]

    struct Token {
        let range: Range<String.Index>
        let name: String
        let attributes: [String: String]
        let modifiers: [String]
    }

    // MARK: Reading

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "{") {
            guard let close = text[open...].firstIndex(of: "}") else { break }
            let body = text[text.index(after: open)..<close]
            if let token = parse(body, range: open..<text.index(after: close)) {
                tokens.append(token)
            }
            index = text.index(after: open)
        }
        return tokens
    }

    private static func parse(_ body: Substring, range: Range<String.Index>) -> Token? {
        let segments = splitOutsideQuotes(body, on: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = segments.first else { return nil }
        let name = String(head.prefix { $0.isLetter || $0 == "-" })
        guard !name.isEmpty, supportedNames.contains(name) || knownUnsupported.contains(name) else { return nil }

        var attributes: [String: String] = [:]
        let rest = head.dropFirst(name.count)
        let pattern = #/([A-Za-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"']+))/#
        for match in rest.matches(of: pattern) {
            attributes[String(match.output.1)] = String(match.output.2 ?? match.output.3 ?? match.output.4 ?? "")
        }
        // Anything else in there means it isn't a placeholder ("{date is late}").
        let leftover = rest.replacing(pattern, with: "").trimmingCharacters(in: .whitespaces)
        guard leftover.isEmpty else { return nil }
        return Token(range: range, name: name, attributes: attributes, modifiers: segments.dropFirst().map { $0.lowercased() })
    }

    private static func splitOutsideQuotes(_ text: Substring, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    /// The arguments to ask for, in order. Arguments with the same name share a value;
    /// unnamed ones are separate.
    public static func arguments(in text: String) -> [ArgumentField] {
        var fields: [ArgumentField] = []
        var unnamed = 0
        for token in tokens(in: text) where token.name == "argument" {
            let name: String
            let label: String
            if let given = token.attributes["name"], !given.isEmpty {
                name = given
                label = given.prefix(1).uppercased() + given.dropFirst()
            } else {
                unnamed += 1
                name = "argument\(unnamed)"
                label = unnamed == 1 ? "Text" : "Text \(unnamed)"
            }
            guard !fields.contains(where: { $0.name == name }) else { continue }
            let options = token.attributes["options"]?
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
            fields.append(ArgumentField(name: name, label: label, defaultValue: token.attributes["default"], options: options))
        }
        return fields
    }

    public static func needsSelection(_ text: String) -> Bool {
        tokens(in: text).contains { $0.name == "selection" }
    }

    /// Placeholders that will be left as written, by name, like `["{browser-tab}"]`.
    public static func unsupported(in text: String) -> [String] {
        var names: [String] = []
        for token in tokens(in: text) where knownUnsupported.contains(token.name) {
            let label = "{\(token.name)}"
            if !names.contains(label) { names.append(label) }
        }
        return names
    }

    // MARK: Filling in

    public static func expand(_ text: String, context: PlaceholderContext) -> String {
        expand(text, context: context, depth: 0)
    }

    private static func expand(_ text: String, context: PlaceholderContext, depth: Int) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var cursor = text.startIndex
        var unnamed = 0
        for token in tokens(in: text) {
            guard token.range.lowerBound >= cursor else { continue }
            result += text[cursor..<token.range.lowerBound]
            cursor = token.range.upperBound

            if token.name == "argument", token.attributes["name"]?.isEmpty ?? true {
                unnamed += 1
            }
            guard var value = rawValue(for: token, unnamedIndex: unnamed, context: context, depth: depth) else {
                result += text[token.range]
                continue
            }
            for modifier in token.modifiers {
                value = apply(modifier, to: value)
            }
            if context.encodesValues, token.name != "cursor",
               !token.modifiers.contains("raw"), !token.modifiers.contains("percent-encode") {
                value = percentEncode(value)
            }
            result += value
        }
        result += text[cursor...]
        return result
    }

    private static func rawValue(for token: Token, unnamedIndex: Int, context: PlaceholderContext, depth: Int) -> String? {
        let attributes = token.attributes
        switch token.name {
        case "clipboard":
            let offset = Int(attributes["offset"] ?? "0") ?? 0
            return context.clipboard.indices.contains(offset) ? context.clipboard[offset] : ""
        case "selection":
            return context.selection ?? ""
        case "cursor":
            return ""
        case "uuid":
            return UUID().uuidString
        case "argument":
            let name = attributes["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "argument\(unnamedIndex)"
            return context.arguments[name] ?? attributes["default"] ?? ""
        case "snippet":
            guard depth < 3, let name = attributes["name"], let text = context.snippet(name) else { return "" }
            return expand(text, context: context, depth: depth + 1)
        case "date", "time", "datetime", "day":
            return formatDate(token.name, attributes: attributes, now: context.now)
        default:
            return nil // known but unsupported: leave as written
        }
    }

    // MARK: Dates

    private static func formatDate(_ name: String, attributes: [String: String], now: Date) -> String {
        let date = attributes["offset"].map { shift(now, by: $0) } ?? now
        let locale = attributes["locale"].map(Locale.init(identifier:)) ?? .current
        if let format = attributes["format"] {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        switch name {
        case "time": return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        case "datetime": return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
        case "day": return date.formatted(Date.FormatStyle(locale: locale).weekday(.wide))
        default: return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
        }
    }

    /// "+2y +5M -3d 4h 30m": years, months, weeks, days, hours, minutes.
    static func shift(_ date: Date, by offset: String) -> Date {
        var result = date
        let calendar = Calendar.current
        for part in offset.split(separator: " ") {
            guard let match = part.wholeMatch(of: #/([+-]?)(\d+)([mhdwMy])/#), var amount = Int(match.output.2) else { continue }
            if match.output.1 == "-" { amount = -amount }
            let component: Calendar.Component = switch match.output.3 {
            case "m": .minute
            case "h": .hour
            case "w": .weekOfYear
            case "M": .month
            case "y": .year
            default: .day
            }
            result = calendar.date(byAdding: component, value: amount, to: result) ?? result
        }
        return result
    }

    // MARK: Modifiers

    private static func apply(_ modifier: String, to value: String) -> String {
        switch modifier {
        case "uppercase": return value.uppercased()
        case "lowercase": return value.lowercased()
        case "trim": return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "percent-encode": return percentEncode(value)
        case "json-stringify":
            guard let data = try? JSONEncoder().encode(value) else { return value }
            return String(decoding: data, as: UTF8.self)
        default: return value // "raw" and unknown modifiers change nothing here
        }
    }

    static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
