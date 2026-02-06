import AppKit
import ApplicationServices

/// Swift wrapper around AXUIElement for window manipulation.
public struct AccessibilityElement: @unchecked Sendable {
    public let element: AXUIElement

    public init(element: AXUIElement) {
        self.element = element
    }

    /// Get the focused window of the frontmost application.
    @MainActor
    public static func focusedWindow() -> AccessibilityElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else { return nil }
        return AccessibilityElement(element: value as! AXUIElement)
    }

    public var position: CGPoint? {
        get {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
            guard result == .success else { return nil }
            var point = CGPoint.zero
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
            return point
        }
        set {
            guard var point = newValue else { return }
            if let value = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
            }
        }
    }

    public var size: CGSize? {
        get {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
            guard result == .success else { return nil }
            var size = CGSize.zero
            AXValueGetValue(value as! AXValue, .cgSize, &size)
            return size
        }
        set {
            guard var size = newValue else { return }
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
            }
        }
    }

    /// Get the screen that contains most of this window.
    public func currentScreen() -> NSScreen? {
        guard let pos = position, let sz = size else { return NSScreen.main }
        // pos is in AX coordinates (Y=0 at top of primary screen, increases downward).
        // NSScreen.frame uses Cocoa coordinates (Y=0 at bottom of primary screen, increases upward).
        // Convert AX Y → Cocoa Y before comparing.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let centerX = pos.x + sz.width / 2
        let centerY = primaryHeight - (pos.y + sz.height / 2)
        let cocoaCenter = CGPoint(x: centerX, y: centerY)
        return NSScreen.screens.first { NSMouseInRect(cocoaCenter, $0.frame, false) } ?? NSScreen.main
    }
}
