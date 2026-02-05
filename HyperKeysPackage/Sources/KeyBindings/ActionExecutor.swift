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

    public init(bindingStore: BindingStore) {
        self.bindingStore = bindingStore
    }

    private func loadAppGroups() -> [AppGroup] {
        (try? Persistence.load([AppGroup].self, from: "appGroups.json")) ?? []
    }

    public func execute(keyCode: KeyCode) {
        actionLog("execute keyCode=\(keyCode.rawValue) (\(keyCode.displayLabel))")
        guard let binding = bindingStore.binding(for: keyCode) else {
            actionLog("No binding for Hyper+\(keyCode.displayLabel). Active bindings count=\(bindingStore.activeBindings.count)")
            return
        }

        switch binding.action {
        case .launchApp(let bundleId, let appName):
            actionLog("Toggling \(appName) (\(bundleId))")
            AppLauncher.toggleApp(bundleIdentifier: bundleId)

        case .triggerMenuItem(let appBundleId, let menuPath):
            actionLog("Triggering menu: \(menuPath.joined(separator: " > "))")
            triggerMenuItem(appBundleId: appBundleId, menuPath: menuPath)

        case .showAppGroup(let groupId):
            if let group = loadAppGroups().first(where: { $0.id == groupId }) {
                actionLog("Toggling group: \(group.name) (\(group.appBundleIdentifiers.count) apps)")
                AppGroupManager.activate(group: group)
            }

        case .windowAction(let position):
            actionLog("Window action: \(position.displayName)")
            WindowManager.moveWindow(to: position)

        case .none:
            break
        }
    }

    private func triggerMenuItem(appBundleId: String, menuPath: [String]) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleId).first {
            app.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let _ = MenuBarReader.triggerMenuItem(forPID: app.processIdentifier, path: menuPath)
            }
        }
    }
}
