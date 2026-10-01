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

    var body: some View {
        Button(statusLine) {}
            .disabled(true)

        if !appState.permissionManager.allPermissionsGranted {
            Button("Grant Permissions…", action: openMainWindow)
        }

        if !bindingStore.actionGroups.isEmpty {
            Divider()
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

        Divider()

        Button(menuTitle("Search Apps…", for: .appSearch)) {
            AppSearchController.shared.show()
        }
        Button(menuTitle("Switch Apps…", for: .appSwitcher)) {
            AppSwitcherController.shared.show()
        }
        Button(menuTitle("Emoji & Symbols…", for: .emojiPicker)) {
            EmojiPickerController.shared.show()
        }
        Button(menuTitle("Snippets…", for: .snippets)) {
            SnippetsPanelController.shared.show()
        }

        Button("Open HyperKeys…", action: openMainWindow)
            .keyboardShortcut(",")

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

    private func menuTitle(_ title: String, for action: BoundAction) -> String {
        guard let key = bindingStore.keyCode(for: action) else { return title }
        return "\(title)  (Hyper + \(key.name))"
    }

    private var statusLine: String {
        if !appState.permissionManager.allPermissionsGranted { return "HyperKeys needs permissions" }
        if appState.status.isPaused { return "HyperKeys is paused" }
        return "Hold \(bindingStore.hyperKeyCode.name) + a key"
    }

    private func openMainWindow() {
        openWindow(id: AppState.mainWindowID)
        AppDelegate.bringMainWindowToFront()
    }
}
