import Foundation
import Testing
@testable import KeyBindings
import EventEngine

@MainActor
struct SettingsResetTests {
    @Test func defaultsAreWhatAFreshInstallHas() throws {
        let snippet = Snippet(name: "Sign-off", text: "Thanks")
        let settings = ConfigStore.defaultSettings(snippets: [snippet])
        #expect(settings.hyperKey == .capsLock)
        #expect(settings.bindings.map(\.keyCode) == [.space, .tab])
        #expect(settings.bindings.map(\.action) == [.appSearch, .appSwitcher])
        #expect(settings.profiles.isEmpty && settings.hotkeys.isEmpty && settings.aliases.isEmpty)
        #expect(settings.snippets.map(\.name) == ["Sign-off"])
        #expect(settings.windowGap == .none)
        #expect(!settings.switcherStaysOpen)
        #expect(settings.doubleTapOpensWindow)

        // And it writes a config file that loads cleanly.
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.map(\.action) == [.appSearch, .appSwitcher])
    }

    @Test func theOldConfigIsCopiedAsideFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hyperkeys-reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config/hyperkeys/config.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{ "hyperKey": "tab" }"#.utf8).write(to: config)

        let store = ConfigStore(fileURL: config)
        let backups = root.appendingPathComponent("Backups")
        let copy = try #require(store.copyConfig(to: backups, prefix: "config.before-reset"))
        #expect(copy.lastPathComponent.hasPrefix("config.before-reset-"))
        #expect(try Data(contentsOf: copy) == Data(contentsOf: config))

        // Nothing to copy when there's no file yet.
        let empty = ConfigStore(fileURL: root.appendingPathComponent("none/config.json"))
        #expect(empty.copyConfig(to: backups, prefix: "x") == nil)
    }
}
