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
    static let mainWindowID = "hyperkeys-main"

    let permissionManager = PermissionManager()
    let bindingStore = BindingStore()
    let status = HyperKeyStatus()

    /// Open the window automatically only on first launch or when setup is incomplete,
    /// so launching at login stays quiet.
    let shouldOpenWindowAtLaunch: Bool

    /// Stored by the view layer so we can open the main window programmatically.
    static var openMainWindow: (() -> Void)?

    private var eventTapManager: EventTapManager?
    private var actionExecutor: ActionExecutor?

    private var retryTask: Task<Void, Never>?

    public init() {
        let defaults = UserDefaults.standard
        shouldOpenWindowAtLaunch = !defaults.bool(forKey: Preferences.hasLaunchedBefore) || !permissionManager.allPermissionsGranted
        defaults.set(true, forKey: Preferences.hasLaunchedBefore)

        // config.json is the source of truth; start following it before anything else changes settings.
        ConfigStore.shared.onHyperKeyChanged = { [weak self] in self?.updateHyperKey($0) }
        ConfigStore.shared.start(bindingStore: bindingStore)
        actionExecutor = makeExecutor()
        GlobalShortcutStore.shared.onUpdate = { [weak self] in self?.registerGlobalShortcuts() }
        if let combo = ClipboardHistoryStore.shared.takeLegacyHotKey(),
           GlobalShortcutStore.shared.shortcut(for: .clipboardHistory) == nil {
            GlobalShortcutStore.shared.set(combo, for: .clipboardHistory)
        }
        registerGlobalShortcuts()

        AppSearchController.shared.bindingStore = bindingStore
        AppSearchController.shared.status = status
        AppSearchController.shared.onSetPaused = { [weak self] in self?.setPaused($0) }
        AppSearchController.shared.perform = { [weak self] in self?.actionExecutor?.perform($0) }
        DeeplinkRouter.shared.bindingStore = bindingStore
        DeeplinkRouter.shared.perform = { [weak self] in self?.performFromShortcut($0) }
        DeeplinkRouter.shared.setPaused = { [weak self] in self?.setPaused($0) }
        AppSwitcherController.shared.isHyperKeyDown = { [status] in status.isHyperKeyDown }
        // A keyboard Hyper key includes Shift, so Shift can't mean "go backwards" there.
        AppSwitcherController.shared.reversesWithShift = { [bindingStore] in bindingStore.hyperKeyCode != .modifierHyper }
        seedAppSearchShortcut()
        seedAppSwitcherShortcut()

        // Deferred to next run loop so all properties are initialized
        Task { @MainActor in
            self.startEventTap()
            AppSearchController.shared.warmUp()
            AppSwitcherController.shared.warmUp()
            EmojiPickerController.shared.warmUp()
            SnippetsPanelController.shared.warmUp()
            ClipboardHistoryPanelController.shared.warmUp()
            KillProcessController.shared.warmUp()
            MenuSearchController.shared.warmUp()
            GifSearchController.shared.warmUp()
            ClipboardMonitor.shared.start()
            GlobalHotKeys.shared.isPaused = self.status.isPaused
        }
    }

    func startEventTap() {
        NSLog("[HyperKeys] startEventTap called. shouldShowMainUI=\(permissionManager.shouldShowMainUI) allPerms=\(permissionManager.allPermissionsGranted) skipped=\(permissionManager.onboardingSkipped)")
        guard permissionManager.shouldShowMainUI else {
            NSLog("[HyperKeys] Skipping event tap — UI not ready")
            return
        }
        guard !status.isPaused else {
            NSLog("[HyperKeys] Skipping event tap — paused")
            return
        }
        guard eventTapManager == nil else {
            NSLog("[HyperKeys] Event tap already running")
            return
        }

        let executor = actionExecutor ?? makeExecutor()
        actionExecutor = executor

        let manager = EventTapManager()
        manager.onKeyTyped = { key in
            MainActor.assumeIsolated { KeywordExpander.shared.handle(key) }
        }

        // Caps Lock is remapped to F18 via hidutil at the IOKit level,
        // so the engine listens for F18 while the UI shows Caps Lock.
        let hyperKey = bindingStore.hyperKeyCode
        if hyperKey == .capsLock {
            CapsLockRemapper.enable()
            manager.engine.hyperKeyCode = KeyCode.f18.rawValue
            manager.engine.logicalHyperKey = .capsLock
        } else {
            CapsLockRemapper.disable()
            manager.engine.hyperKeyCode = hyperKey.rawValue
            manager.engine.logicalHyperKey = hyperKey
        }
        let status = status
        let bindingStore = bindingStore
        // The tap runs on the main run loop, so these callbacks are already on the main thread.
        // State is updated synchronously so a quick Hyper+Tab tap can't see its release
        // before the switch it started; actions run afterwards so they never stall the tap.
        manager.engine.onHyperKeyActivated = { [weak executor] keyCode in
            MainActor.assumeIsolated {
                status.recordTrigger(keyCode)
                let switcherKey = bindingStore.keyCode(for: .appSwitcher)
                if AppSwitcherController.shared.handleHeldKey(keyCode, switcherKey: switcherKey) {
                    return
                }
                Task { @MainActor in
                    executor?.execute(keyCode: keyCode)
                }
            }
        }
        // Keyboard-Hyper (⌃⌥⇧⌘) mode: only take combos HyperKeys actually uses,
        // so other apps' ⌃⌥⇧⌘ shortcuts keep working.
        manager.engine.shouldHandleModifierCombo = { key in
            MainActor.assumeIsolated {
                AppSwitcherController.shared.isCapturingHyperKeys || bindingStore.binding(for: key) != nil
            }
        }
        manager.engine.onHyperKeyRepeat = { keyCode in
            MainActor.assumeIsolated {
                AppSwitcherController.shared.handleRepeat(keyCode, switcherKey: bindingStore.keyCode(for: .appSwitcher))
            }
        }
        manager.engine.onHyperKeyStateChanged = { isDown in
            MainActor.assumeIsolated {
                status.isHyperKeyDown = isDown
                if !isDown {
                    AppSwitcherController.shared.hyperKeyReleased()
                }
            }
        }
        manager.engine.onDoubleTap = {
            Task { @MainActor in
                guard Preferences.isDoubleTapEnabled else { return }
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

    /// Offers Hyper + Space for App Search once, if that key is still free.
    private func seedAppSearchShortcut() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Preferences.didSeedAppSearch) else { return }
        defaults.set(true, forKey: Preferences.didSeedAppSearch)

        seedDefault(.appSearch, on: .space)
    }

    /// Offers Hyper + Tab for the App Switcher once, if that key is still free.
    private func seedAppSwitcherShortcut() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Preferences.didSeedAppSwitcher) else { return }
        defaults.set(true, forKey: Preferences.didSeedAppSwitcher)
        seedDefault(.appSwitcher, on: .tab)
    }

    private func seedDefault(_ action: BoundAction, on key: KeyCode) {
        let keyIsFree = !bindingStore.bindings.contains { $0.keyCode == key }
        let alreadyBound = bindingStore.bindings.contains { $0.action == action }
        if keyIsFree, !alreadyBound, bindingStore.hyperKeyCode != key {
            bindingStore.setBinding(KeyBinding(keyCode: key, action: action))
        }
    }

    private func makeExecutor() -> ActionExecutor {
        let executor = ActionExecutor(bindingStore: bindingStore)
        executor.onShowAppSearch = { AppSearchController.shared.toggle() }
        executor.onShowAppSwitcher = { AppSwitcherController.shared.shortcutPressed() }
        executor.onShowEmojiPicker = { EmojiPickerController.shared.toggle() }
        executor.onShowSnippets = { SnippetsPanelController.shared.toggle() }
        executor.onShowClipboardHistory = { ClipboardHistoryPanelController.shared.toggle() }
        executor.onShowKillProcess = { KillProcessController.shared.toggle() }
        executor.onShowMenuSearch = { MenuSearchController.shared.toggle() }
        executor.onShowGifSearch = { GifSearchController.shared.toggle() }
        executor.onOpenQuicklink = { QuicklinkRunner.open(named: $0) }
        return executor
    }

    // MARK: - Regular shortcuts

    /// Names registered with macOS, so removed shortcuts can be released.
    private var registeredShortcutNames: Set<String> = []

    /// Registers every regular shortcut (⌥Space, ⇧⌘V…) with macOS, releasing removed ones.
    private func registerGlobalShortcuts() {
        let shortcuts = GlobalShortcutStore.shared.shortcuts.filter(\.isEnabled)
        let names = Set(shortcuts.map { "shortcut-\($0.id.uuidString)" })
        for stale in registeredShortcutNames.subtracting(names) {
            GlobalHotKeys.shared.set(nil, for: stale) {}
        }
        for shortcut in shortcuts {
            let action = shortcut.action
            GlobalHotKeys.shared.set(shortcut.combo, for: "shortcut-\(shortcut.id.uuidString)") { [weak self] in
                self?.performFromShortcut(action)
            }
        }
        registeredShortcutNames = names
    }

    private func performFromShortcut(_ action: BoundAction) {
        if action == .appSwitcher {
            // Without Hyper held there's nothing to release, so open it to pick with the keyboard.
            AppSwitcherController.shared.show()
            return
        }
        actionExecutor?.perform(action)
    }

    func stopEventTap() {
        retryTask?.cancel()
        CapsLockRemapper.disable()
        eventTapManager?.stop()
        eventTapManager = nil
        status.isHyperKeyDown = false
    }

    /// Temporarily turns all shortcuts off (and restores the normal Caps Lock behavior).
    func setPaused(_ paused: Bool) {
        guard paused != status.isPaused else { return }
        status.isPaused = paused
        GlobalHotKeys.shared.isPaused = paused
        if paused {
            stopEventTap()
        } else {
            startEventTap()
        }
    }

    func updateHyperKey(_ keyCode: KeyCode) {
        bindingStore.setHyperKey(keyCode)
        eventTapManager?.engine.reset()
        if keyCode == .capsLock {
            CapsLockRemapper.enable()
            eventTapManager?.engine.hyperKeyCode = KeyCode.f18.rawValue
            eventTapManager?.engine.logicalHyperKey = .capsLock
        } else {
            CapsLockRemapper.disable()
            eventTapManager?.engine.hyperKeyCode = keyCode.rawValue
            eventTapManager?.engine.logicalHyperKey = keyCode
        }
    }

}
