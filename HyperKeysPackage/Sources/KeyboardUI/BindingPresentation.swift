import AppKit
import AppSwitcher
import KeyBindings
import Shared
import SwiftUI
import WindowEngine

/// Everything the UI needs to describe a bound action: title, subtitle, icons and kind.
public struct BindingPresentation: Equatable, Sendable {
    public let kind: ActionKind
    public let title: String
    public let subtitle: String
    public let appBundleIds: [String]
    public let windowPosition: WindowPosition?
    /// Files or folders whose Finder icons represent this binding.
    public var filePaths: [String] = []
    public var systemAction: SystemAction?
    /// For quicklinks to websites: the site whose icon to show.
    public var faviconHost: String?

    /// The SF Symbol for command-style actions; system actions each have their own.
    public var symbol: String {
        systemAction?.symbol ?? kind.symbol
    }

    @MainActor
    public init?(_ action: BoundAction) {
        guard let kind = ActionKind(action) else { return nil }
        self.kind = kind

        switch action {
        case .launchApp(let bundleId, let appName):
            title = appName
            subtitle = "Open App"
            appBundleIds = [bundleId]
            windowPosition = nil

        case .showAppGroup(let groupId):
            let group = AppGroupStore.shared.group(id: groupId)
            let names = (group?.appBundleIdentifiers ?? []).compactMap { AppInfo.resolve(bundleId: $0)?.name }
            title = group?.name ?? "App Group"
            subtitle = names.isEmpty ? "Open Apps" : names.joined(separator: ", ")
            appBundleIds = group?.appBundleIdentifiers ?? []
            windowPosition = nil

        case .windowAction(let position):
            title = position.displayName
            subtitle = "Window Layout"
            appBundleIds = []
            windowPosition = position

        case .triggerMenuItem(let appBundleId, let menuPath):
            let appName = AppInfo.resolve(bundleId: appBundleId)?.name ?? appBundleId
            title = menuPath.last ?? "Menu Command"
            subtitle = ([appName] + menuPath.dropLast()).joined(separator: " › ")
            appBundleIds = [appBundleId]
            windowPosition = nil

        case .appSearch:
            title = "App Search"
            subtitle = "Search and open any app"
            appBundleIds = []
            windowPosition = nil

        case .appSwitcher:
            title = "App Switcher"
            subtitle = "Switch between open apps and windows"
            appBundleIds = []
            windowPosition = nil

        case .emojiPicker:
            title = "Emoji & Symbols"
            subtitle = "Search and paste emoji and symbols"
            appBundleIds = []
            windowPosition = nil

        case .openFolder(let path):
            let expanded = (path as NSString).expandingTildeInPath
            title = expanded == NSHomeDirectory() ? "Home" : FileManager.default.displayName(atPath: expanded)
            subtitle = (expanded as NSString).abbreviatingWithTildeInPath
            appBundleIds = []
            windowPosition = nil
            filePaths = [expanded]

        case .emptyTrash:
            title = "Empty Trash"
            subtitle = "Permanently delete what's in the Trash"
            appBundleIds = []
            windowPosition = nil

        case .snippets:
            title = "Snippets"
            subtitle = "Search and paste your snippets"
            appBundleIds = []
            windowPosition = nil

        case .clipboardHistory:
            title = "Clipboard History"
            subtitle = "Search and paste what you've copied"
            appBundleIds = []
            windowPosition = nil

        case .killProcess:
            title = "Kill Process"
            subtitle = "Quit or force quit a running app or process"
            appBundleIds = []
            windowPosition = nil

        case .quicklink(let name):
            let quicklink = QuicklinkStore.shared.quicklink(named: name)
            title = name
            subtitle = quicklink?.displayLink ?? "Quicklink"
            appBundleIds = []
            windowPosition = nil
            faviconHost = quicklink?.host
            if let path = quicklink?.localPath {
                filePaths = [path]
            } else if let app = quicklink?.openingAppURL {
                filePaths = [app.path]
            }

        case .menuSearch:
            title = "Search Menu Items"
            subtitle = "Find and run any menu command in the app you're in"
            appBundleIds = []
            windowPosition = nil

        case .gifSearch:
            title = "Search GIFs"
            subtitle = "Find a GIF or clip on GIPHY or Klipy and copy it"
            appBundleIds = []
            windowPosition = nil

        case .system(let action):
            title = action.title
            subtitle = action.detail
            appBundleIds = []
            windowPosition = nil
            systemAction = action

        case .none:
            return nil
        }
    }

