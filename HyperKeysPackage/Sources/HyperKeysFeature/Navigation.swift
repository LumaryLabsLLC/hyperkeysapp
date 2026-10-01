import KeyBindings
import KeyboardUI
import SwiftUI

/// Top-level destinations in the sidebar.
enum Pane: String, CaseIterable, Identifiable, Hashable {
    case shortcuts
    case windows
    case appSearch
    case snippets
    case hyperKey
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .shortcuts: "Shortcuts"
        case .windows: "Windows"
        case .appSearch: "Search & Switch"
        case .snippets: "Snippets"
        case .hyperKey: "Hyper Key"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .shortcuts: "keyboard.fill"
        case .windows: "rectangle.split.2x1.fill"
        case .appSearch: "magnifyingglass"
        case .snippets: "text.quote"
        case .hyperKey: "sparkle"
        case .settings: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .shortcuts: .blue
        case .windows: .green
        case .appSearch: .pink
        case .snippets: .mint
        case .hyperKey: Brand.purple
        case .settings: .gray
        }
    }
}

/// Large icon + title + one-line explanation at the top of each page.
struct PageHeader: View {
    let pane: Pane
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: pane.symbol, color: pane.color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Scrollable page container with consistent padding and a readable max width.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Toolbar menu for switching, creating, renaming and deleting profiles.
struct ProfileMenu: View {
    @Bindable var bindingStore: BindingStore

    private enum NamePrompt {
        case new, duplicate, rename
    }

    @State private var namePrompt: NamePrompt?
    @State private var nameDraft = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        Menu {
            Picker("Profile", selection: activeProfile) {
                Text("Default").tag(UUID?.none)
                ForEach(bindingStore.actionGroups) { group in
                    Text(group.name).tag(UUID?.some(group.id))
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("New Profile…", systemImage: "plus") { prompt(.new) }
            Button("Duplicate “\(bindingStore.activeProfileName)”…", systemImage: "plus.square.on.square") { prompt(.duplicate) }
            if let group = bindingStore.activeGroup {
                Button("Rename “\(group.name)”…", systemImage: "pencil") { prompt(.rename) }
                Button("Delete “\(group.name)”…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        } label: {
            Label(bindingStore.activeProfileName, systemImage: "person.crop.rectangle.stack")
                .labelStyle(.titleAndIcon)
        }
        .help("Profiles keep separate sets of shortcuts — switch any time, also from the menu bar")
        .alert(alertTitle, isPresented: isPromptPresented) {
            TextField("Profile name", text: $nameDraft)
            Button(namePrompt == .rename ? "Rename" : "Create", action: commitName)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Delete “\(bindingStore.activeProfileName)”?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Profile", role: .destructive) {
                if let id = bindingStore.activeGroupId { bindingStore.deleteGroup(id) }
            }
        } message: {
            Text("Its shortcuts will be removed. HyperKeys switches back to the Default profile.")
        }
    }

    private var activeProfile: Binding<UUID?> {
        Binding(
            get: { bindingStore.activeGroupId },
            set: { bindingStore.setActiveGroup($0) }
        )
    }

    private var isPromptPresented: Binding<Bool> {
        Binding(
            get: { namePrompt != nil },
            set: { if !$0 { namePrompt = nil } }
        )
    }

    private var alertTitle: String {
        switch namePrompt {
        case .rename: "Rename Profile"
        case .duplicate: "Duplicate Profile"
        default: "New Profile"
        }
    }

    private var alertMessage: String {
        switch namePrompt {
        case .rename: "Choose a new name."
        case .duplicate: "The new profile starts with a copy of “\(bindingStore.activeProfileName)”’s shortcuts."
        default: "The new profile starts empty and becomes active."
        }
    }

    private func prompt(_ kind: NamePrompt) {
        switch kind {
        case .rename: nameDraft = bindingStore.activeProfileName
        case .duplicate: nameDraft = "\(bindingStore.activeProfileName) Copy"
        case .new: nameDraft = ""
        }
        namePrompt = kind
    }

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let kind = namePrompt else { return }
        switch kind {
        case .new:
            bindingStore.createProfile(named: name, copyingActive: false)
        case .duplicate:
            bindingStore.createProfile(named: name, copyingActive: true)
        case .rename:
            if let id = bindingStore.activeGroupId { bindingStore.renameGroup(id, to: name) }
        }
        namePrompt = nil
    }
}

/// Opens the HyperKeys window from anywhere (floating panels, menu bar), optionally on a given page.
public enum HyperKeysWindow {
    /// Provided by the app layer, which owns the `openWindow` action.
    @MainActor public static var open: (() -> Void)?

    @MainActor
    static func open(on pane: Pane) {
        NavigationRequests.shared.pane = pane
        open?()
    }
}

/// A page the window should switch to the next time it's shown or updated.
@MainActor
@Observable
final class NavigationRequests {
    static let shared = NavigationRequests()
    var pane: Pane?
    /// Ask the Snippets page to open its editor.
    var snippet: SnippetRequest?
}

enum SnippetRequest: Equatable {
    case create
    case edit(UUID)
}
