import ContextEngine
import EventEngine
import Foundation
import Testing
@testable import ContextEngine
@testable import HyperKeysFeature
@testable import KeyBindings

@MainActor
struct MenuSearchTests {
    private let menus = [
        MenuItemInfo(title: "Notes", path: ["Notes"], children: [
            MenuItemInfo(title: "Services", path: ["Notes", "Services"], children: [
                MenuItemInfo(title: "Activity Monitor", path: ["Notes", "Services", "Activity Monitor"]),
            ]),
            MenuItemInfo(title: "Settings…", path: ["Notes", "Settings…"], shortcut: "⌘,"),
        ]),
        MenuItemInfo(title: "File", path: ["File"], children: [
            MenuItemInfo(title: "New Window", path: ["File", "New Window"], shortcut: "⌘N"),
            MenuItemInfo(title: "Open Recent", path: ["File", "Open Recent"], children: [
                MenuItemInfo(title: "notes.md", path: ["File", "Open Recent", "notes.md"]),
            ]),
            MenuItemInfo(title: "Print…", path: ["File", "Print…"], isEnabled: false),
        ]),
        MenuItemInfo(title: "View", path: ["View"], children: [
            MenuItemInfo(title: "Developer", path: ["View", "Developer"], children: [
                MenuItemInfo(title: "Developer Tools", path: ["View", "Developer", "Developer Tools"], shortcut: "⌥⌘I"),
            ]),
            MenuItemInfo(title: "Enter Full Screen", path: ["View", "Enter Full Screen"], shortcut: "⌃⌘F"),
        ]),
    ]

    @Test func listsEnabledItemsThatDoSomething() {
        let commands = MenuSearchModel.commands(from: menus)
        #expect(commands.map(\.title) == ["Settings…", "New Window", "notes.md", "Developer Tools", "Enter Full Screen"])
        #expect(commands.first { $0.title == "Developer Tools" }?.location == "View › Developer")
        #expect(commands.first { $0.title == "New Window" }?.shortcut == "⌘N")
    }

    @Test func searchMatchesTitlesFirstThenMenus() {
        let model = MenuSearchModel()
        let commands = MenuSearchModel.commands(from: menus)
        model.setForTesting(commands)

        model.query = "full"
        #expect(model.items.first?.title == "Enter Full Screen")

        model.query = "view dev"
        #expect(model.items.map(\.title) == ["Developer Tools"])
    }

    @Test func spellsModifiersLikeMenusDo() {
        #expect(MenuBarReader.modifierSymbols(0) == "⌘")
        #expect(MenuBarReader.modifierSymbols(1) == "⇧⌘")
        #expect(MenuBarReader.modifierSymbols(6) == "⌃⌥⌘")
        #expect(MenuBarReader.modifierSymbols(8) == "")
    }

    @Test func menuSearchShortcutsRoundTripAndImport() throws {
        let data = try ConfigCodec.encode(ConfigCodec.document(from: ConfigSettings(bindings: [KeyBinding(keyCode: .m, action: .menuSearch)], snippets: [])))
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.first?.action == .menuSearch)

        let mapped = RaycastImportPlan.map(.command(extensionId: "e:r:navigation", id: "e:r:navigation::search-menu-items", title: nil), resolveApp: { _ in nil })
        #expect(mapped == .action(.menuSearch, title: "Search Menu Items"))
    }
}
