import EventEngine
import Foundation
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings
import WindowEngine

@MainActor
struct AliasStoreTests {
    @Test func aliasesAreOneLowercaseWord() {
        #expect(Alias(text: " G H ", action: .appSearch).text == "gh")
    }

    @Test func anAliasNamesOneThingAndAThingHasOneAlias() {
        let store = AliasStore()
        var changes = 0
        store.onChange = { changes += 1 }

        store.save(Alias(text: "e", action: .emojiPicker))
        store.save(Alias(text: "em", action: .emojiPicker))
        #expect(store.aliases.map(\.text) == ["em"])

        store.save(Alias(text: "em", action: .snippets))
        #expect(store.alias(for: .emojiPicker) == nil)
        #expect(store.alias(matching: "EM")?.action == .snippets)

        store.save(Alias(text: "  ", action: .appSearch))
        #expect(store.aliases.count == 1)
        #expect(changes == 3)
    }

    @Test func followsAQuicklinkToItsNewName() {
        let store = AliasStore()
        store.replaceAll([Alias(text: "gh", action: .quicklink(name: "GitHub"))])
        store.renameQuicklink(from: "github", to: "Search GitHub")
        #expect(store.aliases.first?.action == .quicklink(name: "Search GitHub"))

        let shortcuts = GlobalShortcutStore()
        shortcuts.set(.init(key: .g, modifiers: [.option]), for: .quicklink(name: "GitHub"))
        shortcuts.renameQuicklink(from: "GitHub", to: "Search GitHub")
        #expect(shortcuts.shortcuts.first?.action == .quicklink(name: "Search GitHub"))
    }

    @Test func aliasesRoundTripThroughConfig() throws {
        let settings = ConfigSettings(aliases: [
            Alias(text: "gh", action: .quicklink(name: "Search GitHub")),
            Alias(text: "lh", action: .windowAction(.leftHalf)),
            Alias(text: "dt", action: .triggerMenuItem(appBundleId: "com.google.Chrome", menuPath: ["View", "Developer", "Developer Tools"])),
        ])
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""alias" : "gh""#))
        #expect(text.contains(#""quicklink" : "Search GitHub""#))

        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.aliases.map(\.text) == ["gh", "lh", "dt"])
        #expect(loaded.aliases.map(\.action) == settings.aliases.map(\.action))
    }

    @Test func badAliasesAreSkippedWithAWarning() throws {
        let json = #"""
        { "aliases": [
            { "alias": "GH", "quicklink": "Search GitHub" },
            { "alias": "gh", "command": "appSearch" },
            { "alias": "", "command": "appSearch" },
            { "alias": "x", "command": "makeCoffee" }
        ] }
        """#
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8)))
        #expect(loaded.aliases.map(\.text) == ["gh"])
        #expect(warnings.count == 3)
    }
}

@MainActor
struct AliasSearchTests {
    private let devTools = BoundAction.triggerMenuItem(appBundleId: "com.google.Chrome", menuPath: ["View", "Developer", "Developer Tools"])

    private func model(aliases: [Alias]) -> AppSearchModel {
        var search = LauncherCommand(
            id: "quicklink-gh", title: "Search GitHub", subtitle: "github.com", icon: .symbol("link", .blue),
            action: .quicklink(name: "Search GitHub"), isQuicklink: true
        ) { _ in }
        search.runWithArgument = { _, _ in }
        let controller = AppSearchController.shared
        var commands = controller.makeCommands() + [search]
        commands += controller.aliasOnlyCommands(besides: commands, aliases: aliases)
        let model = AppSearchModel()
        model.prepare(bindings: [], hyperKey: .capsLock, commands: commands, aliases: aliases)
        return model
    }

    @Test func typingAnAliasPutsItsItemFirst() {
        let model = model(aliases: [Alias(text: "ll", action: .windowAction(.leftHalf)), Alias(text: "zz", action: .emojiPicker)])
        model.query = "ll"
        #expect(model.items.first?.id == "command-window-leftHalf")
        #expect(model.aliasLabels["command-window-leftHalf"] == "ll")

        // The start of an alias ranks it high too.
        model.query = "z"
        #expect(model.items.first?.id == "command-emoji")
    }

    @Test func anAliasCanNameSomethingAppSearchDoesntList() {
        let model = model(aliases: [Alias(text: "dt", action: devTools)])
        model.query = "dt"
        guard case .command(let command) = model.items.first else {
            Issue.record("Expected the menu command first")
            return
        }
        #expect(command.isAliasOnly)
        #expect(command.action == devTools)
        #expect(command.title == "Developer Tools")

        // Only by its alias, so it doesn't crowd ordinary searches.
        model.query = "developer tools"
        #expect(!model.items.contains { $0.id == "command-\(command.id)" })
    }

    @Test func textAfterAQuicklinksAliasIsItsArgument() {
        let model = model(aliases: [Alias(text: "gh", action: .quicklink(name: "Search GitHub"))])
        model.query = "gh SwiftUI navigation"
        #expect(model.items.first?.id == "command-quicklink-gh")
        #expect(model.aliasArgument?.itemId == "command-quicklink-gh")
        #expect(model.aliasArgument?.text == "SwiftUI navigation")

        model.query = "gh"
        #expect(model.aliasArgument == nil)
        #expect(model.items.first?.id == "command-quicklink-gh")

        // Other aliases don't take text.
        let other = self.model(aliases: [Alias(text: "ll", action: .windowAction(.leftHalf))])
        other.query = "ll something"
        #expect(other.aliasArgument == nil)
    }

    @Test func appsCanHaveAliases() {
        let model = model(aliases: [Alias(text: "fi", action: .launchApp(bundleId: "com.apple.finder", appName: "Finder"))])
        model.query = "fi"
        #expect(model.items.first?.id == "app-com.apple.finder")
    }
}

@MainActor
struct AppSearchShortcutTests {
    @Test func showsRegularShortcutsNextToItems() {
        let model = AppSearchModel()
        let lock = KeyCombo(key: .l, modifiers: [.control, .command])
        model.prepare(
            bindings: [], hyperKey: .capsLock, commands: AppSearchController.shared.makeCommands(),
            hotkeys: [GlobalShortcut(combo: lock, action: .system(.lockScreen))]
        )
        #expect(model.combos["command-system-lockScreen"] == lock)
    }
}
