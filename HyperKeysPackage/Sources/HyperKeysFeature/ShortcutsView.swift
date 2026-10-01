import AppSwitcher
import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI

struct ShortcutsView: View {
    @Bindable var bindingStore: BindingStore
    let status: HyperKeyStatus

    /// Key whose editor is open on the keyboard.
    @State private var editingKey: KeyCode?
    /// Key whose editor is open from the list below the keyboard.
    @State private var listEditingKey: KeyCode?
    /// Observed so group renames / edits refresh the list and keycaps.
    @State private var groupStore = AppGroupStore.shared
    @State private var isImportingFromRaycast = false

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .shortcuts,
                subtitle: "Hold \(bindingStore.hyperKeyCode.name) and press a key to run its shortcut. Click a key — or just press it — to set one up."
            )

            KeyboardView(bindingStore: bindingStore, editingKey: $editingKey, status: status)

            legend

            assignedList
        }
        .sheet(isPresented: $isImportingFromRaycast) {
            RaycastImportSheet(bindingStore: bindingStore)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach([ActionKind.app, .appGroup, .window, .menu, .folder], id: \.self) { kind in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(kind.color.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(kind.color.opacity(0.7), lineWidth: 1))
                        .frame(width: 12, height: 12)
                    Text(kind.title)
                }
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Assigned shortcuts

    private var sortedBindings: [KeyBinding] {
        let order = Dictionary(uniqueKeysWithValues: KeyboardLayout.keyOrder.enumerated().map { ($1, $0) })
        return bindingStore.activeBindings
            .filter { $0.isEnabled && $0.keyCode != bindingStore.hyperKeyCode && ActionKind($0.action) != nil }
            .sorted { (order[$0.keyCode] ?? .max) < (order[$1.keyCode] ?? .max) }
    }

    private var assignedList: some View {
        let bindings = sortedBindings

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Shortcuts")
                    .font(.headline)
                if !bindings.isEmpty {
                    Text("\(bindings.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                Spacer()
                if !bindingStore.actionGroups.isEmpty {
                    Text("Profile: \(bindingStore.activeProfileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Import from Raycast…", systemImage: "square.and.arrow.down") {
                    isImportingFromRaycast = true
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            if bindings.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(bindings) { binding in
                        if let presentation = BindingPresentation(binding.action) {
                            ShortcutRow(
                                keyCode: binding.keyCode,
                                hyperKey: bindingStore.hyperKeyCode,
                                presentation: presentation,
                                onEdit: { listEditingKey = binding.keyCode },
                                onRemove: {
                                    withAnimation(.snappy) { bindingStore.clearBinding(for: binding.keyCode) }
                                }
                            )
                            .popover(isPresented: listEditorPresented(for: binding.keyCode), arrowEdge: .leading) {
                                BindingEditor(keyCode: binding.keyCode, bindingStore: bindingStore) {
                                    listEditingKey = nil
                                }
                            }

                            if binding.id != bindings.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .hkCard()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text("No shortcuts yet")
                .font(.headline)
            Text("Click any key above — or press it on your keyboard — to open an app, snap a window or run a menu command with Hyper + that key.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .hkCard()
    }

    private func listEditorPresented(for keyCode: KeyCode) -> Binding<Bool> {
        Binding(
            get: { listEditingKey == keyCode },
            set: { if !$0, listEditingKey == keyCode { listEditingKey = nil } }
        )
    }
}

private struct ShortcutRow: View {
    let keyCode: KeyCode
    let hyperKey: KeyCode
    let presentation: BindingPresentation
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            HyperComboView(hyperKey: hyperKey, key: keyCode, height: 22)
                .fixedSize()
                .frame(minWidth: 96, alignment: .leading)

            BindingIcon(presentation: presentation, size: 26)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: presentation.kind.symbol)
                        .foregroundStyle(presentation.kind.color)
                    Text(detailText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Edit Shortcut…", systemImage: "pencil", action: onEdit)
            Button("Remove Shortcut", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Remove", onRemove)
    }

    private var detailText: String {
        switch presentation.kind {
        case .app, .window: presentation.kind.title
        case .appGroup, .menu, .folder, .appSearch, .appSwitcher, .emojiPicker, .snippets, .emptyTrash: presentation.subtitle
        }
    }
}
