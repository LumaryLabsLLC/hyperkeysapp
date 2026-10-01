import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard History: its shortcut, how long to keep things, apps to leave out, and clearing it.
struct ClipboardPage: View {
    @Bindable var bindingStore: BindingStore

    @State private var store = ClipboardHistoryStore.shared
    @State private var isConfirmingClear = false
    @State private var isAddingApp = false

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .clipboard,
                subtitle: "Everything you copy, kept on this Mac. Search it and paste it again in any app."
            )

            panelCard

            VStack(alignment: .leading, spacing: 10) {
                Text("History")
                    .font(.headline)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    settingRow {
                        Toggle("Save clipboard history", isOn: $store.isEnabled)
                    }
                    Divider().padding(.leading, 14)
                    settingRow {
                        Picker("Keep history for", selection: $store.retention) {
                            ForEach(ClipboardRetention.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(!store.isEnabled)
                    }
                    Divider().padding(.leading, 14)
                    settingRow {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                                if !store.pinnedItems.isEmpty {
                                    Text("\(store.pinnedItems.count) pinned — kept until you unpin them")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                                .disabled(store.items.allSatisfy(\.isPinned))
                        }
                    }
                }
                .hkCard()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Never Save From")
                        .font(.headline)
                    Spacer()
                    Button("Add App…", systemImage: "plus") { isAddingApp = true }
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    if visibleIgnoredApps.isEmpty {
                        Text("Copies from every app are saved.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    ForEach(visibleIgnoredApps, id: \.self) { bundleId in
                        ignoredAppRow(bundleId)
                        if bundleId != visibleIgnoredApps.last {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .hkCard()

                Text("History stays on this Mac. It isn't saved in config.json or synced with iCloud. Passwords and anything else an app marks as private are never saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .fileImporter(isPresented: $isAddingApp, allowedContentTypes: [.application]) { result in
            guard case .success(let url) = result, let bundleId = Bundle(url: url)?.bundleIdentifier,
                  !store.ignoredBundleIds.contains(bundleId)
            else { return }
            store.ignoredBundleIds.append(bundleId)
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything you've copied is deleted from HyperKeys. Pinned items are kept.")
        }
    }

    private var panelCard: some View {
        HStack(spacing: 16) {
            IconTile(symbol: ActionKind.clipboardHistory.symbol, color: ActionKind.clipboardHistory.color, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard History panel")
                        .font(.headline)
                    Text("Search what you've copied from any app. Return pastes, ⌘Return copies, ⌘P pins.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ActionShortcutField(action: .clipboardHistory, bindingStore: bindingStore)
            }
            Spacer(minLength: 12)
            Button("Try It") { ClipboardHistoryPanelController.shared.show() }
                .hkProminentButtonStyle()
        }
        .padding(18)
        .hkGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: ActionKind.clipboardHistory.color.opacity(0.06))
    }

    /// Built-in password managers you don't have stay protected, but aren't listed until installed.
    private var visibleIgnoredApps: [String] {
        store.ignoredBundleIds.filter {
            AppInfo.resolve(bundleId: $0) != nil || !ClipboardHistoryStore.defaultIgnoredBundleIds.contains($0)
        }
    }

    private func settingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ignoredAppRow(_ bundleId: String) -> some View {
        let app = AppInfo.resolve(bundleId: bundleId)
        return HStack(spacing: 12) {
            if let icon = AppIconCache.icon(forBundleId: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.name ?? bundleId)
                if app == nil {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Remove", systemImage: "minus.circle") {
                store.ignoredBundleIds.removeAll { $0 == bundleId }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Save copies from this app again")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
