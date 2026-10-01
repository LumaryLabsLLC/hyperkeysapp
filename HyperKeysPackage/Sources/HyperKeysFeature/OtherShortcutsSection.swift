import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI

/// Regular shortcuts (⌥Space, ⇧⌘V…) that run any action without the Hyper key.
struct OtherShortcutsSection: View {
    @State private var store = GlobalShortcutStore.shared
    @State private var hotKeys = GlobalHotKeys.shared
    @State private var draft: GlobalShortcutDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Other Shortcuts")
                    .font(.headline)
                if !store.shortcuts.isEmpty {
                    Text("\(store.shortcuts.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                Spacer()
                Button("Add Shortcut", systemImage: "plus") { draft = GlobalShortcutDraft() }
            }
            .padding(.horizontal, 4)

            if store.shortcuts.isEmpty {
                Text("Regular shortcuts like ⌥Space or ⇧⌘V that run anything a Hyper key can, in every app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .hkCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.shortcuts) { shortcut in
                        GlobalShortcutRow(
                            shortcut: shortcut,
                            isTaken: hotKeys.conflicts.contains(shortcut.combo),
                            onEdit: { draft = GlobalShortcutDraft(shortcut) },
                            onDelete: { store.delete(id: shortcut.id) }
                        )
                        if shortcut.id != store.shortcuts.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .hkListCard()
            }
        }
        .sheet(item: $draft) { draft in
            GlobalShortcutEditor(
                draft: draft,
                usedBy: { combo in store.shortcuts.first { $0.combo == combo && $0.id != draft.id } },
                onSave: { saved in
                    if let combo = saved.combo, let action = saved.action {
                        store.save(GlobalShortcut(id: saved.id, combo: combo, action: action))
                    }
                    self.draft = nil
                },
                onDelete: draft.isNew ? nil : {
                    store.delete(id: draft.id)
                    self.draft = nil
                },
                onCancel: { self.draft = nil }
            )
        }
    }
}

private struct GlobalShortcutRow: View {
    let shortcut: GlobalShortcut
    let isTaken: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let presentation = BindingPresentation(shortcut.action)
        HStack(spacing: 12) {
            ComboKeycaps(combo: shortcut.combo, height: 22)
                .fixedSize()
                .frame(minWidth: 120, alignment: .leading)
            if let presentation {
                BindingIcon(presentation: presentation, size: 26)
                    .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation?.title ?? "Unknown action")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if isTaken {
                    Label("Another app already uses \(shortcut.combo.displayLabel)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let presentation {
                    Text(presentation.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .hkRowHighlight(isHovered)
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Shortcut…", systemImage: "pencil", action: onEdit)
            CopyDeeplinkButton(for: shortcut.action)
            Divider()
            Button("Delete Shortcut", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

struct GlobalShortcutDraft: Identifiable {
    var id = UUID()
    var combo: KeyCombo?
    var action: BoundAction?
    var isNew = true

    init() {}

    init(_ shortcut: GlobalShortcut) {
        id = shortcut.id
        combo = shortcut.combo
        action = shortcut.action
        isNew = false
    }
}

private struct GlobalShortcutEditor: View {
    @State var draft: GlobalShortcutDraft
    let usedBy: (KeyCombo) -> GlobalShortcut?
    let onSave: (GlobalShortcutDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    var body: some View {
        ActionTriggerEditor(
            title: draft.isNew ? "New Shortcut" : "Edit Shortcut",
            action: $draft.action,
            canSave: draft.combo != nil,
            onSave: { onSave(draft) },
            onDelete: onDelete,
            onCancel: onCancel
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcut")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                KeyComboRecorder(combo: draft.combo, onRecord: { draft.combo = $0 }, onClear: { draft.combo = nil })
                if let combo = draft.combo, let other = usedBy(combo), let presentation = BindingPresentation(other.action) {
                    Text("Replaces “\(presentation.title)”.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
