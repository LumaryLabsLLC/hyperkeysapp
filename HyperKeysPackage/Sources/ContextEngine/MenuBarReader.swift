import AppKit
import ApplicationServices

public struct MenuItemInfo: Sendable {
    public let title: String
    public let path: [String]
    public let children: [MenuItemInfo]
    public let isEnabled: Bool

    public init(title: String, path: [String], children: [MenuItemInfo] = [], isEnabled: Bool = true) {
        self.title = title
        self.path = path
        self.children = children
        self.isEnabled = isEnabled
    }
}

@MainActor
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
            items.append(MenuItemInfo(title: title, path: path, children: subItems, isEnabled: isEnabled))
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

    private static func isElementEnabled(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
        guard result == .success else { return true }
        return (value as? Bool) ?? true
    }
}
