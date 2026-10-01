import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI

/// The shortcut for one action: Hyper + a key, or a regular shortcut like ⇧⌘V. An action has
/// one, so recording either kind replaces the other. Asks before taking keys from something else.
struct ActionShortcutField: View {
    let action: BoundAction
    @Bindable var bindingStore: BindingStore

    @State private var shortcuts = GlobalShortcutStore.shared
    @State private var hotKeys = GlobalHotKeys.shared
    @State private var pending: RecordedShortcut?

    var body: some View {
        let combo = shortcuts.shortcut(for: action)?.combo
        VStack(alignment: .leading, spacing: 4) {
            ShortcutRecorder(
                keyCode: bindingStore.keyCode(for: action),
                combo: combo,
                hyperKey: bindingStore.hyperKeyCode,
                onRecord: record,
                onClear: clear
            )
            if let combo, hotKeys.conflicts.contains(combo) {
                Label("Another app already uses \(combo.displayLabel). Turn it off there, or pick another shortcut.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            pendingTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { shortcut in
            Button("Use for \(BindingPresentation(action)?.title ?? "This")") { apply(shortcut) }
            Button("Cancel", role: .cancel) {}
        } message: { shortcut in
            Text("It currently does “\(currentUse(of: shortcut).flatMap(BindingPresentation.init)?.summary ?? "something else")”. Replace it?")
        }
    }

    private func record(_ shortcut: RecordedShortcut) {
        if let other = currentUse(of: shortcut), other != action {
            pending = shortcut
        } else {
            apply(shortcut)
        }
    }

    private func apply(_ shortcut: RecordedShortcut) {
        withAnimation(.snappy) {
            switch shortcut {
            case .hyper(let key):
                if let previous = bindingStore.keyCode(for: action), previous != key {
                    bindingStore.clearBinding(for: previous)
                }
                if shortcuts.shortcut(for: action) != nil {
                    shortcuts.set(nil, for: action)
                }
                bindingStore.assign(action, to: key)
            case .combo(let combo):
                if let previous = bindingStore.keyCode(for: action) {
                    bindingStore.clearBinding(for: previous)
                }
                shortcuts.set(combo, for: action)
            }
        }
    }

    private func clear() {
        withAnimation(.snappy) {
            if let key = bindingStore.keyCode(for: action) {
                bindingStore.clearBinding(for: key)
            }
            if shortcuts.shortcut(for: action) != nil {
                shortcuts.set(nil, for: action)
            }
        }
    }

    /// What these keys run now, if anything.
    private func currentUse(of shortcut: RecordedShortcut) -> BoundAction? {
        switch shortcut {
        case .hyper(let key): bindingStore.binding(for: key)?.action
        case .combo(let combo): shortcuts.shortcuts.first { $0.combo == combo }?.action
        }
    }

    private var pendingTitle: String {
        switch pending {
        case .hyper(let key): "Hyper + \(key.displayLabel) is already in use"
        case .combo(let combo): "\(combo.displayLabel) is already in use"
        case nil: ""
        }
    }
}
