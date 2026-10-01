import KeyBindings
import KeyboardUI
import Shared
import SwiftUI

/// Search field + type filter, the history grouped by day, a preview, and a footer with what the keys do.
struct ClipboardHistoryPanelView: View {
    @Bindable var model: ClipboardHistoryPanelModel
    let onInsert: (ClipboardItem, _ paste: Bool) -> Void
    let onOpenSettings: () -> Void

    @FocusState private var isSearchFocused: Bool

    static let width: CGFloat = 780
    private let bodyHeight: CGFloat = 400
    private let listWidth: CGFloat = 300
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                if !model.store.isEnabled {
                    message(
                        symbol: "pause.circle",
                        title: "Clipboard history is off",
                        detail: "Turn it on to keep what you copy and paste it again later.",
                        button: ("Turn On", { model.store.isEnabled = true })
                    )
                } else if model.store.items.isEmpty {
                    message(
                        symbol: "doc.on.clipboard",
                        title: "Nothing copied yet",
                        detail: "Copy some text, a link, an image or a file and it shows up here."
                    )
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
            TextField("Search clipboard history…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
            Menu {
                Button("All Types") { model.kindFilter = nil }
                Divider()
                ForEach(ClipboardItem.Kind.allCases, id: \.self) { kind in
                    Button(kind.pluralTitle) { model.kindFilter = kind }
                }
            } label: {
                Label(model.kindFilter?.pluralTitle ?? "All Types", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // MARK: - List

    private enum Row: Identifiable {
        case header(String)
        case item(ClipboardItem, index: Int)

        var id: String {
            switch self {
            case .header(let title): "header-\(title)"
            case .item(let item, _): item.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var index = 0
        for section in model.sections {
            rows.append(.header(section.title))
            for item in section.items {
                rows.append(.item(item, index: index))
                index += 1
            }
        }
        return rows
    }

    @ViewBuilder
    private var list: some View {
        if model.items.isEmpty {
            Text(model.query.isEmpty ? "No \(model.kindFilter?.pluralTitle.lowercased() ?? "items")" : "No matches for “\(model.query)”")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            switch row {
                            case .header(let title):
                                Text(title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                            case .item(let item, let index):
                                itemRow(item, index: index)
                            }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) {
                    if let selected = model.selectedItem {
                        proxy.scrollTo(selected.id.uuidString)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: ClipboardItem, index: Int) -> some View {
        let isSelected = index == model.selection
        return Button {
            model.selection = index
        } label: {
            HStack(spacing: 10) {
                rowIcon(item)
                    .frame(width: 26, height: 26)
                Text(item.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .opacity(isSelected ? 1 : 0.7)
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
        .simultaneousGesture(TapGesture(count: 2).onEnded { onInsert(item, true) })
    }

    @ViewBuilder
    private func rowIcon(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            if let image = model.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
            } else {
                kindTile(item.kind)
            }
        case .file:
            if let path = item.filePaths.first {
                Image(nsImage: AppIconCache.icon(forPath: path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                kindTile(item.kind)
            }
        case .text, .link:
            kindTile(item.kind)
        }
    }

    private func kindTile(_ kind: ClipboardItem.Kind) -> some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let item = model.selectedItem {
            VStack(spacing: 0) {
                preview(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.4)
                metadata(item)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .text, .link:
            ScrollView {
                Text(item.text)
                    .font(.system(size: 14))
                    .foregroundStyle(item.kind == .link ? Color.accentColor : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
        case .image:
            if let image = model.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .padding(18)
            } else {
                Text("This image is no longer available.")
                    .foregroundStyle(.secondary)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.filePaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(nsImage: AppIconCache.icon(forPath: path))
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                Text(((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
            }
        }
    }

    /// One quiet line: where it came from, when, and how big.
    private func metadata(_ item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            if let bundleId = item.sourceBundleId, let icon = AppIconCache.icon(forBundleId: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(metadataText(item))
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 34)
    }

    private func metadataText(_ item: ClipboardItem) -> String {
        var parts: [String] = []
        if let source = item.sourceName { parts.append(source) }
        parts.append(item.copiedAt.formatted(.relative(presentation: .named)))
        switch item.kind {
        case .text:
            let count = item.text.count
            parts.append("\(count.formatted()) character\(count == 1 ? "" : "s")")
        case .link:
            parts.append("Link")
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { parts.append("\(w) × \(h)") }
        case .file:
            let count = item.filePaths.count
            parts.append("\(count) file\(count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Empty states & footer

    private func message(symbol: String, title: String, detail: String, button: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let button {
                Button(button.0, action: button.1)
                    .hkProminentButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
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
            Spacer()
            if let item = model.selectedItem {
                action(model.targetAppName.map { "Paste to \($0)" } ?? "Paste", keys: ["↩"])
                action("Copy", keys: ["⌘", "↩"])
                action(item.isPinned ? "Unpin" : "Pin", keys: ["⌘", "P"])
                action("Delete", keys: ["⌘", "⌫"])
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

extension ClipboardItem.Kind {
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var pluralTitle: String {
        switch self {
        case .text: "Text"
        case .link: "Links"
        case .image: "Images"
        case .file: "Files"
        }
    }
}
