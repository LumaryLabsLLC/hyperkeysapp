import EventEngine
import KeyBindings
import KeyboardUI
import Permissions
import SwiftUI

public struct ContentView: View {
    let bindingStore: BindingStore
    let permissionManager: PermissionManager
    var onHyperKeyChanged: ((KeyCode) -> Void)?

    public init(bindingStore: BindingStore, permissionManager: PermissionManager, onHyperKeyChanged: ((KeyCode) -> Void)? = nil) {
        self.bindingStore = bindingStore
        self.permissionManager = permissionManager
        self.onHyperKeyChanged = onHyperKeyChanged
    }

    public var body: some View {
        if !permissionManager.shouldShowMainUI {
            OnboardingView(permissionManager: permissionManager)
        } else {
            SettingsContentView(
                bindingStore: bindingStore,
                permissionManager: permissionManager,
                onHyperKeyChanged: onHyperKeyChanged
            )
        }
    }
}

struct SettingsContentView: View {
    @Bindable var bindingStore: BindingStore
    let permissionManager: PermissionManager
    var onHyperKeyChanged: ((KeyCode) -> Void)?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Keyboard", systemImage: "keyboard", value: 0) {
                KeyboardView(bindingStore: bindingStore, keySize: 52)
            }
            Tab("Profiles", systemImage: "person.2", value: 1) {
                ProfilesView(bindingStore: bindingStore)
            }
            Tab("Settings", systemImage: "gear", value: 2) {
                GeneralSettingsView(
                    permissionManager: permissionManager,
                    bindingStore: bindingStore,
                    onHyperKeyChanged: onHyperKeyChanged
                )
            }
        }
        .frame(width: 786, height: 325)
    }
}
