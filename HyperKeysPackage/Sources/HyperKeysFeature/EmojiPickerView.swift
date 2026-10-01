import KeyboardUI
import SwiftUI

/// Search field + category menu, a sectioned grid of emoji and symbols, and a footer with
/// the selected item's name and what Return will do.
struct EmojiPickerView: View {
    @Bindable var model: EmojiPickerModel
    let onInsert: (EmojiItem, _ paste: Bool) -> Void

    @FocusState private var isSearchFocused: Bool

    static let tile: CGFloat = 80
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    static var width: CGFloat {
        let columns = CGFloat(EmojiPickerModel.columns)
        return columns * tile + (columns - 1) * spacing + padding * 2
    }

    private let gridHeight: CGFloat = 384
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .frame(height: gridHeight)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
        .onChange(of: model.focusRequest) {
            isSearchFocused = true
        }
        .onChange(of: model.isNavigating) { _, navigating in
            if navigating { isSearchFocused = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search Emoji & Symbols…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
            if model.isNavigating {
                hint(["h", "j", "k", "l"], "move")
                hint(["/"], "search")
                hint(["y"], "copy")
            }
            Menu {
                Button("All Categories") { model.category = nil }
                Divider()
                ForEach(model.categoryNames, id: \.self) { name in
                    Button(name) { model.category = name }
                }
            } label: {
                Label(model.category ?? "All Categories", systemImage: "square.grid.3x3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // MARK: - Grid

    @ViewBuilder
    private var content: some View {
        if !model.isLoaded {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.sections.isEmpty {
            Text("No emoji or symbols match “\(model.query)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.spacing), count: EmojiPickerModel.columns)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        let offset = model.sectionOffsets[sectionIndex]
                        HStack(spacing: 8) {
                            Text(section.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(section.items.count)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, sectionIndex == 0 ? 0 : 10)
                        .padding(.horizontal, 2)

                        LazyVGrid(columns: columns, spacing: Self.spacing) {
                            // Identity is the global position (one id per tile, also the scroll target).
                            ForEach(section.items.indices.map { (offset + $0, section.items[$0]) }, id: \.0) { index, item in
                                tile(item, isSelected: index == model.selection)
                            }
                        }
                    }
                }
                .padding(Self.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) {
                proxy.scrollTo(model.selection)
            }
        }
    }

    private func tile(_ item: EmojiItem, isSelected: Bool) -> some View {
        Button {
            onInsert(item, true)
        } label: {
            Text(item.character)
                // Apple Color Emoji has dedicated artwork for large sizes, so bigger is also crisper.
                .font(.system(size: item.isEmoji ? 46 : 30))
                .foregroundStyle(.primary)
                .frame(width: Self.tile, height: Self.tile)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.14 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Brand.purple, lineWidth: isSelected ? 2 : 0)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(item.displayName)
        .accessibilityLabel(item.displayName)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let item = model.selectedItem {
                Text(item.character)
                    .font(.system(size: 16))
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            action(model.targetAppName.map { "Paste to \($0)" } ?? "Paste", keys: ["↩"])
            action("Copy", keys: ["⌘", "↩"])
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { KeycapChip($0, height: 17) }
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
