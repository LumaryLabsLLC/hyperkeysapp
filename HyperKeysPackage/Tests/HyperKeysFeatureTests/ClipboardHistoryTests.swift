import AppKit
import Foundation
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings
import EventEngine

/// A private pasteboard, so tests never touch the real clipboard.
@MainActor
private func scratchPasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    return pasteboard
}

/// A store in its own folder and defaults suite, cleaned up by the caller.
@MainActor
private struct Sandbox {
    let folder: URL
    let defaults: UserDefaults
    let suite: String

    init() {
        suite = "hyperkeys-clipboard-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    func store() -> ClipboardHistoryStore {
        ClipboardHistoryStore(folder: folder, defaults: defaults)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }
}

private func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
struct ClipboardReaderTests {
    @Test func recognizesLinks() {
        #expect(ClipboardReader.isLink("https://example.com/a?b=c"))
        #expect(ClipboardReader.isLink("  http://localhost:8080 \n"))
        #expect(ClipboardReader.isLink("mailto:someone@example.com"))
        #expect(!ClipboardReader.isLink("see https://example.com"))
        #expect(!ClipboardReader.isLink("example.com"))
        #expect(!ClipboardReader.isLink("file:///etc/hosts"))
    }

    @Test func readsTextLinksFilesAndImages() throws {
        let pasteboard = scratchPasteboard()

        pasteboard.setString("Hello\nworld", forType: .string)
        #expect(ClipboardReader.capture(from: pasteboard)?.kind == .text)

        pasteboard.clearContents()
        pasteboard.setString("https://lumarylabs.com", forType: .string)
        #expect(ClipboardReader.capture(from: pasteboard)?.kind == .link)

        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/Applications/Safari.app") as NSURL])
        let file = try #require(ClipboardReader.capture(from: pasteboard))
        #expect(file.kind == .file)
        #expect(file.text == "/Applications/Safari.app")

        pasteboard.clearContents()
        pasteboard.setData(pngData(width: 12, height: 7), forType: .png)
        let image = try #require(ClipboardReader.capture(from: pasteboard))
        #expect(image.kind == .image)
        #expect(image.imageWidth == 12 && image.imageHeight == 7)
    }

    @Test func leavesOutPasswordsBlanksAndItsOwnPastes() {
        let pasteboard = scratchPasteboard()

        let secret = NSPasteboardItem()
        secret.setString("hunter2", forType: .string)
        secret.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([secret])
        #expect(ClipboardReader.capture(from: pasteboard) == nil)

        pasteboard.clearContents()
        let own = NSPasteboardItem()
        own.setString("snippet text", forType: .string)
        own.setString("", forType: ClipboardReader.ownWriteType)
        pasteboard.writeObjects([own])
        #expect(ClipboardReader.capture(from: pasteboard) == nil)

        pasteboard.clearContents()
        pasteboard.setString("  \n ", forType: .string)
        #expect(ClipboardReader.capture(from: pasteboard) == nil)
    }

    @Test func writesItemsBackMarkedAsItsOwn() throws {
        let pasteboard = scratchPasteboard()
        let item = ClipboardItem(kind: .link, text: "https://example.com", fingerprint: "x")
        ClipboardWriter.write(item, imageURL: nil, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://example.com")
        // The monitor sees its own write and leaves it alone.
        #expect(ClipboardReader.capture(from: pasteboard) == nil)
    }
}

@MainActor
struct ClipboardHistoryStoreTests {
    private func capture(_ text: String) -> ClipboardCapture {
        ClipboardCapture(kind: .text, text: text, fingerprint: ClipboardReader.fingerprint(.text, Data(text.utf8)))
    }

    @Test func copyingAgainMovesToTheTop() {
        let box = Sandbox()
        defer { box.remove() }
        let store = box.store()
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        store.record(capture("one"), sourceBundleId: "com.apple.Safari", sourceName: "Safari", now: start)
        store.record(capture("two"), sourceBundleId: nil, sourceName: nil, now: start.addingTimeInterval(10))
        store.record(capture("one"), sourceBundleId: "com.apple.Notes", sourceName: "Notes", now: start.addingTimeInterval(20))

        #expect(store.items.map(\.text) == ["one", "two"])
        #expect(store.items.first?.sourceName == "Notes")
    }

    @Test func keepsHistoryAcrossLaunches() {
        let box = Sandbox()
        defer { box.remove() }
        let first = box.store()
        first.record(capture("kept"), sourceBundleId: nil, sourceName: nil)
        first.togglePin(id: first.items[0].id)

        let reopened = box.store()
        #expect(reopened.items.map(\.text) == ["kept"])
        #expect(reopened.items.first?.isPinned == true)
    }

    @Test func oldItemsExpireButPinnedOnesStay() {
        let box = Sandbox()
        defer { box.remove() }
        let store = box.store()
        store.retention = .week
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let old = now.addingTimeInterval(-8 * 86_400)

        store.record(capture("old"), sourceBundleId: nil, sourceName: nil, now: old)
        store.record(capture("old pinned"), sourceBundleId: nil, sourceName: nil, now: old)
        store.togglePin(id: store.items[0].id)
        store.record(capture("new"), sourceBundleId: nil, sourceName: nil, now: now)

        #expect(Set(store.items.map(\.text)) == ["new", "old pinned"])

        store.clear()
        #expect(store.items.map(\.text) == ["old pinned"])
    }

