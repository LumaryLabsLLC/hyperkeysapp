import EventEngine
import Foundation
import Testing
@testable import KeyBindings
import AppSwitcher
import WindowEngine

@MainActor
struct GlobalShortcutTests {
    private let optSpace = KeyCombo(key: .space, modifiers: [.option])
    private let shiftCmdV = KeyCombo(key: .v, modifiers: [.shift, .command])

    @Test func anActionHasOneShortcutAndAShortcutRunsOneAction() {
        let store = GlobalShortcutStore()
        var updates = 0
        store.onUpdate = { updates += 1 }

        store.set(optSpace, for: .appSearch)
        store.set(shiftCmdV, for: .appSearch)
        #expect(store.shortcuts.map(\.combo) == [shiftCmdV])

        // Giving ⇧⌘V to Clipboard History takes it from App Search.
        store.set(shiftCmdV, for: .clipboardHistory)
        #expect(store.shortcut(for: .appSearch) == nil)
        #expect(store.shortcut(for: .clipboardHistory)?.combo == shiftCmdV)

        store.set(nil, for: .clipboardHistory)
        #expect(store.shortcuts.isEmpty)
        #expect(updates == 4)
    }

    @Test func savingEditsInPlaceAndTakesOverTheKeys() {
        let store = GlobalShortcutStore()
        var changes = 0
        store.onChange = { changes += 1 }
        let search = GlobalShortcut(combo: optSpace, action: .appSearch)
        let left = GlobalShortcut(combo: shiftCmdV, action: .windowAction(.leftHalf))
        store.save(search)
        store.save(left)

        var edited = search
        edited.action = .emojiPicker
        store.save(edited)
        #expect(store.shortcuts.map(\.id) == [search.id, left.id])
        #expect(store.shortcuts.first?.action == .emojiPicker)

        edited.combo = shiftCmdV
        store.save(edited)
        #expect(store.shortcuts.map(\.id) == [search.id])

        store.delete(id: search.id)
        #expect(store.shortcuts.isEmpty)
        #expect(changes == 5)
    }

    @Test func loadingTheConfigDoesntCountAsAnEdit() {
        let store = GlobalShortcutStore()
        var changes = 0
        var updates = 0
        store.onChange = { changes += 1 }
        store.onUpdate = { updates += 1 }
        store.replaceAll([GlobalShortcut(combo: optSpace, action: .appSearch)])
        #expect(changes == 0)
        #expect(updates == 1)
    }

    @Test func hotkeysRoundTripThroughConfig() throws {
        let terminal = AppGroup(name: "Terminal", appBundleIdentifiers: ["com.mitchellh.ghostty"])
        let settings = ConfigSettings(
            appGroups: [terminal],
            hotkeys: [
                GlobalShortcut(combo: shiftCmdV, action: .clipboardHistory),
                GlobalShortcut(combo: optSpace, action: .appSearch),
                GlobalShortcut(combo: KeyCombo(key: .l, modifiers: [.control, .command]), action: .system(.lockScreen)),
                GlobalShortcut(combo: KeyCombo(key: .f5, modifiers: []), action: .windowAction(.leftHalf)),
                GlobalShortcut(combo: KeyCombo(key: .t, modifiers: [.control, .option]), action: .showAppGroup(groupId: terminal.id)),
            ]
        )
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""shortcut" : "shift+cmd+v""#))
        #expect(text.contains(#""command" : "clipboardHistory""#))
        #expect(text.contains(#""command" : "lockScreen""#))

        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.hotkeys.map(\.combo) == settings.hotkeys.map(\.combo))
        #expect(Array(loaded.hotkeys.map(\.action).prefix(4)) == Array(settings.hotkeys.map(\.action).prefix(4)))
        guard case .showAppGroup(let groupId) = loaded.hotkeys.last?.action else {
            Issue.record("The app group shortcut didn't come back")
            return
        }
        #expect(loaded.appGroups.first { $0.id == groupId }?.appBundleIdentifiers == ["com.mitchellh.ghostty"])
    }

    @Test func loadingKeepsTheSameIdsSoNothingReRegisters() throws {
        let json = #"{ "hotkeys": [ { "shortcut": "opt+space", "command": "appSearch" } ] }"#
        let first = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8))).0
        let second = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8))).0
        #expect(first.hotkeys.map(\.id) == second.hotkeys.map(\.id))
    }

    @Test func badHotkeysAreSkippedWithAWarning() throws {
        let json = #"""
        { "hotkeys": [
            { "shortcut": "shift+v", "command": "appSearch" },
            { "shortcut": "opt+space", "command": "appSearch" },
            { "shortcut": "opt+space", "command": "emojiPicker" },
            { "shortcut": "ctrl+opt+x", "command": "makeCoffee" }
        ] }
        """#
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8)))
        #expect(loaded.hotkeys.map(\.action) == [.appSearch])
        #expect(warnings.count == 3)
    }
}
