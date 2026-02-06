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

    // Window positions for app groups
    @State private var appWindowPositions: [String: WindowPosition] = [:]

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
        .frame(width: 400, height: 480)
        .task {
            installedApps.scan()
            // Pre-select apps if already bound to a group
            if case .showAppGroup(let groupId) = currentBinding?.action {
                let groups = (try? Persistence.load([AppGroup].self, from: "appGroups.json")) ?? []
                if let group = groups.first(where: { $0.id == groupId }) {
                    selectedApps = installedApps.apps.filter { group.appBundleIdentifiers.contains($0.bundleIdentifier) }
                    groupName = group.name
                    appWindowPositions = group.windowPositions
                }
            }
            // Pre-select if bound to a single app
            if case .launchApp(let bundleId, _) = currentBinding?.action {
                if let app = installedApps.apps.first(where: { $0.bundleIdentifier == bundleId }) {
                    selectedApps = [app]
                }
            }
            // Pre-populate menu item target
            if case .triggerMenuItem(let appBundleId, _) = currentBinding?.action {
                menuTargetBundleId = appBundleId
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == appBundleId }) {
                    menuTargetName = app.localizedName ?? appBundleId
                    menuTargetPid = app.processIdentifier
                    menuTopLevel = MenuBarReader.readMenuItems(forPID: app.processIdentifier)
                } else {
                    menuTargetName = appBundleId
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
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)

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

            // Bottom bar
            if !selectedApps.isEmpty {
                Divider()
                VStack(spacing: 4) {
                    ForEach(selectedApps) { app in
                        HStack(spacing: 6) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                            }
                            Text(app.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Picker("", selection: windowPositionBinding(for: app.bundleIdentifier)) {
                                Text("No Position").tag(nil as WindowPosition?)
                                Divider()
                                ForEach(tilePositions, id: \.self) { pos in
                                    Text(pos.displayName).tag(pos as WindowPosition?)
                                }
                            }
                            .fixedSize()
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Bind") {
                            bindSelectedApps()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func handleDone() {
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
        if selectedApps.count == 1 && appWindowPositions[selectedApps[0].bundleIdentifier] == nil {
            // Single app, no position → direct binding
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
        } else if selectedApps.count == 1 {
            // Single app with position → auto-create 1-app group
            groupName = selectedApps[0].name
            saveGroup()
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

        var group: AppGroup
        if case .showAppGroup(let existingId) = currentBinding?.action,
           let idx = groups.firstIndex(where: { $0.id == existingId }) {
            groups[idx].name = name
            groups[idx].appBundleIdentifiers = selectedApps.map(\.bundleIdentifier)
            groups[idx].windowPositions = appWindowPositions
            group = groups[idx]
        } else {
            group = AppGroup(name: name, appBundleIdentifiers: selectedApps.map(\.bundleIdentifier), windowPositions: appWindowPositions)
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

    // MARK: - Window Picker (Visual Grid)

    private var currentWindowPosition: WindowPosition? {
        if case .windowAction(let pos) = currentBinding?.action {
            return pos
        }
        return nil
    }

    private var windowPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(WindowPositionCategory.allCases, id: \.self) { category in
                    let positions = WindowPosition.allCases.filter { $0.category == category }
                    if !positions.isEmpty {
                        WindowPositionCategoryGrid(
                            category: category,
                            positions: positions,
                            selected: currentWindowPosition
                        ) { position in
                            let binding = KeyBinding(keyCode: keyCode, action: .windowAction(position))
                            if let groupId = bindingStore.activeGroupId {
                                bindingStore.setBindingInGroup(groupId: groupId, binding: binding)
                            } else {
                                bindingStore.setBinding(binding)
                            }
                            onDismiss()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Menu Item Picker

    private var menuItemPicker: some View {
        VStack(spacing: 0) {
            if menuTargetBundleId != nil {
                menuBrowser
            } else {
                runningAppPicker
            }
        }
    }

    private var runningAppPicker: some View {
        VStack(spacing: 0) {
            Text("Select a running app to browse its menus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            List {
                ForEach(runningAppsForMenu, id: \.processIdentifier) { app in
                    Button {
                        selectMenuApp(app)
                    } label: {
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var runningAppsForMenu: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
            }
    }

    private func selectMenuApp(_ app: NSRunningApplication) {
        menuTargetBundleId = app.bundleIdentifier
        menuTargetName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        menuTargetPid = app.processIdentifier
        menuTopLevel = MenuBarReader.readMenuItems(forPID: app.processIdentifier)
        menuNavStack = []
        menuNavTitles = []
    }

    private var menuBrowser: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if menuNavStack.isEmpty {
                        menuTargetBundleId = nil
                        menuTopLevel = []
                    } else {
                        menuNavStack.removeLast()
                        menuNavTitles.removeLast()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(menuNavTitles.last ?? menuTargetName)
                            .lineLimit(1)
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            let currentItems = menuNavStack.last ?? menuTopLevel

            if currentItems.isEmpty {
                VStack {
                    Spacer()
                    Text("No menu items found")
                        .foregroundStyle(.secondary)
                    Text("Make sure the app is running and in the foreground.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(currentItems, id: \.path) { item in
                        Button {
                            if item.children.isEmpty {
                                bindMenuItem(item)
                            } else {
                                menuNavStack.append(item.children)
                                menuNavTitles.append(item.title)
                            }
                        } label: {
                            HStack {
                                Text(item.title)
                                    .foregroundStyle(item.isEnabled ? .primary : .secondary)
                                Spacer()
                                if !item.children.isEmpty {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.isEnabled && item.children.isEmpty)
                    }
                }
            }
        }
    }

    private func bindMenuItem(_ item: MenuItemInfo) {
        guard let bundleId = menuTargetBundleId else { return }
        let binding = KeyBinding(
            keyCode: keyCode,
            action: .triggerMenuItem(appBundleId: bundleId, menuPath: item.path)
        )
        if let groupId = bindingStore.activeGroupId {
            bindingStore.setBindingInGroup(groupId: groupId, binding: binding)
        } else {
            bindingStore.setBinding(binding)
        }
        onDismiss()
    }

    // MARK: - Helpers

    private func windowPositionBinding(for bundleId: String) -> Binding<WindowPosition?> {
        Binding(
            get: { appWindowPositions[bundleId] },
            set: {
                if let value = $0 {
                    appWindowPositions[bundleId] = value
                } else {
                    appWindowPositions.removeValue(forKey: bundleId)
                }
            }
        )
    }

    private var tilePositions: [WindowPosition] {
        WindowPosition.allCases
    }

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
}

// MARK: - Visual Grid Components

private struct WindowPositionTile: View {
    let position: WindowPosition
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private let tileWidth: CGFloat = 50
    private let tileHeight: CGFloat = 34

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    // Screen background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: tileWidth, height: tileHeight)

                    if let rect = position.normalizedRect {
                        // Highlighted area
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.5)))
                            .frame(
                                width: max(rect.width * tileWidth - 2, 4),
                                height: max(rect.height * tileHeight - 2, 4)
                            )
                            .offset(
                                x: (rect.origin.x - 0.5 + rect.width / 2) * tileWidth,
                                y: (rect.origin.y - 0.5 + rect.height / 2) * tileHeight
                            )
                    }

                    // Border
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.4) : .clear), lineWidth: 1.5)
                        .frame(width: tileWidth, height: tileHeight)
                }

                Text(position.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: tileWidth + 12)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct WindowPositionCategoryGrid: View {
    let category: WindowPositionCategory
    let positions: [WindowPosition]
    let selected: WindowPosition?
    let onSelect: (WindowPosition) -> Void

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fontWeight(.semibold)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(positions, id: \.self) { position in
                    WindowPositionTile(
                        position: position,
                        isSelected: selected == position
                    ) {
                        onSelect(position)
                    }
                }
            }
        }
    }
}
