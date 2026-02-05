import AppKit
import AppSwitcher
import ContextEngine
import EventEngine
import KeyBindings
import Shared
import SwiftUI
import WindowEngine

public struct BindingPopover: View {
    let keyCode: KeyCode
    @Bindable var bindingStore: BindingStore
    let onDismiss: () -> Void

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var installedApps = InstalledAppProvider()

    // Multi-select state for app picker
    @State private var selectedApps: [AppInfo] = []
    @State private var showingGroupName = false
    @State private var groupName = ""

    // Menu item picker state
    @State private var menuTargetBundleId: String?
    @State private var menuTargetName = ""
    @State private var menuTargetPid: pid_t = 0
    @State private var menuTopLevel: [MenuItemInfo] = []
    @State private var menuNavStack: [[MenuItemInfo]] = []
    @State private var menuNavTitles: [String] = []

    public init(keyCode: KeyCode, bindingStore: BindingStore, onDismiss: @escaping () -> Void) {
        self.keyCode = keyCode
        self.bindingStore = bindingStore
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            tabContent
        }
        .frame(width: 400, height: 450)
        .task {
            installedApps.scan()
            // Pre-select apps if already bound to a group
            if case .showAppGroup(let groupId) = currentBinding?.action {
                let groups = (try? Persistence.load([AppGroup].self, from: "appGroups.json")) ?? []
                if let group = groups.first(where: { $0.id == groupId }) {
                    selectedApps = installedApps.apps.filter { group.appBundleIdentifiers.contains($0.bundleIdentifier) }
                    groupName = group.name
                }
            }
            // Pre-select if bound to a single app
            if case .launchApp(let bundleId, _) = currentBinding?.action {
                if let app = installedApps.apps.first(where: { $0.bundleIdentifier == bundleId }) {
                    selectedApps = [app]
                }
            }
        }
        .alert("Name this group", isPresented: $showingGroupName) {
            TextField("e.g. Work, Music, Design", text: $groupName)
            Button("Save") { saveGroup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedApps.count) apps selected. Give this group a name.")
        }
    }

    private var currentBinding: KeyBinding? {
        bindingStore.binding(for: keyCode)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hyper + \(keyCode.displayLabel)")
                    .font(.headline)
                Spacer()
                Button("Done") { handleDone() }
                    .keyboardShortcut(.cancelAction)
            }

            if let binding = currentBinding {
                HStack {
                    Label(actionDescription(binding.action), systemImage: actionIcon(binding.action))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        if let groupId = bindingStore.activeGroupId {
                            bindingStore.removeBindingInGroup(groupId: groupId, keyCode: keyCode)
                        } else {
                            bindingStore.removeBinding(for: keyCode)
                        }
                        selectedApps = []
                        groupName = ""
                    } label: {
                        Label("Remove Shortcut", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Apps").tag(0)
            Text("Window").tag(1)
            Text("Menu Item").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: appPicker
        case 1: windowPicker
        case 2: menuItemPicker
        default: EmptyView()
        }
    }

    // MARK: - App Picker (multi-select)

    private var appPicker: some View {
        VStack(spacing: 0) {
            // Selected apps chips
            if !selectedApps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedApps) { app in
                            HStack(spacing: 4) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                Text(app.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Button {
                                    toggleAppSelection(app)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 8)

            List(filteredApps) { app in
                let isSelected = selectedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier })
                Button {
                    toggleAppSelection(app)
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        Text(app.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            // Bottom bar: selection count + bind button
            if !selectedApps.isEmpty {
                Divider()
                HStack {
                    if selectedApps.count == 1 {
                        Text(selectedApps[0].name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(selectedApps.count) apps selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Bind") {
                        bindSelectedApps()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func handleDone() {
        // If user had a binding but deselected all apps, remove the binding
        if currentBinding != nil && selectedApps.isEmpty {
            if let groupId = bindingStore.activeGroupId {
                bindingStore.removeBindingInGroup(groupId: groupId, keyCode: keyCode)
            } else {
                bindingStore.removeBinding(for: keyCode)
            }
        }
        onDismiss()
    }

    private func toggleAppSelection(_ app: AppInfo) {
        if let idx = selectedApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            selectedApps.remove(at: idx)
        } else {
            selectedApps.append(app)
        }
    }

    private func bindSelectedApps() {
        if selectedApps.count == 1 {
            // Single app → direct binding
            let app = selectedApps[0]
            let binding = KeyBinding(
                keyCode: keyCode,
                action: .launchApp(bundleId: app.bundleIdentifier, appName: app.name)
            )
            if let groupId = bindingStore.activeGroupId {
                bindingStore.setBindingInGroup(groupId: groupId, binding: binding)
            } else {
                bindingStore.setBinding(binding)
            }
            onDismiss()
        } else {
            // Multiple apps → prompt for group name
            if groupName.isEmpty {
                showingGroupName = true
            } else {
                saveGroup()
            }
        }
    }

    private func saveGroup() {
        let name = groupName.isEmpty ? "Group" : groupName
        var groups = (try? Persistence.load([AppGroup].self, from: "appGroups.json")) ?? []

        // Check if we're updating an existing group
        var group: AppGroup
        if case .showAppGroup(let existingId) = currentBinding?.action,
           let idx = groups.firstIndex(where: { $0.id == existingId }) {
            groups[idx].name = name
            groups[idx].appBundleIdentifiers = selectedApps.map(\.bundleIdentifier)
            group = groups[idx]
        } else {
            group = AppGroup(name: name, appBundleIdentifiers: selectedApps.map(\.bundleIdentifier))
            groups.append(group)
        }
        try? Persistence.save(groups, to: "appGroups.json")

        let binding = KeyBinding(keyCode: keyCode, action: .showAppGroup(groupId: group.id))
        if let activeGroupId = bindingStore.activeGroupId {
            bindingStore.setBindingInGroup(groupId: activeGroupId, binding: binding)
        } else {
            bindingStore.setBinding(binding)
        }
        onDismiss()
    }

    // MARK: - Window Picker

    private var windowPicker: some View {
        List(WindowPosition.allCases, id: \.self) { position in
            Button {
                let binding = KeyBinding(keyCode: keyCode, action: .windowAction(position))
                if let groupId = bindingStore.activeGroupId {
                    bindingStore.setBindingInGroup(groupId: groupId, binding: binding)
                } else {
                    bindingStore.setBinding(binding)
                }
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: iconName(for: position))
                    Text(position.displayName)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Menu Item (placeholder)

    private var menuItemPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "menubar.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Menu Item Binding")
                .font(.headline)
            Text("Select the frontmost app's menu item to trigger.\nActivate the target app first, then click here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return installedApps.apps }
        return installedApps.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func actionDescription(_ action: BoundAction) -> String {
        switch action {
        case .launchApp(_, let name): return name
        case .triggerMenuItem(_, let path): return path.joined(separator: " > ")
        case .showAppGroup(let groupId):
            let groups = (try? Persistence.load([AppGroup].self, from: "appGroups.json")) ?? []
            if let group = groups.first(where: { $0.id == groupId }) {
                return "\(group.name) (\(group.appBundleIdentifiers.count) apps)"
            }
            return "App Group"
        case .windowAction(let pos): return pos.displayName
        case .none: return "None"
        }
    }

    private func actionIcon(_ action: BoundAction) -> String {
        switch action {
        case .launchApp: "app"
        case .triggerMenuItem: "filemenu.and.selection"
        case .showAppGroup: "square.grid.2x2"
        case .windowAction: "macwindow"
        case .none: "circle.slash"
        }
    }

    private func iconName(for position: WindowPosition) -> String {
        switch position {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeftQuarter: "rectangle.topthird.inset.filled"
        case .topRightQuarter: "rectangle.topthird.inset.filled"
        case .bottomLeftQuarter: "rectangle.bottomthird.inset.filled"
        case .bottomRightQuarter: "rectangle.bottomthird.inset.filled"
        case .fullScreen: "rectangle.fill"
        case .center: "rectangle.center.inset.filled"
        case .nextScreen: "rectangle.righthalf.inset.arrow.right"
        case .previousScreen: "rectangle.lefthalf.inset.arrow.left"
        }
    }
}
