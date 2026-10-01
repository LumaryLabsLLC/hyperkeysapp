import CoreText
import Foundation

struct EmojiItem: Identifiable, Hashable, Sendable {
    let character: String
    /// Lowercased name, e.g. "check mark button".
    let name: String
    /// Lowercased search keywords.
    let keywords: [String]
    let isEmoji: Bool

    var id: String { character }

    var displayName: String { name.capitalized }
}

struct EmojiCategory: Identifiable, Sendable {
    let name: String
    let items: [EmojiItem]

    var id: String { name }
}

/// Bundled emoji (from Unicode's emoji-test.txt + CLDR keywords, see Scripts/generate-emoji-data.py)
/// plus text symbols generated from Unicode character names.
enum EmojiCatalog {
    /// Loads everything. Slow-ish (font checks), so call it off the main thread.
    static func load() -> [EmojiCategory] {
        emoji() + symbols()
    }

    // MARK: - Emoji

    static var dataURL: URL? {
        Bundle.module.url(forResource: "emoji", withExtension: "json")
    }

    private static func emoji() -> [EmojiCategory] {
        guard let url = dataURL,
              let data = try? Data(contentsOf: url),
              let groups = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 32, nil)
        return groups.compactMap { group in
            guard let name = group["name"] as? String, let rows = group["emoji"] as? [[Any]] else { return nil }
            let items = rows.compactMap { row -> EmojiItem? in
                guard row.count >= 2, let character = row[0] as? String, let title = row[1] as? String,
                      isDrawable(character, with: font) else { return nil }
                let keywords = (row.count > 2 ? row[2] as? [String] : nil) ?? []
                return EmojiItem(character: character, name: title.lowercased(), keywords: keywords.map { $0.lowercased() }, isEmoji: true)
            }
            return EmojiCategory(name: name, items: items)
        }
    }

    /// True when this Mac's emoji font draws the sequence as a single glyph, so emoji newer
    /// than the installed macOS don't show up as blank boxes or split-apart sequences.
    private static func isDrawable(_ emoji: String, with font: CTFont) -> Bool {
        let attributed = NSAttributedString(string: emoji, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        guard CTLineGetGlyphCount(line) == 1,
              let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first else { return false }
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let runFont = attributes[kCTFontAttributeName as String] else { return false }
        // swiftlint:disable:next force_cast
        return (CTFontCopyPostScriptName(runFont as! CTFont) as String).hasPrefix("AppleColorEmoji")
    }

    // MARK: - Symbols

    private static func symbols() -> [EmojiCategory] {
        [
            EmojiCategory(name: "Arrows", items: scalars(Array(0x2190...0x21FF) + Array(0x27F0...0x27FF) + Array(0x2B00...0x2B0D))),
            EmojiCategory(name: "Math", items: scalars([0xB1, 0xD7, 0xF7, 0xAC, 0xB0, 0xB5, 0xB9, 0xB2, 0xB3, 0xBC, 0xBD, 0xBE] + Array(0x2200...0x22FF))),
            EmojiCategory(name: "Currency", items: scalars([0x24, 0xA2, 0xA3, 0xA4, 0xA5] + Array(0x20A0...0x20C1))),
            EmojiCategory(name: "Keyboard", items: keyboardSymbols),
            EmojiCategory(name: "Punctuation", items: scalars([
                0x2022, 0x2026, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0xAB, 0xBB, 0x2039, 0x203A,
                0x2020, 0x2021, 0xA7, 0xB6, 0xA9, 0xAE, 0x2122, 0x2032, 0x2033, 0x2030, 0x203B, 0xA1, 0xBF,
                0xB7, 0x203D, 0x2116, 0xA6, 0x2016, 0x2042, 0x2051, 0x204E, 0x2044, 0xA8, 0xB4, 0x2DC, 0x2C6,
            ])),
            EmojiCategory(name: "Shapes", items: scalars(
                Array(0x25A0...0x25FF) + [0x2605, 0x2606] + Array(0x2660...0x2667) + Array(0x266A...0x266F)
                    + [0x2713, 0x2717, 0x2718] + Array(0x2726...0x273F)
            )),
            EmojiCategory(name: "Letterlike", items: scalars(Array(0x2100...0x214F))),
        ]
    }

    /// Mac keyboard symbols, with the names people actually search for.
    private static let keyboardSymbols: [EmojiItem] = [
        ("⌘", "command", ["cmd"]), ("⌥", "option", ["alt", "opt"]), ("⇧", "shift", []), ("⌃", "control", ["ctrl"]),
        ("⇪", "caps lock", []), ("⇥", "tab", []), ("⇤", "back tab", []), ("↩", "return", ["enter"]),
        ("⌤", "enter", []), ("⌫", "delete", ["backspace"]), ("⌦", "forward delete", []), ("⎋", "escape", ["esc"]),
        ("⏏", "eject", []), ("␣", "space", []), ("⇞", "page up", []), ("⇟", "page down", []),
        ("↖", "home", []), ("↘", "end", []), ("←", "left arrow", []), ("→", "right arrow", []),
        ("↑", "up arrow", []), ("↓", "down arrow", []), ("⌧", "clear", []), ("⌽", "power", []),
    ].map { EmojiItem(character: $0.0, name: $0.1, keywords: $0.2 + ["key", "keyboard"], isEmoji: false) }

    private static func scalars(_ values: [Int]) -> [EmojiItem] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let scalar = Unicode.Scalar(UInt32(value)),
                  scalar.properties.generalCategory != .unassigned,
                  // Emoji-style ones are already in the emoji sections.
                  !scalar.properties.isEmojiPresentation,
                  let name = scalar.properties.name else { return nil }
            let character = String(scalar)
            guard seen.insert(character).inserted else { return nil }
            return EmojiItem(character: character, name: name.lowercased(), keywords: [], isEmoji: false)
        }
    }
}

/// The emoji and symbols you picked, most recent first.
enum EmojiRecents {
    private static let key = "emojiRecents"
    private static let limit = 36

    static func record(_ character: String) {
        var recents = all().filter { $0 != character }
        recents.insert(character, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(limit)), forKey: key)
    }

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
