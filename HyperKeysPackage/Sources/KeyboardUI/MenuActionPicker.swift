import AppKit
import AppSwitcher
import ContextEngine
import KeyBindings
import Shared
import SwiftUI

/// Choose a running app, then browse or search its menu bar for a command.
struct MenuActionPicker: View {
    let currentAction: BoundAction?
    let onAssign: (BoundAction) -> Void

    @State private var runningApps: [AppInfo] = []
    @State private var target: AppInfo?
    @State private var menus: [MenuItemInfo] = []
    @State private var drillPath: [MenuItemInfo] = []
    @State private var query = ""
    @State private var isLoading = false

    private var currentPath: [String]? {
        if case .triggerMenuItem(_, let path) = currentAction { return path }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let target {
                menuBrowser(for: target)
            } else {
                appList
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Step 1: choose an app

    private var appList: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search open apps", text: $query) {
                if let first = filteredApps.first { select(first) }
            }
            .padding(12)

            if filteredApps.isEmpty {
                PickerMessage(symbol: "app.dashed", title: "No open apps", message: "Open the app whose menu command you want to use.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        PickerSectionHeader(title: "Choose an app to browse its menus")
                        ForEach(filteredApps) { app in
                            PickerRow(title: app.name) {
                                select(app)
                            } leading: {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                            } trailing: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var filteredApps: [AppInfo] {
        query.isEmpty ? runningApps : runningApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Step 2: browse the app's menus

    private func menuBrowser(for app: AppInfo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .labelStyle(.iconOnly)
                    .hkButtonStyle()
                    .controlSize(.small)
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text(([app.name] + drillPath.map(\.title)).joined(separator: " › "))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            SearchField(prompt: "Search \(app.name) commands", text: $query)
                .padding(12)

            if isLoading {
                PickerMessage(symbol: "", title: "Reading menus…", isLoading: true)
            } else if menus.isEmpty {
                PickerMessage(
                    symbol: "filemenu.and.selection",
                    title: "No menus found",
                    message: "HyperKeys needs Accessibility permission to read other apps' menus."
                )
            } else if !query.isEmpty {
                searchResults
            } else {
                levelList
            }
        }
    }

    private var levelList: some View {
        let items = drillPath.last?.children ?? menus
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    PickerRow(title: item.title, isSelected: item.path == currentPath) {
                        if item.children.isEmpty {
                            assign(item)
                        } else {
                            withAnimation(.snappy(duration: 0.2)) { drillPath.append(item) }
                        }
                    } leading: {
                        EmptyView()
                    } trailing: {
                        if !item.children.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .opacity(item.isEnabled || !item.children.isEmpty ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var searchResults: some View {
        let matches = Array(leaves(of: menus).filter {
            $0.path.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }.prefix(150))

        return Group {
            if matches.isEmpty {
                PickerMessage(symbol: "magnifyingglass", title: "No commands match “\(query)”")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { _, item in
                            PickerRow(
                                title: item.title,
                                subtitle: item.path.dropLast().joined(separator: " › "),
                                isSelected: item.path == currentPath
                            ) {
                                assign(item)
                            } leading: {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() {
        runningApps = InstalledAppProvider.runningApps()
        if case .triggerMenuItem(let bundleId, _) = currentAction,
           let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
            select(app)
        }
    }

    private func select(_ app: AppInfo) {
        target = app
        query = ""
        drillPath = []
        menus = []
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first?.processIdentifier else {
            return
        }
        isLoading = true
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                MenuBarReader.readMenuItems(forPID: pid)
            }.value
            guard target?.bundleIdentifier == app.bundleIdentifier else { return }
            menus = items
            isLoading = false
        }
    }

    private func goBack() {
        query = ""
        if drillPath.isEmpty {
            target = nil
            menus = []
            isLoading = false
        } else {
            withAnimation(.snappy(duration: 0.2)) { _ = drillPath.removeLast() }
        }
    }

    private func assign(_ item: MenuItemInfo) {
        guard let target else { return }
        onAssign(.triggerMenuItem(appBundleId: target.bundleIdentifier, menuPath: item.path))
    }

    private func leaves(of items: [MenuItemInfo]) -> [MenuItemInfo] {
        items.flatMap { $0.children.isEmpty ? [$0] : leaves(of: $0.children) }
    }
}
