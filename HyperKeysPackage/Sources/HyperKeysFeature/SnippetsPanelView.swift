import KeyBindings
import KeyboardUI
import SwiftUI

/// Search field + tag filter, the snippet list (grouped by last use), a preview with details,
/// and a footer with what Return does.
struct SnippetsPanelView: View {
    @Bindable var model: SnippetsPanelModel
    let onInsert: (Snippet, _ paste: Bool) -> Void
    let onNew: () -> Void

    @FocusState private var isSearchFocused: Bool

    static let width: CGFloat = 760
    private let bodyHeight: CGFloat = 380
    private let listWidth: CGFloat = 270
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                if model.store.snippets.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 0) {
                        list
                            .frame(width: listWidth)
                        Divider().opacity(0.5)
                        detail
                    }
                }
            }
            .frame(height: bodyHeight)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
        .onChange(of: model.focusRequest) {
            isSearchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search snippets…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
            if !model.store.allTags.isEmpty {
                Menu {
                    Button("All Tags") { model.tag = nil }
                    Divider()
                    ForEach(model.store.allTags, id: \.self) { tag in
                        Button(tag) { model.tag = tag }
                    }
                } label: {
                    Label(model.tag ?? "All Tags", systemImage: "tag")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // MARK: - List

    private enum Row: Identifiable {
        case header(String)
        case snippet(Snippet, index: Int)

        var id: String {
            switch self {
            case .header(let title): "header-\(title)"
            case .snippet(let snippet, _): snippet.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var index = 0
        for section in model.sections {
            rows.append(.header(section.title))
            for snippet in section.snippets {
                rows.append(.snippet(snippet, index: index))
                index += 1
            }
        }
        return rows
    }

    @ViewBuilder
    private var list: some View {
        if model.items.isEmpty {
            Text("No snippets match “\(model.query)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            switch row {
                            case .header(let title):
                                Text(title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                            case .snippet(let snippet, let index):
                                snippetRow(snippet, isSelected: index == model.selection, index: index)
                            }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) {
                    if let selected = model.selectedSnippet {
                        proxy.scrollTo(selected.id.uuidString)
                    }
                }
            }
        }
    }

    private func snippetRow(_ snippet: Snippet, isSelected: Bool, index: Int) -> some View {
        Button {
            model.selection = index
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
                Text(snippet.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let keyword = snippet.keyword {
                    Text(keyword)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onInsert(snippet, true) })
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let snippet = model.selectedSnippet {
            ScrollView {
                Text(snippet.text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    // MARK: - Empty & footer

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No snippets yet")
                .font(.headline)
            Text("Save text you type often — addresses, links, replies — and paste it anywhere.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Create Snippet", action: onNew)
                .hkProminentButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: onNew) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("New Snippet")
                    KeycapChip("⌘", height: 18)
                    KeycapChip("N", height: 18)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer()
            if model.selectedSnippet != nil {
                action(model.targetAppName.map { "Paste to \($0)" } ?? "Paste", keys: ["↩"])
                action("Copy", keys: ["⌘", "↩"])
                action("Edit", keys: ["⌘", "E"])
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private func action(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ForEach(keys, id: \.self) { KeycapChip($0, height: 18) }
        }
    }
}
