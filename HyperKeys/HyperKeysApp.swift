import HyperKeysFeature
import KeyBindings
import Permissions
import SwiftUI

@main
struct HyperKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        Window("HyperKeys", id: AppState.mainWindowID) {
            ContentView(
                bindingStore: appState.bindingStore,
                permissionManager: appState.permissionManager,
                status: appState.status,
                onHyperKeyChanged: { appState.updateHyperKey($0) },
                onPauseChanged: { appState.setPaused($0) }
            )
            .onChange(of: appState.permissionManager.shouldShowMainUI) { _, show in
                if show {
                    appState.startEventTap()
                }
            }
            // Show in the Dock and app switcher only while the window is open.
            .onAppear { AppDelegate.setDockIconVisible(true) }
            .onDisappear { AppDelegate.setDockIconVisible(false) }
        }
        .defaultSize(width: ContentView.windowWidth, height: 760)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(appState.shouldOpenWindowAtLaunch ? .presented : .suppressed)

        MenuBarExtra {
            MenuBarMenu(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarLabel: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: iconState))
            .onAppear {
                let open = { [openWindow] in
                    openWindow(id: AppState.mainWindowID)
                    AppDelegate.bringMainWindowToFront()
                }
                AppState.openMainWindow = open
                HyperKeysWindow.open = open
            }
    }

    private var iconState: MenuBarIcon.State {
        if appState.status.isPaused || !appState.permissionManager.allPermissionsGranted {
            return .inactive
        }
        return appState.status.isHyperKeyDown ? .held : .active
    }
}

struct MenuBarMenu: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var bindingStore: BindingStore { appState.bindingStore }

    /// Kept short: App Search reaches every panel and command, so the menu only opens things
    /// and holds the switches you'd want at a glance.
    var body: some View {
        if !appState.permissionManager.allPermissionsGranted {
            Button("Grant Permissions…", action: openMainWindow)
            Divider()
        }

        Button("Open HyperKeys…", action: openMainWindow)
            .keyboardShortcut(",")
        Button("App Search…") {
            AppSearchController.shared.show()
        }

        Divider()

        if !bindingStore.actionGroups.isEmpty {
            Picker("Profile", selection: Binding(
                get: { bindingStore.activeGroupId },
                set: { bindingStore.setActiveGroup($0) }
            )) {
                Text("Default").tag(UUID?.none)
                ForEach(bindingStore.actionGroups) { group in
                    Text(group.name).tag(UUID?.some(group.id))
                }
            }
        }
        Toggle("Keep Mac Awake", isOn: Binding(
            get: { Caffeinate.shared.isActive },
            set: { $0 ? Caffeinate.shared.start() : Caffeinate.shared.stop() }
        ))
        Toggle("Pause Shortcuts", isOn: Binding(
            get: { appState.status.isPaused },
            set: { appState.setPaused($0) }
        ))

        Divider()

        Button("Quit HyperKeys") {
            appState.stopEventTap()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMainWindow() {
        openWindow(id: AppState.mainWindowID)
        AppDelegate.bringMainWindowToFront()
    }
}
