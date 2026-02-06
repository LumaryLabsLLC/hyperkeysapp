import AppKit
import Shared

@MainActor
public enum WindowManager {
    /// Move a specific app's window to a position. Returns true if the window was found and positioned.
    @discardableResult
    public static func moveWindow(to position: WindowPosition, ofApp bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var value: AnyObject?
        var result = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &value)
        if result != .success {
            result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        }
        guard result == .success else { return false }

        var window = AccessibilityElement(element: value as! AXUIElement)
        guard let screen = window.currentScreen() else { return false }
        let frame = gappedFrame(for: screen)

        switch position {
        case .maximizeHeight:
            applyMaximizeHeight(window: &window, frame: frame)
        case .maximizeWidth:
            applyMaximizeWidth(window: &window, frame: frame)
        default:
            let (origin, size) = targetRect(for: position, in: frame)
            applyRect(window: &window, origin: origin, size: size)
        }
        return true
    }

    /// Move the frontmost app's focused window to a position.
    public static func moveWindow(to position: WindowPosition) {
        guard var window = AccessibilityElement.focusedWindow() else { return }
        guard let screen = window.currentScreen() else { return }
        let frame = gappedFrame(for: screen)

        switch position {
        case .maximizeHeight:
            applyMaximizeHeight(window: &window, frame: frame)
        case .maximizeWidth:
            applyMaximizeWidth(window: &window, frame: frame)
        default:
            let (origin, size) = targetRect(for: position, in: frame)
            applyRect(window: &window, origin: origin, size: size)
        }
    }

    private static func screenVisibleFrame(_ screen: NSScreen) -> CGRect {
        let mainScreen = NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        let y = mainScreen.frame.height - visibleFrame.origin.y - visibleFrame.height
        return CGRect(x: visibleFrame.origin.x, y: y, width: visibleFrame.width, height: visibleFrame.height)
    }

    private static func gappedFrame(for screen: NSScreen) -> CGRect {
        let frame = screenVisibleFrame(screen)
        let halfGap = WindowGap.load().points / 2
        return CGRect(
            x: frame.origin.x + halfGap,
            y: frame.origin.y + halfGap,
            width: frame.width - halfGap * 2,
            height: frame.height - halfGap * 2
        )
    }

    private static func targetRect(for position: WindowPosition, in frame: CGRect) -> (CGPoint, CGSize) {
        let halfW = frame.width / 2
        let halfH = frame.height / 2
        let thirdW = frame.width / 3
        let fourthW = frame.width / 4

        switch position {
        // Halves
        case .leftHalf:
            return (frame.origin, CGSize(width: halfW, height: frame.height))
        case .rightHalf:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y), CGSize(width: halfW, height: frame.height))
        case .topHalf:
            return (frame.origin, CGSize(width: frame.width, height: halfH))
        case .bottomHalf:
            return (CGPoint(x: frame.origin.x, y: frame.origin.y + halfH), CGSize(width: frame.width, height: halfH))
        // Quarters
        case .topLeftQuarter:
            return (frame.origin, CGSize(width: halfW, height: halfH))
        case .topRightQuarter:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y), CGSize(width: halfW, height: halfH))
        case .bottomLeftQuarter:
            return (CGPoint(x: frame.origin.x, y: frame.origin.y + halfH), CGSize(width: halfW, height: halfH))
        case .bottomRightQuarter:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y + halfH), CGSize(width: halfW, height: halfH))
        // Thirds
        case .firstThird:
            return (frame.origin, CGSize(width: thirdW, height: frame.height))
        case .centerThird:
            return (CGPoint(x: frame.origin.x + thirdW, y: frame.origin.y), CGSize(width: thirdW, height: frame.height))
        case .lastThird:
            return (CGPoint(x: frame.origin.x + thirdW * 2, y: frame.origin.y), CGSize(width: thirdW, height: frame.height))
        case .firstTwoThirds:
            return (frame.origin, CGSize(width: thirdW * 2, height: frame.height))
        case .lastTwoThirds:
            return (CGPoint(x: frame.origin.x + thirdW, y: frame.origin.y), CGSize(width: thirdW * 2, height: frame.height))
        // Sixths
        case .topLeftSixth:
            return (frame.origin, CGSize(width: thirdW, height: halfH))
        case .topCenterSixth:
            return (CGPoint(x: frame.origin.x + thirdW, y: frame.origin.y), CGSize(width: thirdW, height: halfH))
        case .topRightSixth:
            return (CGPoint(x: frame.origin.x + thirdW * 2, y: frame.origin.y), CGSize(width: thirdW, height: halfH))
        case .bottomLeftSixth:
            return (CGPoint(x: frame.origin.x, y: frame.origin.y + halfH), CGSize(width: thirdW, height: halfH))
        case .bottomCenterSixth:
            return (CGPoint(x: frame.origin.x + thirdW, y: frame.origin.y + halfH), CGSize(width: thirdW, height: halfH))
        case .bottomRightSixth:
            return (CGPoint(x: frame.origin.x + thirdW * 2, y: frame.origin.y + halfH), CGSize(width: thirdW, height: halfH))
        // Fourths
        case .firstFourth:
            return (frame.origin, CGSize(width: fourthW, height: frame.height))
        case .secondFourth:
            return (CGPoint(x: frame.origin.x + fourthW, y: frame.origin.y), CGSize(width: fourthW, height: frame.height))
        case .thirdFourth:
            return (CGPoint(x: frame.origin.x + fourthW * 2, y: frame.origin.y), CGSize(width: fourthW, height: frame.height))
        case .lastFourth:
            return (CGPoint(x: frame.origin.x + fourthW * 3, y: frame.origin.y), CGSize(width: fourthW, height: frame.height))
        // Special
        case .fullScreen:
            return (frame.origin, frame.size)
        case .center:
            let w = frame.width * 0.6
            let h = frame.height * 0.7
            return (CGPoint(x: frame.origin.x + (frame.width - w) / 2, y: frame.origin.y + (frame.height - h) / 2),
                    CGSize(width: w, height: h))
        case .reasonableSize:
            let w = frame.width * 0.9
            let h = frame.height * 0.9
            return (CGPoint(x: frame.origin.x + (frame.width - w) / 2, y: frame.origin.y + (frame.height - h) / 2),
                    CGSize(width: w, height: h))
        case .maximizeHeight, .maximizeWidth:
            return (frame.origin, frame.size) // handled separately
        }
    }

    /// Apply position and size with a second pass to handle apps that constrain layout.
    private static func applyRect(window: inout AccessibilityElement, origin: CGPoint, size: CGSize) {
        window.position = origin
        window.size = size
        window.position = origin
    }

    // MARK: - Special position helpers

    private static func applyMaximizeHeight(window: inout AccessibilityElement, frame: CGRect) {
        guard let pos = window.position, let sz = window.size else { return }
        applyRect(window: &window, origin: CGPoint(x: pos.x, y: frame.origin.y), size: CGSize(width: sz.width, height: frame.height))
    }

    private static func applyMaximizeWidth(window: inout AccessibilityElement, frame: CGRect) {
        guard let pos = window.position, let sz = window.size else { return }
        applyRect(window: &window, origin: CGPoint(x: frame.origin.x, y: pos.y), size: CGSize(width: frame.width, height: sz.height))
    }

}
