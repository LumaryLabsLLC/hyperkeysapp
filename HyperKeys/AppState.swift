import AppSwitcher
import ContextEngine
import EventEngine
import HyperKeysFeature
import KeyBindings
import Observation
import Permissions
import Shared
import SwiftUI

extension Notification.Name {
    static let toggleSettingsWindow = Notification.Name("HyperKeys.toggleSettingsWindow")
}

@MainActor
@Observable
public final class AppState {
    let permissionManager = PermissionManager()
    let bindingStore = BindingStore()
    let frontmostAppObserver = FrontmostAppObserver()

    /// Stored by the view layer so we can open the settings window programmatically.
    static var openSettingsWindow: (() -> Void)?

    private var eventTapManager: EventTapManager?
    private var actionExecutor: ActionExecutor?

    private var retryTask: Task<Void, Never>?

    public init() {
        // Deferred to next run loop so all properties are initialized
        Task { @MainActor in
            self.startEventTap()
        }
    }

    func startEventTap() {
        NSLog("[HyperKeys] startEventTap called. shouldShowMainUI=\(permissionManager.shouldShowMainUI) allPerms=\(permissionManager.allPermissionsGranted) skipped=\(permissionManager.onboardingSkipped)")
        guard permissionManager.shouldShowMainUI else {
            NSLog("[HyperKeys] Skipping event tap — UI not ready")
            return
        }
        guard eventTapManager == nil else {
            NSLog("[HyperKeys] Event tap already running")
            return
        }

        let executor = ActionExecutor(bindingStore: bindingStore)
        actionExecutor = executor

        let manager = EventTapManager()
        manager.engine.hyperKeyCode = bindingStore.hyperKeyCode.rawValue
        manager.engine.onHyperKeyActivated = { [weak executor] keyCode in
            Task { @MainActor in
                executor?.execute(keyCode: keyCode)
            }
        }
        manager.engine.onDoubleTap = {
            Task { @MainActor in
                NotificationCenter.default.post(name: .toggleSettingsWindow, object: nil)
            }
        }
        manager.start()
        eventTapManager = manager

        if manager.needsPermission {
            // Retry every 2 seconds until permission is granted
            retryTask?.cancel()
            retryTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, let mgr = self.eventTapManager, mgr.needsPermission else { break }
                    mgr.start()
                    if !mgr.needsPermission {
                        NSLog("[HyperKeys] Event tap retry succeeded!")
                        break
                    }
                }
            }
        }
        NSLog("[HyperKeys] Event tap started. Hyper key=\(bindingStore.hyperKeyCode.rawValue) bindings=\(bindingStore.bindings.count)")
    }

    func stopEventTap() {
        eventTapManager?.stop()
        eventTapManager = nil
    }

    func updateHyperKey(_ keyCode: KeyCode) {
        bindingStore.setHyperKey(keyCode)
        eventTapManager?.engine.hyperKeyCode = keyCode.rawValue
    }

}
