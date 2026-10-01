import EventEngine
import Foundation
@testable import Shared
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings

struct PlaceholderTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000) // Sep 2026

    @Test func fillsClipboardSelectionAndArguments() {
        let context = PlaceholderContext(
            clipboard: ["newest", "older"], selection: "picked",
            arguments: ["who": "Sam", "argument1": "first"], now: now
        )
        let text = "{argument name=\"who\"} {argument} {clipboard} {clipboard offset=1} {selection} {clipboard offset=9}."
        #expect(Placeholders.expand(text, context: context) == "Sam first newest older picked .")
    }

    @Test func listsArgumentsToAskFor() {
        let fields = Placeholders.arguments(in: "{argument name=\"tone\" options=\"happy, sad\"} {argument} {argument name=\"tone\"} {argument default=\"x\"}")
        #expect(fields.map(\.name) == ["tone", "argument1", "argument2"])
        #expect(fields[0].options == ["happy", "sad"])
        #expect(fields[2].defaultValue == "x")
        #expect(fields.map(\.label) == ["Tone", "Text", "Text 2"])
    }

    @Test func formatsAndShiftsDates() {
        let context = PlaceholderContext(now: now)
        #expect(Placeholders.expand("{date format=\"yyyy-MM-dd\"}", context: context).hasPrefix("2026-09-"))
        let shifted = Placeholders.shift(now, by: "+1y -1M +2d")
        #expect(Calendar.current.component(.year, from: shifted) == 2027)
        #expect(Placeholders.expand("{day locale=\"fr-FR\"}", context: context).first?.isLowercase == true)
    }

    @Test func appliesModifiersAndEncodesLinks() {
        let context = PlaceholderContext(clipboard: ["  Hello World  "], arguments: ["argument1": "a b&c"], encodesValues: true)
        #expect(Placeholders.expand("q={argument}", context: context) == "q=a%20b%26c")
        #expect(Placeholders.expand("{clipboard | trim | uppercase | raw}", context: context) == "HELLO WORLD")
        #expect(Placeholders.expand("{clipboard | trim | json-stringify | raw}", context: context) == "\"Hello World\"")
    }

    @Test func expandsOtherSnippetsAndLeavesOtherBracesAlone() {
        let context = PlaceholderContext(snippet: { $0 == "sig" ? "— {argument default=\"Adib\"}" : nil })
        #expect(Placeholders.expand("Thanks {snippet name=\"sig\"}", context: context) == "Thanks — Adib")
        #expect(Placeholders.expand("{\"json\": 1} {date is late} {cursor}", context: context) == "{\"json\": 1} {date is late} ")
        #expect(Placeholders.unsupported(in: "{browser-tab format=\"markdown\"} {date}") == ["{browser-tab}"])
    }
}

@MainActor
struct QuicklinkTests {
    @Test func knowsLocalLinksFromWebLinks() {
        let folder = Quicklink(name: "Projects", link: "~/Projects")
        #expect(folder.isLocal)
        #expect(folder.localPath == NSHomeDirectory() + "/Projects")

        let search = Quicklink(name: "GitHub", link: "https://github.com/search?q={argument}")
        #expect(!search.isLocal)
        #expect(search.displayLink == "github.com")
    }

    @Test func buildsUrlsToOpen() {
        #expect(QuicklinkRunner.url(for: "github.com/apple", isLocal: false)?.absoluteString == "https://github.com/apple")
        #expect(QuicklinkRunner.url(for: "slack://open", isLocal: false)?.scheme == "slack")
        #expect(QuicklinkRunner.url(for: "~/Downloads", isLocal: true)?.path == NSHomeDirectory() + "/Downloads")
    }

    @Test func quicklinksAndTheirShortcutsRoundTripThroughConfig() throws {
        let settings = ConfigSettings(
            bindings: [KeyBinding(keyCode: .g, action: .quicklink(name: "GitHub"))],
            quicklinks: [Quicklink(name: "GitHub", link: "https://github.com/search?q={argument}", openWith: "com.google.Chrome")]
        )
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""quicklink" : "GitHub""#))
        #expect(text.contains(#""openWith" : "com.google.Chrome""#))

        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.quicklinks.map(\.link) == ["https://github.com/search?q={argument}"])
        #expect(loaded.bindings.first?.action == .quicklink(name: "GitHub"))
    }

    @Test func raycastWebQuicklinksComeOverAsQuicklinks() throws {
        let export = RaycastExport(hotkeys: [
            .init(target: .quicklink(name: "Jira", link: "https://jira.example.com/browse/{argument}"), keyCode: 38, modifiers: .hyper),
        ])
        let plan = RaycastImportPlan(export: export, hyperKey: .capsLock, existingBindings: [], existingSnippets: [], resolveApp: { _ in nil })
        #expect(plan.shortcuts.first?.action == .quicklink(name: "Jira"))
        #expect(plan.quicklinkLinks["Jira"] == "https://jira.example.com/browse/{argument}")
    }
}

@MainActor
struct FaviconTests {
    @Test func prefersTheBiggestDeclaredIcon() {
        let html = """
        <html><head>
          <link rel="icon" href="/favicon-32.png" sizes="32x32">
          <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png">
          <LINK REL="icon" HREF="logo.svg">
          <link rel="mask-icon" href="/mask.svg">
          <link rel="stylesheet" href="/app.css">
        </head></html>
        """
        let urls = FaviconCache.declaredIcons(in: html, base: URL(string: "https://example.com/")!)
        #expect(urls.map(\.absoluteString) == [
            "https://cdn.example.com/touch.png", "https://example.com/favicon-32.png", "https://example.com/logo.svg",
        ])
    }

    @Test func findsTheSiteOfALink() {
        #expect(Quicklink(name: "a", link: "https://github.com/search?q={argument}").host == "github.com")
        #expect(Quicklink(name: "b", link: "news.ycombinator.com").host == "news.ycombinator.com")
        #expect(Quicklink(name: "c", link: "slack://open").host == nil)
        #expect(Quicklink(name: "d", link: "~/Projects").host == nil)
    }
}
