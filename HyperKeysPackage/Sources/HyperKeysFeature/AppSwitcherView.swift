import AppKit
import AppSwitcher
import KeyboardUI
import Shared
import SwiftUI

/// Minimal grid of open apps. Apps with several windows are stacked into one tile;
/// opening a stack (click / Return) or searching shows the individual windows.
struct AppSwitcherView: View {
    @Bindable var model: AppSwitcherModel
    let onActivate: (SwitcherItem) -> Void
    let onBack: () -> Void

    @FocusState private var isFilterFocused: Bool

    static let tileSize = CGSize(width: 112, height: 104)
    static let spacing: CGFloat = 4
    static let gridPadding: CGFloat = 10
    /// Exactly wide enough for the grid, so there's no dead space at the sides.
    static var gridWidth: CGFloat {
        let columns = CGFloat(AppSwitcherModel.columns)
        return columns * tileSize.width + (columns - 1) * spacing + gridPadding * 2
    }

    private let iconSize: CGFloat = 64
    private let maxVisibleRows = 4
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            if !model.isHoldMode {
                header
                Divider().opacity(0.5)
            }
            if model.items.isEmpty {
                Text(model.query.isEmpty ? "No open apps" : "Nothing matches “\(model.query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
            } else {
                grid
            }
        }
        .frame(width: Self.gridWidth)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
    }

    // MARK: - Header

    /// Stay-open header: key hints, the opened stack's app, or the "/" filter field.
    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            if model.isHinting {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Type a letter to switch")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Spacer()
                hint(["esc"], "cancel")
            } else if model.isFiltering {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Filter apps and windows", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFilterFocused)
                    .onAppear {
                        // The field is created by the same update that asks for focus,
                        // so focus it on the next turn, once it's actually in the window.
                        DispatchQueue.main.async {
                            isFilterFocused = true
                        }
                    }
            } else if let app = model.expandedApp {
                Button("All Apps", systemImage: "chevron.left", action: onBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(app.name)
                    .font(.system(size: 15, weight: .semibold))
                Text("\(model.items.count) windows")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                hint(["esc"], "back")
                hint(["↩"], "switch")
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Switch to…")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Spacer()
                hint(["h", "j", "k", "l"], "move")
                hint(["f"], "jump")
                hint(["/"], "filter")
                hint(["↩"], "open")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { KeycapChip($0, height: 17) }
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 4)
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(Self.tileSize.width), spacing: Self.spacing), count: AppSwitcherModel.columns)
        let rows = (model.items.count + AppSwitcherModel.columns - 1) / AppSwitcherModel.columns
        let visibleRows = min(rows, maxVisibleRows)

        let hintLabels = model.isHinting ? model.hintLabels : []

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        tile(item, isSelected: index == model.selection)
                            .overlay(alignment: .topLeading) {
                                if hintLabels.indices.contains(index) {
                                    HintBadge(label: hintLabels[index], typed: model.hintInput)
                                        .padding(6)
                                }
                            }
                            .id(item.id)
                    }
                }
                .padding(Self.gridPadding)
            }
            .scrollIndicators(.never)
            .frame(height: CGFloat(visibleRows) * (Self.tileSize.height + Self.spacing) - Self.spacing + Self.gridPadding * 2)
            .onChange(of: model.selection) {
                if let selected = model.selectedItem {
                    proxy.scrollTo(selected.id)
                }
            }
        }
    }

    private func tile(_ item: SwitcherItem, isSelected: Bool) -> some View {
        let (title, subtitle) = labels(for: item)

        return Button {
            onActivate(item)
        } label: {
            VStack(spacing: 4) {
                icon(for: item)
                    .frame(width: iconSize, height: iconSize)
                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.12) : .clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(item.isStack ? "\(item.app.name) — \(item.windows.count) windows" : (item.frontWindow.windowTitle ?? item.app.name))
    }

    @ViewBuilder
    private func icon(for item: SwitcherItem) -> some View {
        let entry = item.frontWindow
        if let image = item.app.icon {
            ZStack {
                if item.isStack {
                    // A fanned "deck" behind the icon says "several windows".
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: iconSize * 0.84, height: iconSize * 0.84)
                        .opacity(0.35)
                        .offset(x: 9, y: -6)
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: iconSize * 0.92, height: iconSize * 0.92)
                        .opacity(0.6)
                        .offset(x: 5, y: -3)
                }
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    // Dimmed when there's no window to bring back (minimized, or none open).
                    .opacity(entry.isMinimized ? 0.55 : (entry.windowCountForApp == 0 ? 0.7 : 1))
            }
            .overlay(alignment: .topTrailing) {
                if item.isStack {
                    Text("\(item.windows.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Brand.purple, in: .circle)
                        .offset(x: 8, y: -6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if entry.isMinimized, !item.isStack {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.secondary, in: .circle)
                }
            }
        }
    }

    /// Stacks show "n windows"; inside an opened stack the window title leads.
    private func labels(for item: SwitcherItem) -> (String, String) {
        if item.isStack {
            return (item.app.name, "\(item.windows.count) windows")
        }
        let entry = item.frontWindow
        let windowTitle = cleanTitle(for: entry)
        if model.isExpanded {
            return (windowTitle ?? entry.app.name, entry.isMinimized ? "Minimized" : " ")
        }
        return (entry.app.name, windowTitle ?? (entry.isMinimized ? "Minimized" : " "))
    }

    /// The window title without a trailing " - AppName", or nil when it adds nothing.
    private func cleanTitle(for entry: OpenWindowEntry) -> String? {
        let name = entry.app.name
        var title = entry.windowTitle ?? ""
        // "#general - Discord" → "#general"
        for separator in [" - ", " — ", " – "] where title.hasSuffix(separator + name) {
            title = String(title.dropLast((separator + name).count))
        }
        return title.isEmpty || title == name ? nil : title
    }
}

