import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI

/// Create, edit and delete snippets, and give the Snippets panel a shortcut.
struct SnippetsPage: View {
    @Bindable var bindingStore: BindingStore

    @State private var store = SnippetStore.shared
    @State private var navigation = NavigationRequests.shared
    @State private var draft: SnippetDraft?
    @AppStorage(Preferences.expandSnippetKeywords) private var expandKeywords = true
    @State private var isImportingFromRaycast = false

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .snippets,
                subtitle: "Save text you type often — addresses, links, replies — and paste it anywhere."
            )

            panelCard

            Toggle(isOn: $expandKeywords) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expand keywords as you type")
                    Text("Give a snippet a keyword, like ;addr, and typing it anywhere replaces it with the snippet. Never in password fields.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hkCard()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your Snippets")
                        .font(.headline)
                    if !store.snippets.isEmpty {
                        Text("\(store.snippets.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: .capsule)
                    }
                    Spacer()
                    Button("Import from Raycast…", systemImage: "square.and.arrow.down") {
                        isImportingFromRaycast = true
                    }
                    Button("New Snippet", systemImage: "plus") {
                        draft = SnippetDraft()
                    }
                }
                .padding(.horizontal, 4)

                if store.snippets.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.snippets) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                onEdit: { draft = SnippetDraft(snippet) },
                                onDelete: { store.delete(id: snippet.id) }
                            )
                            if snippet.id != store.snippets.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .hkListCard()
                }

                Text("Placeholders like {clipboard}, {date} and {time} are filled in when you paste. Snippets are saved in config.json with the rest of your settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .sheet(item: $draft) { draft in
            SnippetEditor(
                draft: draft,
                onSave: { snippet in
                    store.save(snippet)
                    self.draft = nil
                },
                onDelete: draft.isNew ? nil : {
                    store.delete(id: draft.id)
                    self.draft = nil
                },
                onCancel: { self.draft = nil }
            )
        }
        .sheet(isPresented: $isImportingFromRaycast) {
            RaycastImportSheet(bindingStore: bindingStore)
        }
        .onChange(of: navigation.snippet, initial: true) { _, request in
            guard let request else { return }
            switch request {
            case .create:
                draft = SnippetDraft()
            case .edit(let id):
                draft = store.snippet(id: id).map(SnippetDraft.init)
            }
            navigation.snippet = nil
        }
    }

    private var panelCard: some View {
        HStack(spacing: 16) {
            IconTile(symbol: ActionKind.snippets.symbol, color: ActionKind.snippets.color, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snippets panel")
                        .font(.headline)
                    Text("Search your snippets from any app. Return pastes, ⌘Return copies. Also in App Search.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ActionShortcutField(action: .snippets, bindingStore: bindingStore)
            }
            Spacer(minLength: 12)
            Button("Try It") { SnippetsPanelController.shared.show() }
                .hkProminentButtonStyle()
        }
        .padding(18)
        .hkGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: ActionKind.snippets.color.opacity(0.06))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No snippets yet")
                .font(.headline)
            Text("Create one for anything you type more than twice.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("New Snippet", systemImage: "plus") { draft = SnippetDraft() }
                .hkProminentButtonStyle()
                .padding(.top, 4)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .hkCard()
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let keyword = snippet.keyword {
                Text(keyword)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                    .help("Type \(keyword) anywhere to paste this snippet")
            }
            ForEach(snippet.tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
            HStack(spacing: 6) {
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
            Button("Edit Snippet…", systemImage: "pencil", action: onEdit)
            Button("Delete Snippet", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Editor

struct SnippetDraft: Identifiable {
    var id = UUID()
    var name = ""
    var text = ""
    var tags = ""
    var keyword = ""
    var isNew = true

    init() {}

    init(_ snippet: Snippet) {
        id = snippet.id
        name = snippet.name
        text = snippet.text
        tags = snippet.tags.joined(separator: ", ")
        keyword = snippet.keyword ?? ""
        isNew = false
    }

    var snippet: Snippet {
        Snippet(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            text: text,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            keyword: keyword.trimmingCharacters(in: .whitespaces)
        )
    }
}

private struct SnippetEditor: View {
    @State var draft: SnippetDraft
    let onSave: (Snippet) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    /// Another snippet with the same keyword (the longer keyword wins when typing, so warn).
    private var keywordClash: String? {
        let keyword = draft.keyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return nil }
        return SnippetStore.shared.snippets.first { $0.id != draft.id && $0.keyword == keyword }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "New Snippet" : "Edit Snippet")
                .font(.title3.weight(.semibold))

            field("Name") {
                TextField("e.g. Home Address", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }
            field("Text") {
                TextEditor(text: $draft.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 170)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
            HStack(alignment: .top, spacing: 12) {
                field("Keyword") {
                    TextField("Optional, e.g. ;addr", text: $draft.keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                .frame(width: 180)
                field("Tags") {
                    TextField("Optional, separated by commas", text: $draft.tags)
                        .textFieldStyle(.roundedBorder)
                }
            }
            if let clash = keywordClash {
                Text("“\(clash)” already uses this keyword.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Placeholders like {clipboard}, {date} and {time} are filled in when you paste.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft.snippet) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.text.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
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
