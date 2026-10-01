import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI
import UniformTypeIdentifiers

/// Create, edit and delete quicklinks, and give them Hyper keys.
struct QuicklinksPage: View {
    @Bindable var bindingStore: BindingStore

    @State private var store = QuicklinkStore.shared
    @State private var draft: QuicklinkDraft?

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .quicklinks,
                subtitle: "Websites, folders and app links you open often. Open them from App Search, a shortcut or an alias."
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your Quicklinks")
                        .font(.headline)
                    if !store.quicklinks.isEmpty {
                        Text("\(store.quicklinks.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: .capsule)
                    }
                    Spacer()
                    Button("New Quicklink", systemImage: "plus") {
                        draft = QuicklinkDraft()
                    }
                }
                .padding(.horizontal, 4)

                if store.quicklinks.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.quicklinks) { quicklink in
                            QuicklinkRow(
                                quicklink: quicklink,
                                key: bindingStore.keyCode(for: .quicklink(name: quicklink.name)),
                                hyperKey: bindingStore.hyperKeyCode,
                                onOpen: { QuicklinkRunner.open(quicklink, from: nil) },
                                onEdit: {
                                    let action = BoundAction.quicklink(name: quicklink.name)
                                    draft = QuicklinkDraft(
                                        quicklink, key: bindingStore.keyCode(for: action),
                                        combo: GlobalShortcutStore.shared.shortcut(for: action)?.combo,
                                        alias: AliasStore.shared.alias(for: action)?.text
                                    )
                                },
                                onDelete: { delete(quicklink) }
                            )
                            if quicklink.id != store.quicklinks.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .hkListCard()
                }

                Text("Placeholders: {argument} asks for a value when you open it (name it with {argument name=\"query\"}). {clipboard}, {selection} and {date} work too. In web links, filled-in values are URL-encoded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .sheet(item: $draft) { draft in
            QuicklinkEditor(
                draft: draft,
                hyperKey: bindingStore.hyperKeyCode,
                isNameTaken: { name in
                    store.quicklinks.contains { $0.id != draft.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
                },
                currentAction: { shortcut in
                    switch shortcut {
                    case .hyper(let key): bindingStore.binding(for: key)?.action
                    case .combo(let combo): GlobalShortcutStore.shared.shortcuts.first { $0.combo == combo }?.action
                    }
                },
                onSave: { save($0) },
                onDelete: draft.isNew ? nil : {
                    if let quicklink = store.quicklink(id: draft.id) { delete(quicklink) }
                    self.draft = nil
                },
                onCancel: { self.draft = nil }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No quicklinks yet")
                .font(.headline)
            Text("Try https://github.com/search?q={argument} or ~/Projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("New Quicklink", systemImage: "plus") { draft = QuicklinkDraft() }
                .hkProminentButtonStyle()
                .padding(.top, 4)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .hkCard()
    }

    private func save(_ draft: QuicklinkDraft) {
        let quicklink = draft.quicklink
        if let original = draft.originalName, original != quicklink.name {
            bindingStore.renameQuicklink(from: original, to: quicklink.name)
            GlobalShortcutStore.shared.renameQuicklink(from: original, to: quicklink.name)
            AliasStore.shared.renameQuicklink(from: original, to: quicklink.name)
        }
        store.save(quicklink)

        let action = BoundAction.quicklink(name: quicklink.name)
        if let previous = bindingStore.keyCode(for: action), previous != draft.key {
            bindingStore.clearBinding(for: previous)
        }
        if let key = draft.key, bindingStore.binding(for: key)?.action != action {
            bindingStore.assign(action, to: key)
        }
        let shortcuts = GlobalShortcutStore.shared
        if shortcuts.shortcut(for: action)?.combo != draft.combo {
            shortcuts.set(draft.combo, for: action)
        }
        let aliases = AliasStore.shared
        if draft.alias.isEmpty {
            if let existing = aliases.alias(for: action) { aliases.delete(id: existing.id) }
        } else if aliases.alias(for: action)?.text != draft.alias {
            aliases.save(Alias(id: aliases.alias(for: action)?.id ?? UUID(), text: draft.alias, action: action))
        }
        self.draft = nil
    }

    private func delete(_ quicklink: Quicklink) {
        let action = BoundAction.quicklink(name: quicklink.name)
        if let key = bindingStore.keyCode(for: action) {
            bindingStore.clearBinding(for: key)
        }
        if GlobalShortcutStore.shared.shortcut(for: action) != nil {
            GlobalShortcutStore.shared.set(nil, for: action)
        }
        if let alias = AliasStore.shared.alias(for: action) {
            AliasStore.shared.delete(id: alias.id)
        }
        store.delete(id: quicklink.id)
    }
}

private struct QuicklinkRow: View {
    let quicklink: Quicklink
    let key: KeyCode?
    let hyperKey: KeyCode
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = QuicklinkRunner.icon(for: quicklink) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(quicklink.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(quicklink.link)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let key {
                HyperComboView(hyperKey: hyperKey, key: key, height: 20)
            }
            HStack(spacing: 6) {
                Button("Open", systemImage: "arrow.up.forward.square", action: onOpen)
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hkRowHighlight(isHovered)
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square", action: onOpen)
            Button("Edit Quicklink…", systemImage: "pencil", action: onEdit)
            CopyDeeplinkButton(for: .quicklink(name: quicklink.name))
            Divider()
            Button("Delete Quicklink", systemImage: "trash", role: .destructive, action: onDelete)
        }
        // The buttons only show on hover, so offer the same actions to VoiceOver.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

// MARK: - Editor

struct QuicklinkDraft: Identifiable {
    var id = UUID()
    var name = ""
    var link = ""
    var openWith: String?
    var key: KeyCode?
    /// A regular shortcut instead of a Hyper key.
    var combo: KeyCombo?
    /// Typed in App Search, it finds this quicklink ("gh"); text after it fills the `{argument}`.
    var alias = ""
    var isNew = true
    /// The name before editing, so shortcuts can follow a rename.
    var originalName: String?

    init() {}

    init(_ quicklink: Quicklink, key: KeyCode?, combo: KeyCombo?, alias: String?) {
        id = quicklink.id
        name = quicklink.name
        link = quicklink.link
        openWith = quicklink.openWith
        self.key = key
        self.combo = combo
        self.alias = alias ?? ""
        isNew = false
        originalName = quicklink.name
    }

    var quicklink: Quicklink {
        Quicklink(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            link: link.trimmingCharacters(in: .whitespacesAndNewlines),
            openWith: openWith
        )
    }
}

private struct QuicklinkEditor: View {
    @State var draft: QuicklinkDraft
    let hyperKey: KeyCode
    let isNameTaken: (String) -> Bool
    let currentAction: (RecordedShortcut) -> BoundAction?
    let onSave: (QuicklinkDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var isChoosingApp = false

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        if !trimmedName.isEmpty, isNameTaken(trimmedName) { return "You already have a quicklink called “\(trimmedName)”." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "New Quicklink" : "Edit Quicklink")
                .font(.title3.weight(.semibold))

            field("Name") {
                TextField("e.g. Search GitHub", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }
            field("Link") {
                TextField("https://github.com/search?q={argument}", text: $draft.link)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            field("Open with") {
                HStack {
                    Text(appName)
                    Spacer()
                    if draft.openWith != nil {
                        Button("Use Default") { draft.openWith = nil }
                    }
                    Button("Choose App…") { isChoosingApp = true }
                }
            }
            field("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorder(
                        keyCode: draft.key,
                        combo: draft.combo,
                        hyperKey: hyperKey,
                        onRecord: { shortcut in
                            switch shortcut {
                            case .hyper(let key): (draft.key, draft.combo) = (key, nil)
                            case .combo(let combo): (draft.key, draft.combo) = (nil, combo)
                            }
                        },
                        onClear: { (draft.key, draft.combo) = (nil, nil) }
                    )
                    if let recorded = draft.key.map(RecordedShortcut.hyper) ?? draft.combo.map(RecordedShortcut.combo),
                       let existing = currentAction(recorded),
                       existing != .quicklink(name: draft.originalName ?? ""),
                       let presentation = BindingPresentation(existing) {
                        Text("Replaces “\(presentation.summary)”.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            field("Alias") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("gh", text: $draft.alias)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 160)
                        .onChange(of: draft.alias) {
                            let normalized = Alias.normalized(draft.alias)
                            if normalized != draft.alias { draft.alias = normalized }
                        }
                    Text("Type it in App Search to jump here\(Placeholders.arguments(in: draft.link).isEmpty ? "" : ", followed by what to search for").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || draft.link.trimmingCharacters(in: .whitespaces).isEmpty || problem != nil)
            }
        }
        .padding(22)
        .frame(width: 540)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result, let bundleId = Bundle(url: url)?.bundleIdentifier {
                draft.openWith = bundleId
            }
        }
    }

    private var appName: String {
        if let openWith = draft.openWith {
            return AppInfo.resolve(bundleId: openWith)?.name ?? openWith
        }
        let probe = draft.quicklink
        if probe.isLocal { return "Finder (default)" }
        if let url = probe.openingAppURL {
            return "\((url.lastPathComponent as NSString).deletingPathExtension) (default)"
        }
        return "Default app"
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
