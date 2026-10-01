import CoreGraphics
import EventEngine
import Foundation
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings

@MainActor
struct KeywordExpansionTests {
    private func type(_ text: String, into buffer: String = "") -> String {
        text.reduce(buffer) { KeywordExpander.advance($0, with: TypedKey(keyCode: 0, characters: String($1))) }
    }

    @Test func remembersWhatYouTypeUntilYouMoveOn() {
        var buffer = type("hello ;ad")
        #expect(buffer == "hello ;ad")
        buffer = KeywordExpander.advance(buffer, with: TypedKey(keyCode: 51, characters: "\u{7F}")) // delete
        #expect(buffer == "hello ;a")
        buffer = KeywordExpander.advance(buffer, with: TypedKey(keyCode: 123, characters: "")) // left arrow
        #expect(buffer.isEmpty)
        buffer = KeywordExpander.advance(type("abc"), with: TypedKey(keyCode: 9, flags: .maskCommand, characters: "v")) // ⌘V
        #expect(buffer.isEmpty)
        #expect(type(String(repeating: "x", count: 100)).count == 64)
    }

    @Test func theLongestMatchingKeywordWins() {
        let snippets = [
            Snippet(name: "Address", text: "1 Infinite Loop", keyword: ";addr"),
            Snippet(name: "Work address", text: "1 Apple Park Way", keyword: ";waddr"),
            Snippet(name: "No keyword", text: "x"),
        ]
        #expect(KeywordExpander.match("my ;addr", in: snippets)?.0.name == "Address")
        #expect(KeywordExpander.match("my ;waddr", in: snippets)?.0.name == "Work address")
        #expect(KeywordExpander.match("my ;add", in: snippets) == nil)
    }

    @Test func keywordsRoundTripThroughConfig() throws {
        let settings = ConfigSettings(snippets: [Snippet(name: "Address", text: "1 Infinite Loop", keyword: ";addr")])
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        #expect(String(decoding: data, as: UTF8.self).contains(#""keyword" : ";addr""#))
        let (loaded, _) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(loaded.snippets.first?.keyword == ";addr")
    }

    @Test func raycastKeywordsComeAlong() throws {
        let export = RaycastExport(snippets: [.init(name: "Email", text: "me@example.com", keyword: "!em")])
        let plan = RaycastImportPlan(export: export, hyperKey: .capsLock, existingBindings: [], existingSnippets: [], resolveApp: { _ in nil })
        #expect(plan.snippets.first?.snippet.keyword == "!em")
    }
}
