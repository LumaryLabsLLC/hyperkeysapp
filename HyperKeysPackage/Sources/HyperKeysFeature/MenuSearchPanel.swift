import AppKit
import ContextEngine
import KeyBindings
import KeyboardUI
import SwiftUI

// MARK: - Model

/// A menu command you can run, e.g. View › Developer › Developer Tools.
struct MenuCommandItem: Identifiable, Equatable, Sendable {
    let title: String
    let path: [String]
    let shortcut: String?

    var id: String { path.joined(separator: "\u{1F}") }

    /// "View › Developer", the menus it sits in.
    var location: String { path.dropLast().joined(separator: " › ") }
}

@MainActor
@Observable
final class MenuSearchModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    private(set) var focusRequest = 0
    private(set) var items: [MenuCommandItem] = []
    private(set) var isLoading = false
    private(set) var appName: String?
    private(set) var appIcon: NSImage?
    @ObservationIgnored private(set) var appPID: pid_t?
    @ObservationIgnored private var all: [MenuCommandItem] = []
    @ObservationIgnored private var loadID = UUID()

    func requestFocus() {
        focusRequest += 1
    }

    var selectedItem: MenuCommandItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    /// Reads the app's menus in the background; big apps can take a moment.
    func load(for app: NSRunningApplication?) {
        query = ""
        selection = 0
        all = []
        items = []
        appName = app?.localizedName
        appIcon = app?.icon
        appPID = app?.processIdentifier
        requestFocus()
        guard let pid = appPID else { return }

        isLoading = true
        let id = UUID()
        loadID = id
        Task {
            let menus = await Task.detached(priority: .userInitiated) {
                MenuBarReader.readMenuItems(forPID: pid)
            }.value
            guard loadID == id else { return }
            all = Self.commands(from: menus)
            isLoading = false
            rebuild()
        }
    }

    /// Enabled items that do something, in menu order — minus the app menu's Services submenu,
    /// which lists other apps' services rather than this app's commands.
    static func commands(from menus: [MenuItemInfo]) -> [MenuCommandItem] {
        menus.flatMap(\.leaves)
            .filter { $0.isEnabled && $0.path.count > 1 && !(menus.first?.title == $0.path[0] && $0.path.count > 2 && $0.path[1] == "Services") }
            .map { MenuCommandItem(title: $0.title, path: $0.path, shortcut: $0.shortcut) }
    }

    func setForTesting(_ commands: [MenuCommandItem]) {
        all = commands
        rebuild()
    }

    func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            items = all
            return
        }
        items = all.compactMap { item -> (MenuCommandItem, Int)? in
            if let score = AppSearchModel.score(item.title.lowercased(), query: needle) {
                return (item, score + 100)
            }
            // Also match the menus it lives in ("view dev" finds Developer Tools).
            let full = item.path.joined(separator: " ").lowercased()
            if let score = AppSearchModel.score(full, query: needle) {
                return (item, score)
            }
            return nil
        }
        .enumerated()
        .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
        .map(\.element.0)
    }
}

// MARK: - Controller

/// Raycast-style menu search: type part of a menu command and press Return to run it.
@MainActor
public final class MenuSearchController {
    public static let shared = MenuSearchController()

    let model = MenuSearchModel()
    private var host: FloatingPanelHost?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    public func warmUp() {
        _ = makeHostIfNeeded()
    }

    /// Searches the menus of `app`, or of the app in front.
    public func show(returningTo app: NSRunningApplication? = nil) {
        let target = app ?? NSWorkspace.shared.frontmostApplication
        let host = makeHostIfNeeded()
        model.load(for: target)
        host.show(returningTo: target)
        DispatchQueue.main.async { [model] in
            model.requestFocus()
        }
    }

    public func hide() {
        host?.hide(restoringFocus: true)
    }

    func run(_ item: MenuCommandItem) {
        guard let pid = model.appPID else { return }
        host?.hide(restoringFocus: true)
        // Let the app become active again before pressing its menu item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !MenuBarReader.triggerMenuItem(forPID: pid, path: item.path) {
                NSSound.beep()
            }
        }
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = MenuSearchPanelView(model: model, onRun: { [weak self] item in self?.run(item) })
        let host = FloatingPanelHost(width: MenuSearchPanelView.width, rootView: root)
        host.topFraction = 0.18
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 53: // escape
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 125: model.moveSelection(by: 1); return true
        case 126: model.moveSelection(by: -1); return true
        case 36, 76: // return, enter
            if let item = model.selectedItem {
                run(item)
            }
            return true
        default:
            break
        }
        if flags == .control, characters == "n" {
            model.moveSelection(by: 1)
            return true
        }
        if flags == .control, characters == "p" {
            model.moveSelection(by: -1)
            return true
        }
        return false
    }
}

// MARK: - View

struct MenuSearchPanelView: View {
    @Bindable var model: MenuSearchModel
    let onRun: (MenuCommandItem) -> Void

    @FocusState private var isSearchFocused: Bool

    static let width: CGFloat = 720
    private let bodyHeight: CGFloat = 400
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

    private var header: some View {
        HStack(spacing: 12) {
            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            TextField(model.appName.map { "Search menu items in \($0)…" } ?? "Search menu items…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    @ViewBuilder
    private var list: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading \(model.appName ?? "the app")'s menus…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Text(model.query.isEmpty ? "\(model.appName ?? "This app") has no menu items HyperKeys can read." : "No menu items match “\(model.query)”")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == model.selection)
                                .onTapGesture { model.selection = index }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onRun(item) })
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) {
                    if let selected = model.selectedItem {
                        proxy.scrollTo(selected.id)
                    }
                }
            }
        }
    }

    private func row(_ item: MenuCommandItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(item.title)
                .font(.system(size: 14))
                .lineLimit(1)
            Text(item.location)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 12)
            if let shortcut = item.shortcut {
                HStack(spacing: 3) {
                    ForEach(Array(shortcut.keycapParts.enumerated()), id: \.offset) { _, part in
                        KeycapChip(part, height: 18)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
        )
        .contentShape(.rect)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: ActionKind.menuSearch.symbol)
                    .foregroundStyle(ActionKind.menuSearch.color)
                Text("Search Menu Items")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            Spacer()
            if model.selectedItem != nil {
                HStack(spacing: 5) {
                    Text("Run")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    KeycapChip("↩", height: 18)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }
}

private extension String {
    /// "⇧⌘N" → ["⇧", "⌘", "N"]; "⌘F12" → ["⌘", "F12"].
    var keycapParts: [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var parts: [String] = []
        var rest = Substring(self)
        while let first = rest.first, modifiers.contains(first) {
            parts.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }
}