    @MainActor
    public var icons: [NSImage] {
        if let faviconHost, let favicon = FaviconCache.shared.icon(forHost: faviconHost) {
            return [favicon]
        }
        return appBundleIds.compactMap { AppIconCache.icon(forBundleId: $0) }
            + filePaths.map { AppIconCache.icon(forPath: $0) }
    }

    /// One-line description for tooltips and accessibility.
    public var summary: String {
        switch kind {
        case .app: "Open \(title)"
        case .appGroup: "Open \(title): \(subtitle)"
        case .window: "Move window to \(title)"
        case .menu: "\(subtitle) › \(title)"
        case .appSearch: "Open App Search"
        case .appSwitcher: "Open the App Switcher"
        case .emojiPicker: "Open Emoji & Symbols"
        case .folder: "Open \(subtitle)"
        case .snippets: "Open Snippets"
        case .clipboardHistory: "Open Clipboard History"
        case .killProcess: "Open Kill Process"
        case .menuSearch: "Search the current app's menus"
        case .gifSearch: "Search for GIFs"
        case .quicklink: "Open \(title)"
        case .system: title
        case .emptyTrash: "Empty the Trash"
        }
    }
}

/// Leading icon for a binding row: the app icon(s), a layout glyph, or a kind tile.
public struct BindingIcon: View {
    let presentation: BindingPresentation
    var size: CGFloat = 28

    public init(presentation: BindingPresentation, size: CGFloat = 28) {
        self.presentation = presentation
        self.size = size
    }

    public var body: some View {
        switch presentation.kind {
        case .window:
            if let position = presentation.windowPosition {
                WindowLayoutGlyph(position: position, color: ActionKind.window.color)
                    .frame(width: size * 1.15, height: size * 0.78)
                    .frame(width: size * 1.15, height: size)
            }
        case .app, .appGroup, .folder:
            AppIconStack(icons: presentation.icons, size: size)
        case .quicklink:
            if presentation.icons.isEmpty {
                IconTile(symbol: presentation.symbol, color: presentation.kind.color, size: size)
            } else {
                AppIconStack(icons: presentation.icons, size: size)
            }
        case .appSearch, .appSwitcher, .emojiPicker, .snippets, .clipboardHistory, .killProcess, .menuSearch, .gifSearch, .emptyTrash, .system:
            IconTile(symbol: presentation.symbol, color: presentation.kind.color, size: size)
        case .menu:
            ZStack(alignment: .bottomTrailing) {
                if let icon = presentation.icons.first {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                } else {
                    IconTile(symbol: ActionKind.menu.symbol, color: ActionKind.menu.color, size: size)
                }
                Image(systemName: "filemenu.and.selection")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
                    .background(ActionKind.menu.color, in: .circle)
                    .offset(x: size * 0.12, y: size * 0.08)
            }
        }
    }
}

/// Overlapping app icons (up to three).
public struct AppIconStack: View {
    let icons: [NSImage]
    var size: CGFloat

    public init(icons: [NSImage], size: CGFloat) {
        self.icons = icons
        self.size = size
    }

    public var body: some View {
        let shown = Array(icons.prefix(3))
        let iconSize = shown.count > 1 ? size * 0.78 : size
        let step = iconSize * 0.42

        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, icon in
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .offset(x: CGFloat(index) * step)
            }
        }
        .frame(width: iconSize + step * CGFloat(max(shown.count - 1, 0)), height: size, alignment: .leading)
    }
}
