import KeyBindings
import KeyboardUI
import Shared
import SwiftUI

/// Filter field + sort, then every app and process with its CPU and memory.
struct KillProcessPanelView: View {
    @Bindable var model: KillProcessModel
    let onKill: (ProcessRow, _ force: Bool) -> Void

    @FocusState private var isSearchFocused: Bool

    static let width: CGFloat = 760
    private let bodyHeight: CGFloat = 420
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            list
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
            TextField("Filter by name…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
            Menu {
                Picker("Sort by", selection: $model.sort) {
                    ForEach(ProcessSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(model.sort.title)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if !model.hasLoaded {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Text("No processes match “\(model.query)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Text("Processes")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(model.totalCount.formatted()) running")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, row in
                            processRow(row, isSelected: index == model.selection)
                                .onTapGesture {
                                    model.hasChosen = true
                                    model.selection = index
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onKill(row, false) })
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) {
                    if let selected = model.selectedRow {
                        proxy.scrollTo(selected.id)
                    }
                }
            }
        }
    }

    private func processRow(_ row: ProcessRow, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            icon(row)
                .frame(width: 26, height: 26)
            Text(row.name)
                .font(.system(size: 14))
                .lineLimit(1)
            if row.processCount > 1 {
                Text("\(row.processCount) processes")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            metric("cpu", String(format: "%.1f%%", row.cpu))
                .frame(width: 84, alignment: .trailing)
            metric("memorychip", row.memoryBytes.formatted(.byteCount(style: .memory)))
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
        )
        .contentShape(.rect)
    }

    @ViewBuilder
    private func icon(_ row: ProcessRow) -> some View {
        if let path = row.appPath {
            Image(nsImage: AppIconCache.icon(forPath: path))
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.quaternary)
                .frame(width: 22, height: 22)
        }
    }

    private func metric(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: ActionKind.killProcess.symbol)
                        .foregroundStyle(ActionKind.killProcess.color)
                    Text("Kill Process")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let row = model.selectedRow {
                action(row.appPath == nil ? "Kill" : "Quit", keys: ["↩"])
                action(row.appPath == nil ? "Force Kill" : "Force Quit", keys: ["⌘", "↩"])
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
