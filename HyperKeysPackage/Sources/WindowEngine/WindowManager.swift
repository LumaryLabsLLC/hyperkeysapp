import AppKit

@MainActor
public enum WindowManager {
    public static func moveWindow(to position: WindowPosition) {
        guard var window = AccessibilityElement.focusedWindow() else { return }

        switch position {
        case .nextScreen:
            moveToAdjacentScreen(window: &window, next: true)
            return
        case .previousScreen:
            moveToAdjacentScreen(window: &window, next: false)
            return
        default:
            break
        }

        guard let screen = window.currentScreen() else { return }
        let frame = screenVisibleFrame(screen)
        let (origin, size) = targetRect(for: position, in: frame)

        window.size = size
        window.position = origin
    }

    private static func screenVisibleFrame(_ screen: NSScreen) -> CGRect {
        // Convert from NSScreen coordinates (origin at bottom-left) to CG coordinates (origin at top-left)
        let mainScreen = NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        let y = mainScreen.frame.height - visibleFrame.origin.y - visibleFrame.height
        return CGRect(x: visibleFrame.origin.x, y: y, width: visibleFrame.width, height: visibleFrame.height)
    }

    private static func targetRect(for position: WindowPosition, in frame: CGRect) -> (CGPoint, CGSize) {
        let halfW = frame.width / 2
        let halfH = frame.height / 2

        switch position {
        case .leftHalf:
            return (frame.origin, CGSize(width: halfW, height: frame.height))
        case .rightHalf:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y), CGSize(width: halfW, height: frame.height))
        case .topHalf:
            return (frame.origin, CGSize(width: frame.width, height: halfH))
        case .bottomHalf:
            return (CGPoint(x: frame.origin.x, y: frame.origin.y + halfH), CGSize(width: frame.width, height: halfH))
        case .topLeftQuarter:
            return (frame.origin, CGSize(width: halfW, height: halfH))
        case .topRightQuarter:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y), CGSize(width: halfW, height: halfH))
        case .bottomLeftQuarter:
            return (CGPoint(x: frame.origin.x, y: frame.origin.y + halfH), CGSize(width: halfW, height: halfH))
        case .bottomRightQuarter:
            return (CGPoint(x: frame.origin.x + halfW, y: frame.origin.y + halfH), CGSize(width: halfW, height: halfH))
        case .fullScreen:
            return (frame.origin, frame.size)
        case .center:
            let w = frame.width * 0.6
            let h = frame.height * 0.7
            return (CGPoint(x: frame.origin.x + (frame.width - w) / 2, y: frame.origin.y + (frame.height - h) / 2),
                    CGSize(width: w, height: h))
        case .nextScreen, .previousScreen:
            return (frame.origin, frame.size) // handled separately
        }
    }

    private static func moveToAdjacentScreen(window: inout AccessibilityElement, next: Bool) {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        guard let currentScreen = window.currentScreen(),
              let currentIndex = screens.firstIndex(of: currentScreen) else { return }

        let targetIndex = next
            ? (currentIndex + 1) % screens.count
            : (currentIndex - 1 + screens.count) % screens.count
        let targetScreen = screens[targetIndex]

        let targetFrame = screenVisibleFrame(targetScreen)
        let currentFrame = screenVisibleFrame(currentScreen)

        guard let pos = window.position, let sz = window.size else { return }

        // Calculate relative position on current screen
        let relX = (pos.x - currentFrame.origin.x) / currentFrame.width
        let relY = (pos.y - currentFrame.origin.y) / currentFrame.height
        let relW = sz.width / currentFrame.width
        let relH = sz.height / currentFrame.height

        // Apply to target screen
        let newX = targetFrame.origin.x + relX * targetFrame.width
        let newY = targetFrame.origin.y + relY * targetFrame.height
        let newW = relW * targetFrame.width
        let newH = relH * targetFrame.height

        window.size = CGSize(width: newW, height: newH)
        window.position = CGPoint(x: newX, y: newY)
    }
}
