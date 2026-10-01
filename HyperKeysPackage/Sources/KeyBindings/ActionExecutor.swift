import AppKit
import AppSwitcher
import ContextEngine
import EventEngine
import Shared
import WindowEngine

private func actionLog(_ message: String) {
    let path = "/tmp/hyperkeys.log"
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "\(ts) [Action] \(message)\n"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

@MainActor
public final class ActionExecutor {
    private let bindingStore: BindingStore
    /// Shows the App Search launcher; provided by the app layer.
    public var onShowAppSearch: (() -> Void)?
    /// Shows the App Switcher grid; provided by the app layer.
    public var onShowAppSwitcher: (() -> Void)?
    /// Shows the Emoji & Symbols picker; provided by the app layer.
    public var onShowEmojiPicker: (() -> Void)?
    /// Shows the Snippets panel; provided by the app layer.
    public var onShowSnippets: (() -> Void)?
    /// Shows Clipboard History; provided by the app layer.
    public var onShowClipboardHistory: (() -> Void)?
    /// Shows the process list; provided by the app layer.
    public var onShowKillProcess: (() -> Void)?
    /// Shows Search Menu Items; provided by the app layer.
    public var onShowMenuSearch: (() -> Void)?
    /// Opens a quicklink by name (asking for any arguments); provided by the app layer.
    public var onOpenQuicklink: ((String) -> Void)?

    public init(bindingStore: BindingStore) {
        self.bindingStore = bindingStore
    }

    public func execute(keyCode: KeyCode) {
        actionLog("execute keyCode=\(keyCode.rawValue) (\(keyCode.displayLabel))")
        guard let binding = bindingStore.binding(for: keyCode) else {
            actionLog("No binding for Hyper+\(keyCode.displayLabel). Active bindings count=\(bindingStore.activeBindings.count)")
            return
        }
        perform(binding.action)
    }

    /// Runs an action directly — from a regular shortcut or a deeplink.
    public func perform(_ action: BoundAction) {
        switch action {
        case .launchApp(let bundleId, let appName):
            actionLog("Toggling \(appName) (\(bundleId))")
            AppLauncher.toggleApp(bundleIdentifier: bundleId)

        case .triggerMenuItem(let appBundleId, let menuPath):
            actionLog("Triggering menu: \(menuPath.joined(separator: " > "))")
            triggerMenuItem(appBundleId: appBundleId, menuPath: menuPath)

        case .showAppGroup(let groupId):
            if let group = AppGroupStore.shared.group(id: groupId) {
                actionLog("Toggling group: \(group.name) (\(group.appBundleIdentifiers.count) apps)")
                AppGroupManager.activate(group: group)
            }

        case .windowAction(let position):
            actionLog("Window action: \(position.displayName)")
            WindowManager.moveWindow(to: position)

        case .appSearch:
            actionLog("Showing App Search")
            onShowAppSearch?()

        case .appSwitcher:
            actionLog("Showing App Switcher")
            onShowAppSwitcher?()

        case .emojiPicker:
            actionLog("Showing Emoji & Symbols")
            onShowEmojiPicker?()

        case .openFolder(let path):
            actionLog("Opening folder \(path)")
            SystemCommands.open(path: path)

        case .emptyTrash:
            actionLog("Empty Trash")
            SystemCommands.emptyTrash()

        case .snippets:
            actionLog("Showing Snippets")
            onShowSnippets?()

        case .clipboardHistory:
            actionLog("Showing Clipboard History")
            onShowClipboardHistory?()

        case .killProcess:
            actionLog("Showing Kill Process")
            onShowKillProcess?()

        case .menuSearch:
            actionLog("Showing Search Menu Items")
            onShowMenuSearch?()

        case .quicklink(let name):
            actionLog("Opening quicklink \(name)")
            onOpenQuicklink?(name)

        case .system(let action):
            actionLog("System: \(action.title)")
            SystemCommands.run(action)

        case .none:
            break
        }
    }

    private func triggerMenuItem(appBundleId: String, menuPath: [String]) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleId).first {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let _ = MenuBarReader.triggerMenuItem(forPID: app.processIdentifier, path: menuPath)
            }
        }
    }
}
