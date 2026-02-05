import HyperKeysFeature
import Permissions
import SwiftUI

@main
struct HyperKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("HyperKeys", systemImage: "keyboard.fill") {
            MenuBarMenu(appState: appState)
        }
        .menuBarExtraStyle(.menu)

        Window("HyperKeys Settings", id: "settings") {
            ContentView(
                bindingStore: appState.bindingStore,
                permissionManager: appState.permissionManager,
                onHyperKeyChanged: { appState.updateHyperKey($0) }
            )
            .onChange(of: appState.permissionManager.shouldShowMainUI) { _, show in
                if show {
                    appState.startEventTap()
                }
            }
        }
        .defaultSize(width: 850, height: 500)
    }
}

struct MenuBarMenu: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if appState.permissionManager.allPermissionsGranted {
            Button("Hyper Key: Active") {}
                .disabled(true)
        } else {
            Button("Hyper Key: Permissions Required") {}
                .disabled(true)
        }

        Divider()

        if !appState.bindingStore.actionGroups.isEmpty {
            Menu("Profile") {
                Button {
                    appState.bindingStore.setActiveGroup(nil)
                } label: {
                    HStack {
                        Text("Default")
                        if appState.bindingStore.activeGroupId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(appState.bindingStore.actionGroups) { group in
                    Button {
                        appState.bindingStore.setActiveGroup(group.id)
                    } label: {
                        HStack {
                            Text(group.name)
                            if appState.bindingStore.activeGroupId == group.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
        }

        Button("Open Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit HyperKeys") {
            appState.stopEventTap()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
