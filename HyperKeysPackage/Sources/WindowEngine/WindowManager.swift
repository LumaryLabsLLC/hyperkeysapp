import AppKit
import Shared

@MainActor
public enum WindowManager {
    /// Where each window was before HyperKeys last moved it, for Restore.
    private static var previousFrames: [WindowKey: CGRect] = [:]

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
        guard result == .success, let element = value else { return false }
        // swiftlint:disable:next force_cast
        apply(position, to: AccessibilityElement(element: element as! AXUIElement))
        return true
    }

    /// Move the frontmost app's focused window to a position.
    public static func moveWindow(to position: WindowPosition) {
        guard let window = AccessibilityElement.focusedWindow() else { return }
        apply(position, to: window)
    }

    private static func apply(_ position: WindowPosition, to window: AccessibilityElement) {
        var window = window
        switch position {
        case .toggleFullScreen:
            toggleFullScreen(window)
            return
        case .restore:
            restore(&window)
            return
        default:
            break
        }
        guard let screen = window.currentScreen() else { return }
        remember(window)
        let frame = gappedFrame(for: screen)

        switch position {
        case .nextDisplay, .previousDisplay:
            moveToAdjacentDisplay(&window, from: screen, forward: position == .nextDisplay)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            moveToEdge(&window, position, in: frame)
        case .maximizeHeight:
            applyMaximizeHeight(window: &window, frame: frame)
        case .maximizeWidth:
            applyMaximizeWidth(window: &window, frame: frame)
        default:
            let (origin, size) = cycledRect(for: position, window: window, in: frame) ?? targetRect(for: position, in: frame)
            applyRect(window: &window, origin: origin, size: size)
        }
    }

    // MARK: - Screens

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

    // MARK: - Layouts

    static func targetRect(for position: WindowPosition, in frame: CGRect) -> (CGPoint, CGSize) {
        let halfW = frame.width / 2
        let halfH = frame.height / 2
        let thirdW = frame.width / 3
        let fourthW = frame.width / 4

        func centered(width: CGFloat, height: CGFloat) -> (CGPoint, CGSize) {
            (CGPoint(x: frame.origin.x + (frame.width - width) / 2, y: frame.origin.y + (frame.height - height) / 2),
             CGSize(width: width, height: height))
        }

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
        case .centerHalf:
            return (CGPoint(x: frame.origin.x + fourthW, y: frame.origin.y), CGSize(width: halfW, height: frame.height))
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
        case .centerTwoThirds:
            return (CGPoint(x: frame.origin.x + thirdW / 2, y: frame.origin.y), CGSize(width: thirdW * 2, height: frame.height))
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
        case .firstThreeFourths:
            return (frame.origin, CGSize(width: fourthW * 3, height: frame.height))
        case .lastThreeFourths:
            return (CGPoint(x: frame.origin.x + fourthW, y: frame.origin.y), CGSize(width: fourthW * 3, height: frame.height))
        // Special
        case .fullScreen:
            return (frame.origin, frame.size)
        case .almostMaximize:
            return centered(width: frame.width * 0.9, height: frame.height * 0.9)
        case .center:
            return centered(width: frame.width * 0.6, height: frame.height * 0.7)
        case .reasonableSize:
            // Like Raycast: 60% wide and 80% tall, no bigger than 1025 × 900.
            return centered(width: min(frame.width * 0.6, 1025), height: min(frame.height * 0.8, 900))
        case .maximizeHeight, .maximizeWidth,
             .moveLeft, .moveRight, .moveUp, .moveDown, .nextDisplay, .previousDisplay, .toggleFullScreen, .restore:
            return (frame.origin, frame.size) // handled separately
        }
    }

    /// With cycling on, pressing Left or Right Half again goes ½ → ⅔ → ⅓ → ½.
    static func cycledRect(for position: WindowPosition, window: AccessibilityElement, in frame: CGRect) -> (CGPoint, CGSize)? {
        guard Preferences.isCycleHalvesEnabled, position == .leftHalf || position == .rightHalf,
              let origin = window.position, let size = window.size
        else { return nil }
        return nextCycleRect(current: CGRect(origin: origin, size: size), left: position == .leftHalf, frame: frame)
    }

    static func nextCycleRect(current: CGRect, left: Bool, frame: CGRect) -> (CGPoint, CGSize) {
        let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
        let rects = fractions.map { fraction -> CGRect in
            let width = frame.width * fraction
            return CGRect(x: left ? frame.minX : frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        }
        let tolerance: CGFloat = 12
        let index = rects.firstIndex {
            abs($0.minX - current.minX) < tolerance && abs($0.width - current.width) < tolerance
                && abs($0.minY - current.minY) < tolerance && abs($0.height - current.height) < tolerance
        }
        let next = rects[index.map { ($0 + 1) % rects.count } ?? 0]
        return (next.origin, next.size)
    }

    // MARK: - Moves

    private static func moveToEdge(_ window: inout AccessibilityElement, _ position: WindowPosition, in frame: CGRect) {
        guard let origin = window.position, let size = window.size else { return }
        let width = min(size.width, frame.width)
        let height = min(size.height, frame.height)
        var target = CGPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - width),
            y: min(max(origin.y, frame.minY), frame.maxY - height)
        )
        switch position {
        case .moveLeft: target.x = frame.minX
        case .moveRight: target.x = frame.maxX - width
        case .moveUp: target.y = frame.minY
        case .moveDown: target.y = frame.maxY - height
        default: break
        }
        applyRect(window: &window, origin: target, size: CGSize(width: width, height: height))
    }

    /// Keeps the window's place and size relative to the screen, on the next screen to the right
    /// (or left), wrapping around.
    private static func moveToAdjacentDisplay(_ window: inout AccessibilityElement, from screen: NSScreen, forward: Bool) {
        let screens = NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard screens.count > 1, let index = screens.firstIndex(of: screen),
              let origin = window.position, let size = window.size
        else { return }
        let target = screens[(index + (forward ? 1 : -1) + screens.count) % screens.count]
        let (newOrigin, newSize) = mapRect(
            CGRect(origin: origin, size: size), from: gappedFrame(for: screen), to: gappedFrame(for: target)
        )
        applyRect(window: &window, origin: newOrigin, size: newSize)
    }

    static func mapRect(_ rect: CGRect, from source: CGRect, to target: CGRect) -> (CGPoint, CGSize) {
        let width = min(rect.width / source.width * target.width, target.width)
        let height = min(rect.height / source.height * target.height, target.height)
        let x = target.minX + (rect.minX - source.minX) / source.width * target.width
        let y = target.minY + (rect.minY - source.minY) / source.height * target.height
        return (
            CGPoint(x: min(max(x, target.minX), target.maxX - width), y: min(max(y, target.minY), target.maxY - height)),
            CGSize(width: width, height: height)
        )
    }

    private static func toggleFullScreen(_ window: AccessibilityElement) {
        let attribute = "AXFullScreen" as CFString
        var value: AnyObject?
        let isFullScreen = AXUIElementCopyAttributeValue(window.element, attribute, &value) == .success && (value as? Bool) == true
        AXUIElementSetAttributeValue(window.element, attribute, (!isFullScreen) as CFBoolean)
    }

    // MARK: - Restore

    private static func remember(_ window: AccessibilityElement) {
        guard let origin = window.position, let size = window.size else { return }
        previousFrames[WindowKey(window.element)] = CGRect(origin: origin, size: size)
    }

    /// Puts the window back where it was before HyperKeys last moved it; again to undo that.
    private static func restore(_ window: inout AccessibilityElement) {
        let key = WindowKey(window.element)
        guard let frame = previousFrames[key] else {
            NSSound.beep()
            return
        }
        remember(window)
        applyRect(window: &window, origin: frame.origin, size: frame.size)
    }

    // MARK: - Applying

    /// Apply position and size with a second pass to handle apps that constrain layout.
    private static func applyRect(window: inout AccessibilityElement, origin: CGPoint, size: CGSize) {
        window.position = origin
        window.size = size
        window.position = origin
    }

    private static func applyMaximizeHeight(window: inout AccessibilityElement, frame: CGRect) {
        guard let pos = window.position, let sz = window.size else { return }
        applyRect(window: &window, origin: CGPoint(x: pos.x, y: frame.origin.y), size: CGSize(width: sz.width, height: frame.height))
    }

    private static func applyMaximizeWidth(window: inout AccessibilityElement, frame: CGRect) {
        guard let pos = window.position, let sz = window.size else { return }
        applyRect(window: &window, origin: CGPoint(x: frame.origin.x, y: pos.y), size: CGSize(width: frame.width, height: sz.height))
    }
}

/// An Accessibility window element usable as a dictionary key (same window, same key).
private struct WindowKey: Hashable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