    @Test func savesImagesAndRemovesThemWithTheItem() throws {
        let box = Sandbox()
        defer { box.remove() }
        let store = box.store()
        let data = pngData(width: 4, height: 4)
        store.record(ClipboardCapture(kind: .image, text: "", imageData: data, imageWidth: 4, imageHeight: 4,
                                      fingerprint: ClipboardReader.fingerprint(.image, data)),
                     sourceBundleId: nil, sourceName: nil)

        let item = try #require(store.items.first)
        let url = try #require(store.imageURL(for: item))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(item.title == "Image (4 × 4)")

        store.delete(id: item.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func monitorSkipsIgnoredAppsAndWhenOff() {
        let box = Sandbox()
        defer { box.remove() }
        let store = box.store()
        let pasteboard = scratchPasteboard()
        let monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)
        monitor.check(sourceBundleId: "com.apple.Notes", sourceName: "Notes")
        #expect(store.items.map(\.text) == ["first"])
        #expect(store.items.first?.sourceName == "Notes")

        // Nothing new on the clipboard, nothing new in history.
        monitor.check(sourceBundleId: "com.apple.Notes", sourceName: "Notes")
        #expect(store.items.count == 1)

        store.isEnabled = false
        pasteboard.clearContents()
        pasteboard.setString("while off", forType: .string)
        monitor.check(sourceBundleId: nil, sourceName: nil)
        #expect(store.items.map(\.text) == ["first"])

        store.isEnabled = true
        pasteboard.clearContents()
        pasteboard.setString("a password", forType: .string)
        monitor.check(sourceBundleId: "com.1password.1password", sourceName: "1Password")
        #expect(store.items.map(\.text) == ["first"])
    }

    @Test func titlesDescribeEachKind() {
        #expect(ClipboardItem(kind: .text, text: "\n  Hello there  \nsecond line", fingerprint: "a").title == "Hello there")
        #expect(ClipboardItem(kind: .file, text: "/a/one.txt\n/b/two.txt", fingerprint: "b").title == "one.txt and 1 more")
    }
}

@MainActor
struct ClipboardPanelTests {
    @Test func groupsPinnedThenByDay() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let items = [
            ClipboardItem(kind: .text, text: "today", copiedAt: now.addingTimeInterval(-60), fingerprint: "1"),
            ClipboardItem(kind: .text, text: "yesterday", copiedAt: now.addingTimeInterval(-86_400), fingerprint: "2"),
            ClipboardItem(kind: .text, text: "earlier", copiedAt: now.addingTimeInterval(-20 * 86_400), fingerprint: "3"),
            ClipboardItem(kind: .text, text: "pinned", copiedAt: now.addingTimeInterval(-30 * 86_400), isPinned: true, fingerprint: "4"),
        ]
        let sections = ClipboardHistoryPanelModel.sections(items, now: now).filter { !$0.items.isEmpty }
        #expect(sections.map(\.title) == ["Pinned", "Today", "Yesterday", "Earlier"])
        #expect(sections.flatMap(\.items).map(\.text) == ["pinned", "today", "yesterday", "earlier"])
    }

    @Test func searchMatchesTextSourceAndKind() {
        let link = ClipboardItem(kind: .link, text: "https://github.com", sourceName: "Safari", fingerprint: "1")
        #expect(ClipboardHistoryPanelModel.matches(link, "github"))
        #expect(ClipboardHistoryPanelModel.matches(link, "safari"))
        #expect(ClipboardHistoryPanelModel.matches(link, "link"))
        #expect(!ClipboardHistoryPanelModel.matches(link, "notes"))
    }

    @Test func clipboardHistoryShortcutsRoundTripThroughConfig() throws {
        let settings = ConfigSettings(bindings: [KeyBinding(keyCode: .v, action: .clipboardHistory)], snippets: [])
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        #expect(String(decoding: data, as: UTF8.self).contains(#""command" : "clipboardHistory""#))
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.first?.action == .clipboardHistory)
    }
}

struct KeyComboTests {
    @Test func savesAndReadsShortcuts() throws {
        let combo = try #require(KeyCombo(string: "shift+cmd+v"))
        #expect(combo.key == .v)
        #expect(combo.modifiers == [.shift, .command])
        #expect(combo.displayLabel == "⇧⌘V")
        #expect(combo.string == "shift+cmd+v")
        #expect(KeyCombo(string: combo.string) == combo)
        #expect(KeyCombo(string: "Command+Option+Space")?.displayLabel == "⌥⌘Space")
    }

    @Test func needsAModifierExceptForFunctionKeys() {
        #expect(KeyCombo(string: "v") == nil)
        #expect(KeyCombo(string: "hyper+v") == nil)
        #expect(KeyCombo(string: "f5")?.key == .f5)
    }
}
