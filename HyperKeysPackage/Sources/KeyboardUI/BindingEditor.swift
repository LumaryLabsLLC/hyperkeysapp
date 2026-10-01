import EventEngine
import KeyBindings
import SwiftUI
import WindowEngine

/// Popover editor for a single Hyper + key shortcut.
/// Picking anything assigns it immediately; closing (Esc / click outside) never changes the binding.
public struct BindingEditor: View {
    enum Tab: String, CaseIterable, Identifiable {
        case app = "App"
        case window = "Window"
        case folder = "Folder"
        case menu = "Menu"

        var id: Self { self }
    }

    let keyCode: KeyCode
    @Bindable var bindingStore: BindingStore
    let onClose: () -> Void

    @State private var tab: Tab

    public init(keyCode: KeyCode, bindingStore: BindingStore, onClose: @escaping () -> Void) {
        self.keyCode = keyCode
        self.bindingStore = bindingStore
        self.onClose = onClose

        let initialTab: Tab = switch bindingStore.binding(for: keyCode).flatMap({ ActionKind($0.action) }) {
        case .window: .window
        case .menu: .menu
        case .folder: .folder
        default: .app
        }
        _tab = State(initialValue: initialTab)
    }

    private var currentAction: BoundAction? {
        bindingStore.binding(for: keyCode)?.action
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)

            Picker("Action type", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch tab {
                case .app:
                    AppActionPicker(currentAction: currentAction, onAssign: assign)
                case .window:
                    WindowActionPicker(currentAction: currentAction, onAssign: assign)
                case .folder:
                    FolderActionPicker(currentAction: currentAction, onAssign: assign)
                case .menu:
                    MenuActionPicker(currentAction: currentAction, onAssign: assign)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 390, height: 520)
    }

    private var header: some View {
        let presentation = currentAction.flatMap(BindingPresentation.init)

        return HStack(spacing: 12) {
            HyperComboView(hyperKey: bindingStore.hyperKeyCode, key: keyCode, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation?.title ?? "No shortcut yet")
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if let presentation {
                        Label(presentation.kind == .menu ? presentation.subtitle : presentation.kind.title, systemImage: presentation.kind.symbol)
                            .foregroundStyle(presentation.kind.color)
                    } else {
                        Text("Pick an app, window layout, folder or command")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if presentation != nil {
                Button("Remove Shortcut", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy) {
                        bindingStore.clearBinding(for: keyCode)
                    }
                }
                .labelStyle(.iconOnly)
                .hkButtonStyle()
                .help("Remove this shortcut")
            }
        }
    }

    private func assign(_ action: BoundAction) {
        bindingStore.assign(action, to: keyCode)
        onClose()
    }
}

// MARK: - Shared picker pieces

/// A hoverable list row used by all three pickers.
struct PickerRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var isSelected = false
    let action: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovered ? Color.primary.opacity(0.07) : .clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: 8, style: .continuous))
        .task {
            // Popovers need a beat before they accept focus.
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
    }
}

struct PickerSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// Centered empty / loading message for picker content areas.
struct PickerMessage: View {
    let symbol: String
    let title: String
    var message: String?
    var isLoading = false

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.callout.weight(.medium))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
