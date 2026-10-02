import AppSwitcher
import KeyBindings
import Shared
import SwiftUI
import WindowEngine

/// Pick one app (one click assigns it), or switch on multi-select to open several apps at once,
/// optionally placing each app's window.
struct AppActionPicker: View {
    let currentAction: BoundAction?
    let onAssign: (BoundAction) -> Void

    @State private var provider = InstalledAppProvider.shared
    @State private var quicklinks = QuicklinkStore.shared
    @State private var query = ""
    @State private var runningApps: [AppInfo] = []
    @State private var isMultiSelect = false
    @State private var selection: [AppInfo] = []
    @State private var positions: [String: WindowPosition] = [:]
    @State private var groupName = ""
    @State private var existingGroupId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search apps", text: $query, onSubmit: submitTopResult)
                .padding(12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !isMultiSelect, query.isEmpty {
                        PickerSectionHeader(title: "Commands")
                        builtInRow(.appSearch, subtitle: "Search for any app and open it")
                        builtInRow(.appSwitcher, subtitle: "Switch between open apps and windows")
                        builtInRow(.emojiPicker, subtitle: "Search and paste emoji and symbols")
                        builtInRow(.snippets, subtitle: "Search and paste your snippets")
                        builtInRow(.clipboardHistory, subtitle: "Search and paste what you've copied")
                        builtInRow(.killProcess, subtitle: "Quit or force quit a running app or process")
                        builtInRow(.menuSearch, subtitle: "Find and run any menu command in the app you're in")
                        builtInRow(.gifSearch, subtitle: "Find a GIF on GIPHY or Klipy and copy it")
                        builtInRow(.emptyTrash, subtitle: "Empty the Trash (asks first)")
                        if !quicklinks.quicklinks.isEmpty {
                            PickerSectionHeader(title: "Quicklinks")
                            ForEach(quicklinks.quicklinks) { quicklink in
                                builtInRow(.quicklink(name: quicklink.name), subtitle: quicklink.displayLink)
                            }
                        }
                        PickerSectionHeader(title: "System")
                        ForEach(SystemAction.allCases, id: \.self) { action in
                            builtInRow(.system(action), subtitle: action.detail)
                        }
                    }
                    if query.isEmpty {
                        if !runningApps.isEmpty {
                            PickerSectionHeader(title: "Open Now")
                            ForEach(runningApps) { row(for: $0) }
                        }
                        PickerSectionHeader(title: "All Apps")
                        if provider.apps.isEmpty, provider.isLoading {
                            PickerMessage(symbol: "", title: "Finding apps…", isLoading: true)
                        }
                        ForEach(provider.apps) { row(for: $0) }
                    } else if searchResults.isEmpty {
                        PickerMessage(symbol: "magnifyingglass", title: "No apps match “\(query)”")
                    } else {
                        ForEach(searchResults) { row(for: $0) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Divider()
            footer
                .padding(12)
        }
        .onAppear(perform: load)
    }

    // MARK: - Rows

    /// Rows for HyperKeys' own tools (App Search, App Switcher).
    private func builtInRow(_ action: BoundAction, subtitle: String) -> some View {
        let isCurrent = currentAction == action
        let kind = ActionKind(action) ?? .app
        let presentation = BindingPresentation(action)
        return PickerRow(title: presentation?.title ?? kind.title, subtitle: subtitle, isSelected: isCurrent) {
            onAssign(action)
        } leading: {
            IconTile(symbol: presentation?.symbol ?? kind.symbol, color: kind.color, size: 24)
        } trailing: {
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func row(for app: AppInfo) -> some View {
        let isChecked = selection.contains { $0.bundleIdentifier == app.bundleIdentifier }
        let isCurrent = !isMultiSelect && isCurrentApp(app)

        return PickerRow(title: app.name, isSelected: isCurrent) {
            if isMultiSelect {
                toggle(app)
            } else {
                onAssign(.launchApp(bundleId: app.bundleIdentifier, appName: app.name))
            }
        } leading: {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
        } trailing: {
            if isMultiSelect {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            } else if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isMultiSelect, !selection.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(selection) { app in
                            selectedRow(app)
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(selection.count) * 30, 100))

                HStack(spacing: 8) {
                    TextField("Group name", text: $groupName, prompt: Text(defaultGroupName))
                        .textFieldStyle(.roundedBorder)
                    Button("Save", action: saveSelection)
                        .hkProminentButtonStyle()
                        .keyboardShortcut(.defaultAction)
                }
            }

            Toggle(isOn: $isMultiSelect.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open several apps at once")
                    Text("Launch a set of apps together and arrange their windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func selectedRow(_ app: AppInfo) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(app.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            WindowPositionMenu(position: positionBinding(for: app.bundleIdentifier))
            Button("Remove \(app.name)", systemImage: "xmark.circle.fill") { toggle(app) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
    }

    // MARK: - Data

    private var searchResults: [AppInfo] {
        var seen = Set<String>()
        let lowered = query.lowercased()
        return (runningApps + provider.apps)
            .filter { seen.insert($0.bundleIdentifier).inserted && $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(lowered)
                let rhsPrefix = rhs.name.lowercased().hasPrefix(lowered)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var defaultGroupName: String {
        selection.isEmpty ? "Group name" : selection.prefix(3).map(\.name).joined(separator: " + ")
    }

    private func isCurrentApp(_ app: AppInfo) -> Bool {
        if case .launchApp(let bundleId, _) = currentAction { return bundleId == app.bundleIdentifier }
        return false
    }

    private func load() {
        provider.loadIfNeeded()
        runningApps = InstalledAppProvider.runningApps()

        switch currentAction {
        case .launchApp(let bundleId, let name):
            selection = [AppInfo.resolve(bundleId: bundleId) ?? AppInfo(bundleIdentifier: bundleId, name: name, path: "")]
        case .showAppGroup(let groupId):
            guard let group = AppGroupStore.shared.group(id: groupId) else { return }
            existingGroupId = group.id
            selection = group.appBundleIdentifiers.compactMap { AppInfo.resolve(bundleId: $0) }
            positions = group.windowPositions
            groupName = group.name
            isMultiSelect = true
        default:
            break
        }
    }

    private func toggle(_ app: AppInfo) {
        withAnimation(.snappy) {
            if let index = selection.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                selection.remove(at: index)
            } else {
                selection.append(app)
            }
        }
    }

    private func submitTopResult() {
        guard let first = query.isEmpty ? nil : searchResults.first else { return }
        if isMultiSelect {
            toggle(first)
            query = ""
        } else {
            onAssign(.launchApp(bundleId: first.bundleIdentifier, appName: first.name))
        }
    }

    private func saveSelection() {
        guard !selection.isEmpty else { return }
        let selectedIds = Set(selection.map(\.bundleIdentifier))
        let placedWindows = positions.filter { selectedIds.contains($0.key) }

        if selection.count == 1, placedWindows.isEmpty {
            onAssign(.launchApp(bundleId: selection[0].bundleIdentifier, appName: selection[0].name))
            return
        }

        let trimmed = groupName.trimmingCharacters(in: .whitespaces)
        let group = AppGroup(
            id: existingGroupId ?? UUID(),
            name: trimmed.isEmpty ? defaultGroupName : trimmed,
            appBundleIdentifiers: selection.map(\.bundleIdentifier),
            windowPositions: placedWindows
        )
        AppGroupStore.shared.upsert(group)
        onAssign(.showAppGroup(groupId: group.id))
    }

    private func positionBinding(for bundleId: String) -> Binding<WindowPosition?> {
        Binding(
            get: { positions[bundleId] },
            set: { positions[bundleId] = $0 }
        )
    }
}

/// Compact menu for choosing where an app's window goes when its group opens.
struct WindowPositionMenu: View {
    @Binding var position: WindowPosition?

    var body: some View {
        Menu {
            Button("Leave Where It Is") { position = nil }
            ForEach(WindowPositionCategory.allCases, id: \.self) { category in
                Section(category.displayName) {
                    ForEach(category.positions, id: \.self) { option in
                        Button(option.displayName) { position = option }
                    }
                }
            }
        } label: {
            Text(position?.displayName ?? "Any Position")
        }
        .fixedSize()
        .help("Where this app's window goes")
    }
}
