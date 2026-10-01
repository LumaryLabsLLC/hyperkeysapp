import AppKit
import Carbon.HIToolbox
import EventEngine
import KeyBindings
import Shared

/// Turns snippet keywords into their snippets as you type: type ";addr" anywhere and it's
/// replaced by your address. Never in password fields (macOS's secure input), and never
/// while you're typing in HyperKeys itself.
@MainActor
public final class KeywordExpander {
    public static let shared = KeywordExpander()

    /// The last characters typed, enough to hold any keyword.
    private(set) var buffer = ""
    private static let maxBuffer = 64

    /// Keys that move the caret or end a word without typing: the keyword can't continue past them.
    private static let resetKeys: Set<UInt16> = [36, 76, 48, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126]

    public func handle(_ key: TypedKey) {
        guard Preferences.isSnippetKeywordExpansionEnabled else { return }
        buffer = Self.advance(buffer, with: key)
        guard let (snippet, keyword) = Self.match(buffer, in: SnippetStore.shared.snippets),
              !IsSecureEventInputEnabled(), !NSApplication.shared.isActive
        else { return }
        buffer = ""
        expand(snippet, replacing: keyword)
    }

    /// What's been typed after `key`: characters add on, delete takes one off, and shortcuts,
    /// Return, Tab, Escape and arrows start over.
    static func advance(_ buffer: String, with key: TypedKey) -> String {
        if key.flags.contains(.maskCommand) || key.flags.contains(.maskControl) || resetKeys.contains(key.keyCode) {
            return ""
        }
        if key.keyCode == 51 { // delete
            return String(buffer.dropLast())
        }
        guard !key.characters.isEmpty,
              !key.characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return buffer }
        return String((buffer + key.characters).suffix(maxBuffer))
    }

    /// Forgets what was typed (another app came to the front, say).
    public func reset() {
        buffer = ""
    }

    private var activationObserver: NSObjectProtocol?

    private init() {
        // A keyword can't start in one app and finish in another.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { KeywordExpander.shared.reset() }
        }
    }

    /// The snippet whose keyword the typed text ends with; the longest keyword wins.
    static func match(_ typed: String, in snippets: [Snippet]) -> (Snippet, String)? {
        snippets
            .compactMap { snippet in snippet.keyword.map { (snippet, $0) } }
            .filter { !$0.1.isEmpty && typed.hasSuffix($0.1) }
            .max { $0.1.count < $1.1.count }
    }

    private func expand(_ snippet: Snippet, replacing keyword: String) {
        let app = NSWorkspace.shared.frontmostApplication
        // Let the keyword's last key reach the app, then delete the keyword and paste.
        DispatchQueue.main.async {
            for _ in 0..<keyword.count {
                SyntheticEvent.press(keyCode: 51) // delete
            }
            Task {
                try? await Task.sleep(for: .milliseconds(40))
                guard let text = await PlaceholderFiller.fill(snippet.text, title: snippet.name, app: app) else { return }
                SnippetStore.shared.recordUse(of: snippet)
                TextPaster.deliver(text, paste: true)
            }
        }
    }
}
