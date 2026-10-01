import AppKit
import AppSwitcher
import KeyboardUI
import Shared
import SwiftUI

/// The floating App Search panel: a search field, recent apps and commands (or search results),
/// and a footer with what Return does plus a way into Settings. Sized to exactly its content.
struct AppSearchLauncherView: View {
    @Bindable var model: AppSearchModel
    let onRun: (LauncherItem) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var isSearchFocused: Bool

    private let rowHeight: CGFloat = 40
    private let headerHeight: CGFloat = 28
    /// Room for the whole home screen (5 recent apps + 5 commands + 2 headers) without scrolling.
    private let maxListHeight: CGFloat = 10 * 40 + 2 * 28 + 12
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider().opacity(0.5)
            if model.items.isEmpty {
                Text(model.query.isEmpty ? " " : (model.provider.isLoading ? "Finding apps…" : "No apps or commands found"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
            } else {
                list
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: AppSearchController.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
        .onChange(of: model.focusRequest) {
            isSearchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search for apps and commands…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    // MARK: - Results

    /// One flat list of headers and items. Each row has exactly one identity (its item or
    /// header id), so changing the results can never leave stale rows on screen.
    private enum DisplayRow: Identifiable {
        case header(String)
        case item(LauncherItem, index: Int)

        var id: String {
            switch self {
            case .header(let title): "header-\(title)"
            case .item(let item, _): item.id
            }
        }
    }

    private var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        var index = 0
        for section in model.sections {
            if let title = section.title {
                rows.append(.header(title))
            }
            for item in section.items {
                rows.append(.item(item, index: index))
                index += 1
            }
        }
        return rows
    }

    private var list: some View {
        let rows = displayRows
        let natural = CGFloat(model.items.count) * rowHeight
            + CGFloat(model.sections.filter { $0.title != nil }.count) * headerHeight + 12

        return ScrollViewReader { proxy in
            ScrollView {
                // At most ~30 rows, so render them all; a lazy stack kept stale rows on screen
                // after the results changed.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { displayRow in
                        switch displayRow {
                        case .header(let title):
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: headerHeight, alignment: .bottomLeading)
                        case .item(let item, let index):
                            row(item, isSelected: index == model.selection)
                        }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .frame(height: min(natural, maxListHeight))
            .onChange(of: model.selection) {
                if let selected = model.selectedItem {
                    proxy.scrollTo(selected.id)
                }
            }
        }
    }

    private func row(_ item: LauncherItem, isSelected: Bool) -> some View {
        Button {
            onRun(item)
        } label: {
            HStack(spacing: 10) {
                icon(for: item)
                    .frame(width: 24, height: 24)
                Text(item.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                if let alias = model.aliasLabels[item.id] {
                    Text(alias)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.primary.opacity(0.08), in: .rect(cornerRadius: 4, style: .continuous))
                        .help("Alias")
                }
                if let argument = model.aliasArgument, argument.itemId == item.id {
                    Text(argument.text.isEmpty ? "Type to search" : "“\(argument.text)”")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if case .command(let command) = item {
                    Text(command.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if case .folder(let path) = item {
                    Text(path)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let key = model.shortcuts[item.id] {
                    HyperComboView(hyperKey: model.hyperKey, key: key, height: 17)
                        .opacity(0.85)
                }
                if let combo = model.combos[item.id] {
                    ComboKeycaps(combo: combo, height: 17)
                        .opacity(0.85)
                }
                Text(item.typeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func icon(for item: LauncherItem) -> some View {
        switch item {
        case .app(let app):
            if let image = app.icon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            }
        case .folder(let path):
            Image(nsImage: AppIconCache.icon(forPath: (path as NSString).expandingTildeInPath))
                .resizable()
                .interpolation(.high)
        case .command(let command):
            switch command.icon {
            case .symbol(let symbol, let color):
                IconTile(symbol: symbol, color: color, size: 22)
            case .windowLayout(let position):
                WindowLayoutGlyph(position: position, color: ActionKind.window.color)
                    .frame(width: 24, height: 17)
            case .file(let path):
                Image(nsImage: AppIconCache.icon(forPath: path))
                    .resizable()
                    .interpolation(.high)
            case .quicklink(let quicklink):
                if let image = QuicklinkRunner.icon(for: quicklink) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(.rect(cornerRadius: 5, style: .continuous))
                } else {
                    IconTile(symbol: ActionKind.quicklink.symbol, color: ActionKind.quicklink.color, size: 22)
                }
            case .binding(let presentation):
                BindingIcon(presentation: presentation, size: 22)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Label("HyperKeys", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            if let item = model.selectedItem {
                HStack(spacing: 5) {
                    Text(item.actionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    KeycapChip("↩", height: 18)
                }
            }
            Divider()
                .frame(height: 16)
            Button(action: onOpenSettings) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    KeycapChip("⌘", height: 18)
                    KeycapChip(",", height: 18)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Open HyperKeys settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}
