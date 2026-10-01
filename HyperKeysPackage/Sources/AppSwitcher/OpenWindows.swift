import AppKit
import ApplicationServices
import Shared

/// One switchable thing: a window of a running app, or the app itself when it has no windows.
public struct OpenWindowEntry: Identifiable {
    public let id: String
    public let app: AppInfo
    public let pid: pid_t
    /// nil when the app has no windows on this Space.
    public let windowTitle: String?
    public let isMinimized: Bool
    /// How many windows this app has, so the UI can tell instances apart.
    public let windowCountForApp: Int
    let element: AXUIElement?

    public init(
        id: String, app: AppInfo, pid: pid_t, windowTitle: String?, isMinimized: Bool, windowCountForApp: Int
    ) {
        self.init(
            id: id, app: app, pid: pid, windowTitle: windowTitle, isMinimized: isMinimized,
            windowCountForApp: windowCountForApp, element: nil
        )
    }

    init(
        id: String, app: AppInfo, pid: pid_t, windowTitle: String?, isMinimized: Bool,
        windowCountForApp: Int, element: AXUIElement?
    ) {
        self.id = id
        self.app = app
        self.pid = pid
        self.windowTitle = windowTitle
        self.isMinimized = isMinimized
        self.windowCountForApp = windowCountForApp
        self.element = element
    }
}

/// Lists open windows in most-recently-used order and brings one to the front.
@MainActor
public enum OpenWindows {
    /// Per-app Accessibility timeout so an unresponsive app can't stall the switcher.
    private static let axTimeout: Float = 0.15

    public static func entries() -> [OpenWindowEntry] {
        let ownPid = NSRunningApplication.current.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPid && $0.bundleURL != nil
        }

        // Front-to-back stacking order approximates "most recently used".
        let order = frontToBackPids()
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = apps.sorted { lhs, rhs in
            let l = rank[lhs.processIdentifier] ?? .max
            let r = rank[rhs.processIdentifier] ?? .max
            if l != r { return l < r }
            return (lhs.localizedName ?? "").localizedCaseInsensitiveCompare(rhs.localizedName ?? "") == .orderedAscending
        }

        var entries: [OpenWindowEntry] = []
        for app in sorted {
            guard let bundleURL = app.bundleURL else { continue }
            let info = AppInfo(
                bundleIdentifier: app.bundleIdentifier ?? bundleURL.path,
                name: app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                path: bundleURL.path
            )
            let windows = axWindows(pid: app.processIdentifier)
            if windows.isEmpty {
                entries.append(OpenWindowEntry(
                    id: "\(app.processIdentifier)", app: info, pid: app.processIdentifier,
                    windowTitle: nil, isMinimized: false, windowCountForApp: 0, element: nil
                ))
            } else {
                for (index, window) in windows.enumerated() {
                    entries.append(OpenWindowEntry(
                        id: "\(app.processIdentifier)-\(index)", app: info, pid: app.processIdentifier,
                        windowTitle: window.title, isMinimized: window.isMinimized,
                        windowCountForApp: windows.count, element: window.element
                    ))
                }
            }
        }
        return entries
    }

    /// Brings the entry's window (un-minimizing it if needed) and its app to the front.
    public static func focus(_ entry: OpenWindowEntry) {
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }

        guard let window = entry.element else {
            // No windows: reopen, which makes most apps create a new window.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: entry.app.path), configuration: configuration)
            return
        }

        if entry.isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    // MARK: - Private

    private struct AXWindow {
        let element: AXUIElement
        let title: String?
        let isMinimized: Bool
    }

    private static func axWindows(pid: pid_t) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            let subrole = stringAttribute(window, kAXSubroleAttribute)
            // Real document/app windows only — skip palettes, sheets, tooltips and the like.
            guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { return nil }
            let title = stringAttribute(window, kAXTitleAttribute)
            return AXWindow(
                element: window,
                title: (title?.isEmpty ?? true) ? nil : title,
                isMinimized: boolAttribute(window, kAXMinimizedAttribute)
            )
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func frontToBackPids() -> [pid_t] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var seen = Set<pid_t>()
        var order: [pid_t] = []
        for window in info where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, seen.insert(pid).inserted else { continue }
            order.append(pid)
        }
        return order
    }
}
