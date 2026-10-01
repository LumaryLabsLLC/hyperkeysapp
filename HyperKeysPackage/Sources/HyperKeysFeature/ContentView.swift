import EventEngine
import KeyBindings
import KeyboardUI
import Permissions
import SwiftUI

public struct ContentView: View {
    let bindingStore: BindingStore
    let permissionManager: PermissionManager
    let status: HyperKeyStatus
    var onHyperKeyChanged: (KeyCode) -> Void
    var onPauseChanged: (Bool) -> Void

    public init(
        bindingStore: BindingStore,
        permissionManager: PermissionManager,
        status: HyperKeyStatus,
        onHyperKeyChanged: @escaping (KeyCode) -> Void,
        onPauseChanged: @escaping (Bool) -> Void
    ) {
        self.bindingStore = bindingStore
        self.permissionManager = permissionManager
        self.status = status
        self.onHyperKeyChanged = onHyperKeyChanged
        self.onPauseChanged = onPauseChanged
    }

    public var body: some View {
        Group {
            if permissionManager.shouldShowMainUI {
                MainView(
                    bindingStore: bindingStore,
                    permissionManager: permissionManager,
                    status: status,
                    onHyperKeyChanged: onHyperKeyChanged,
                    onPauseChanged: onPauseChanged
                )
            } else {
                OnboardingView(permissionManager: permissionManager)
            }
        }
        // Fixed width keeps the sidebar and full-size keyboard visible; height can grow.
        .frame(width: Self.windowWidth)
        .frame(minHeight: 640, idealHeight: 760, maxHeight: .infinity)
        .tint(Brand.purple)
    }

    public static let windowWidth: CGFloat = 1060
}

struct MainView: View {
    @Bindable var bindingStore: BindingStore
    let permissionManager: PermissionManager
    let status: HyperKeyStatus
    var onHyperKeyChanged: (KeyCode) -> Void
    var onPauseChanged: (Bool) -> Void

    @SceneStorage("selectedPane") private var selection: Pane = .shortcuts
    @State private var navigation = NavigationRequests.shared

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: selectionBinding) {
                ForEach(Pane.allCases) { pane in
                    NavigationLink(value: pane) {
                        Label {
                            Text(pane.title)
                        } icon: {
                            IconTile(symbol: pane.symbol, color: pane.color, size: 22)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationSplitViewColumnWidth(214)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStatusCard(
                    status: status,
                    permissionManager: permissionManager,
                    hyperKey: bindingStore.hyperKeyCode,
                    onShowSettings: { selection = .settings },
                    onPauseChanged: onPauseChanged
                )
                .padding(10)
            }
        } detail: {
            detail
                .onChange(of: navigation.pane, initial: true) { _, requested in
                    guard let requested else { return }
                    selection = requested
                    navigation.pane = nil
                }
                // Shared by every page so the toolbar never changes height between panes.
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ProfileMenu(bindingStore: bindingStore)
                    }
                }
        }
    }

    private var selectionBinding: Binding<Pane?> {
        Binding(
            get: { selection },
            set: { if let pane = $0 { selection = pane } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .shortcuts:
            ShortcutsView(bindingStore: bindingStore, status: status)
        case .windows:
            WindowsView(bindingStore: bindingStore)
        case .appSearch:
            AppSearchPage(bindingStore: bindingStore)
        case .snippets:
            SnippetsPage(bindingStore: bindingStore)
        case .quicklinks:
            QuicklinksPage(bindingStore: bindingStore)
        case .clipboard:
            ClipboardPage(bindingStore: bindingStore)
        case .hyperKey:
            HyperKeyView(bindingStore: bindingStore, status: status, onHyperKeyChanged: onHyperKeyChanged)
        case .settings:
            SettingsView(bindingStore: bindingStore, permissionManager: permissionManager, status: status, onPauseChanged: onPauseChanged)
        }
    }
}

/// Always-visible answer to "is it working?" at the bottom of the sidebar.
struct SidebarStatusCard: View {
    let status: HyperKeyStatus
    let permissionManager: PermissionManager
    let hyperKey: KeyCode
    let onShowSettings: () -> Void
    let onPauseChanged: (Bool) -> Void

    private enum State {
        case needsPermissions, paused, held, active
    }

    private var state: State {
        if !permissionManager.allPermissionsGranted { return .needsPermissions }
        if status.isPaused { return .paused }
        if status.isHyperKeyDown { return .held }
        return .active
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.8), radius: state == .held ? 5 : 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            switch state {
            case .needsPermissions:
                Button("Fix", action: onShowSettings)
                    .controlSize(.small)
            case .paused:
                Button("Resume") { onPauseChanged(false) }
                    .controlSize(.small)
            case .held, .active:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hkGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: state == .held ? Brand.purple.opacity(0.35) : nil)
        .animation(.snappy(duration: 0.2), value: state)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch state {
        case .needsPermissions: .orange
        case .paused: .gray
        case .held: Brand.purple
        case .active: .green
        }
    }

    private var title: String {
        switch state {
        case .needsPermissions: "Setup needed"
        case .paused: "Paused"
        case .held: "Hyper is on"
        case .active: "Active"
        }
    }

    private var detail: String {
        switch state {
        case .needsPermissions: "Grant permissions to start"
        case .paused: "Shortcuts are off"
        case .held: "Press any key…"
        case .active: "Hold \(hyperKey.name) + a key"
        }
    }
}
