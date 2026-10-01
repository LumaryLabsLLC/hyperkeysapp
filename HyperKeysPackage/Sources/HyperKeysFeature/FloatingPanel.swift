import AppKit
import SwiftUI

/// Borderless floating panel used by App Search and the App Switcher.
/// The window takes the exact size of its SwiftUI content and grows downward from a pinned top edge.
final class FloatingPanel: NSPanel {
    /// Screen y of the top edge; the panel grows and shrinks downward from here.
    var pinnedTop: CGFloat?

    init(width: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 60),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // The system shadow (and its rim) follows the rectangular window frame, not our rounded
        // glass — the content draws its own shadow instead (see `FloatingPanelChrome`).
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        // Appear instantly — no zoom/fade.
        animationBehavior = .none
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let pinnedTop {
            frame.origin.y = pinnedTop - frame.height
        }
        super.setFrame(frame, display: flag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows a SwiftUI view in a `FloatingPanel` and owns everything around it:
/// keyboard focus, key handling, dismissal and handing focus back to the previous app.
@MainActor
final class FloatingPanelHost {
    let panel: FloatingPanel
    /// Return true when the key was handled.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// How far down the screen the top edge sits, as a fraction of the visible height.
    var topFraction: CGFloat = 0.2

    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    /// The app that was in front when the panel opened.
    private(set) var previousApp: NSRunningApplication?

    init<Content: View>(width: CGFloat, rootView: Content) {
        panel = FloatingPanel(width: width)
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting

        // Clicking anywhere else dismisses it, like Spotlight.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide(restoringFocus: false)
            }
        }
        // Switching to another app (⌘-Tab, Dock, …) doesn't always resign the panel's key status,
        // so also close a focused panel whenever HyperKeys stops being the active app.
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.keyMonitor != nil else { return }
                self.hide(restoringFocus: false)
            }
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// - Parameter takingFocus: Make the panel key and activate HyperKeys so it receives typing.
    ///   Pass false for overlays driven entirely by the hyper key (the ⌘-Tab-style switcher),
    ///   which should appear without disturbing the app you're in.
    /// - Parameter returningTo: The app to hand focus back to, when another HyperKeys panel
    ///   opened this one (otherwise it's whatever app is in front right now).
    func show(takingFocus: Bool = true, returningTo app: NSRunningApplication? = nil) {
        position()
        guard takingFocus else {
            previousApp = nil
            panel.orderFrontRegardless()
            return
        }

        let frontmost = app ?? NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier ? nil : frontmost
        panel.makeKeyAndOrderFront(nil)
        // Take keyboard focus for sure, so typing can never land in the app underneath.
        NSApp.activate()
        installKeyMonitor()
    }

    /// - Parameter restoringFocus: Re-activate the app that was in front before the panel opened
    ///   (used when dismissing without choosing anything).
    func hide(restoringFocus: Bool) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if restoringFocus {
            previousApp?.activate()
        }
        previousApp = nil
    }

    /// Centered horizontally, near the top of the screen the pointer is on.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.pinnedTop = visible.maxY - visible.height * topFraction
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.width / 2
        panel.setFrame(frame, display: false)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                // ⌘, opens settings, as everywhere else on macOS.
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags == .command, event.charactersIgnoringModifiers == "," {
                    // Open the window while HyperKeys still has focus, then close the panel —
                    // closing first lets macOS hand focus back to the previous app, and the
                    // window would open behind it.
                    HyperKeysWindow.open(on: .appSearch)
                    DispatchQueue.main.async {
                        self.hide(restoringFocus: false)
                    }
                    return true
                }
                return self.onKeyDown?(event) ?? false
            }
            return consumed ? nil : event
        }
    }
}
