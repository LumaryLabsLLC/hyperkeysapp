import KeyBindings
import KeyboardUI
import SwiftUI

/// Short words that find something in App Search ("gh" → Search GitHub).
struct AliasesSection: View {
    @State private var store = AliasStore.shared
    @State private var draft: AliasDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aliases")
                    .font(.headline)
                Spacer()
                Button("Add Alias", systemImage: "plus") { draft = AliasDraft() }
            }
            .padding(.horizontal, 4)

            if store.aliases.isEmpty {
                Text("Give anything a short name, like “gh” for a GitHub quicklink, and it's the first result when you type it in App Search. Type more after a quicklink's alias (“gh swift”) to fill in its search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .hkCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.aliases) { alias in
                        AliasRow(
                            alias: alias,
                            onEdit: { draft = AliasDraft(alias) },
                            onDelete: { store.delete(id: alias.id) }
                        )
                        if alias.id != store.aliases.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .hkListCard()
            }
        }
        .sheet(item: $draft) { draft in
            AliasEditor(
                draft: draft,
                usedBy: { text in store.aliases.first { $0.text == text && $0.id != draft.id } },
                onSave: { saved in
                    if let action = saved.action {
                        store.save(Alias(id: saved.id, text: saved.text, action: action))
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

/// An alias as App Search shows it: a small monospaced tag.
struct AliasTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.primary.opacity(0.08), in: .rect(cornerRadius: 5, style: .continuous))
    }
}

private struct AliasRow: View {
    let alias: Alias
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let presentation = BindingPresentation(alias.action)
        HStack(spacing: 12) {
            AliasTag(text: alias.text)
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
                if let presentation {
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
            Button("Edit Alias…", systemImage: "pencil", action: onEdit)
            CopyDeeplinkButton(for: alias.action)
            Divider()
            Button("Delete Alias", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

struct AliasDraft: Identifiable {
    var id = UUID()
    var text = ""
    var action: BoundAction?
    var isNew = true

    init() {}

    init(_ alias: Alias) {
        id = alias.id
        text = alias.text
        action = alias.action
        isNew = false
    }
}

private struct AliasEditor: View {
    @State var draft: AliasDraft
    let usedBy: (String) -> Alias?
    let onSave: (AliasDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ActionTriggerEditor(
            title: draft.isNew ? "New Alias" : "Edit Alias",
            action: $draft.action,
            canSave: !draft.text.isEmpty,
            onSave: { onSave(draft) },
            onDelete: onDelete,
            onCancel: onCancel
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alias")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("gh", text: $draft.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 160)
                    .focused($isFocused)
                    .onChange(of: draft.text) {
                        let normalized = Alias.normalized(draft.text)
                        if normalized != draft.text { draft.text = normalized }
                    }
                if let other = usedBy(draft.text), let presentation = BindingPresentation(other.action) {
                    Text("Replaces the alias for “\(presentation.title)”.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear { isFocused = true }
    }
}
