import AppKit
import ApplicationServices

public struct MenuItemInfo: Sendable {
    public let title: String
    public let path: [String]
    public let children: [MenuItemInfo]
    public let isEnabled: Bool
    /// The item's own keyboard shortcut, e.g. "⇧⌘N".
    public let shortcut: String?

    public init(title: String, path: [String], children: [MenuItemInfo] = [], isEnabled: Bool = true, shortcut: String? = nil) {
        self.title = title
        self.path = path
        self.children = children
        self.isEnabled = isEnabled
        self.shortcut = shortcut
    }

    /// Every item that does something (no submenus), in menu order.
    public var leaves: [MenuItemInfo] {
        children.isEmpty ? [self] : children.flatMap(\.leaves)
    }
}

/// Accessibility-based menu bar access. Not main-actor bound, so large menus can be read
/// on a background task without freezing the UI.
public enum MenuBarReader {
    /// Read all menu items for the app with the given PID.
    public static func readMenuItems(forPID pid: pid_t) -> [MenuItemInfo] {
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = getAttribute(app, attribute: kAXMenuBarAttribute) else { return [] }
        guard let children = getChildren(menuBar) else { return [] }

        var results: [MenuItemInfo] = []
        for child in children {
            if let title = getTitle(child), title != "Apple" {
                let items = readSubmenu(element: child, parentPath: [title])
                results.append(MenuItemInfo(title: title, path: [title], children: items))
            }
        }
        return results
    }

    /// Trigger a menu item by its path (e.g., ["View", "Developer", "Developer Tools"]).
    public static func triggerMenuItem(forPID pid: pid_t, path: [String]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = getAttribute(app, attribute: kAXMenuBarAttribute) else { return false }
        return navigateAndPress(element: menuBar, remainingPath: path)
    }

    private static func readSubmenu(element: AXUIElement, parentPath: [String]) -> [MenuItemInfo] {
        guard let submenu = getChildren(element)?.first,
              let children = getChildren(submenu) else { return [] }

        var items: [MenuItemInfo] = []
        for child in children {
            guard let title = getTitle(child), !title.isEmpty else { continue }
            let path = parentPath + [title]
            let isEnabled = isElementEnabled(child)
            let subItems = readSubmenu(element: child, parentPath: path)
            items.append(MenuItemInfo(title: title, path: path, children: subItems, isEnabled: isEnabled, shortcut: shortcutLabel(child)))
        }
        return items
    }

    private static func navigateAndPress(element: AXUIElement, remainingPath: [String]) -> Bool {
        guard let first = remainingPath.first else { return false }
        guard let children = getChildren(element) else { return false }

        for child in children {
            guard let title = getTitle(child) else { continue }
            if title == first {
                if remainingPath.count == 1 {
                    AXUIElementPerformAction(child, kAXPressAction as CFString)
                    return true
                } else {
                    // Open submenu
                    if let submenu = getChildren(child)?.first {
                        return navigateAndPress(element: submenu, remainingPath: Array(remainingPath.dropFirst()))
                    }
                }
            }
        }
        return false
    }

    private static func getAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    private static func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return nil }
        return array
    }

    private static func getTitle(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// "⇧⌘N" from the item's command key, modifiers and glyph.
    static func shortcutLabel(_ element: AXUIElement) -> String? {
        var key: String?
        if let character = stringValue(element, kAXMenuItemCmdCharAttribute),
           let scalar = character.unicodeScalars.first, character.count == 1,
           !CharacterSet.controlCharacters.contains(scalar), !(0xE000...0xF8FF).contains(scalar.value) {
            key = character.uppercased()
        } else if let glyph = intValue(element, kAXMenuItemCmdGlyphAttribute) {
            key = glyphSymbols[glyph]
        }
        guard let key else { return nil }
        let modifiers = intValue(element, kAXMenuItemCmdModifiersAttribute) ?? 0
        return modifierSymbols(modifiers) + key
    }

    /// kAXMenuItemModifier… flags: Shift 1, Option 2, Control 4, and 8 meaning "no ⌘".
    static func modifierSymbols(_ flags: Int) -> String {
        (flags & 4 != 0 ? "⌃" : "") + (flags & 2 != 0 ? "⌥" : "") + (flags & 1 != 0 ? "⇧" : "") + (flags & 8 == 0 ? "⌘" : "")
    }

    /// Menu glyph codes (Carbon's kMenu…Glyph) for keys that aren't characters.
    private static let glyphSymbols: [Int: String] = {
        var map: [Int: String] = [
            0x02: "⇥", 0x04: "⌤", 0x09: "Space", 0x0A: "⌦", 0x0B: "↩", 0x17: "⌫", 0x1B: "⎋",
            0x62: "⇞", 0x64: "←", 0x65: "→", 0x66: "↖", 0x68: "↑", 0x69: "↘", 0x6A: "↓", 0x6B: "⇟",
        ]
        for n in 1...12 { map[0x6E + n] = "F\(n)" }
        return map
    }()

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func intValue(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func isElementEnabled(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
        guard result == .success else { return true }
        return (value as? Bool) ?? true
    }
}