/// Vimium-style jump label. Typed letters dim; labels that no longer match fade out.
private struct HintBadge: View {
    let label: String
    let typed: String

    var body: some View {
        let matches = label.hasPrefix(typed)
        let typedCount = matches ? typed.count : 0

        HStack(spacing: 0) {
            Text(label.prefix(typedCount).uppercased())
                .foregroundStyle(.black.opacity(0.35))
            Text(label.dropFirst(typedCount).uppercased())
                .foregroundStyle(.black)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .padding(.horizontal, 6)
        .frame(minWidth: 22, minHeight: 22)
        .background(
            LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.45), Color(red: 0.98, green: 0.8, blue: 0.2)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 6, style: .continuous)
        )
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .opacity(matches ? 1 : 0.2)
        .animation(.snappy(duration: 0.12), value: typed)
        .accessibilityLabel("Jump key \(label)")
    }
}

/// Glass surface plus a soft shadow for the floating panels. The window itself has no system
/// shadow (it would trace the rectangular frame), so the shadow is drawn here, only outside the
/// rounded shape so it never tints the glass. The margin gives the shadow room inside the window.
struct FloatingPanelChrome<S: Shape>: ViewModifier {
    static var margin: CGFloat { 36 }
    let shape: S

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content
                    .background(BehindWindowBlur())
                    .clipShape(shape)
            }
        }
        .background {
            OuterShadow(shape: shape, margin: Self.margin)
                .padding(-Self.margin)
        }
        .padding(Self.margin)
    }
}

private struct OuterShadow<S: Shape>: View {
    let shape: S
    let margin: CGFloat

    var body: some View {
        Canvas { context, size in
            let path = shape.path(in: CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin))
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 10))
                layer.fill(path, with: .color(.black))
            }
            // Punch out the shape itself, leaving only the shadow around it.
            context.blendMode = .destinationOut
            context.fill(path, with: .color(.black))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
