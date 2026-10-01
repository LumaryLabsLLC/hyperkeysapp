import AppKit
import EventEngine
import KeyBindings
import SwiftUI

/// The interactive on-screen keyboard. Click a key — or press it on the physical keyboard —
/// to open its shortcut editor in a popover anchored to the key.
public struct KeyboardView: View {
    @Bindable var bindingStore: BindingStore
    @Binding var editingKey: KeyCode?
    let status: HyperKeyStatus?

    @State private var keySize: CGFloat = 48
    @State private var typeMonitor: Any?

    private let deckPadding: CGFloat = 14
    private let unitsWide: CGFloat = 14.5

    public init(bindingStore: BindingStore, editingKey: Binding<KeyCode?>, status: HyperKeyStatus? = nil) {
        self.bindingStore = bindingStore
        self._editingKey = editingKey
        self.status = status
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Measures the width on offer without being influenced by the keyboard's own size,
            // so the keyboard can shrink as well as grow.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    let fitted = ((width - deckPadding * 2) / unitsWide).rounded(.down)
                    keySize = min(60, max(30, fitted))
                }

            keyboard
                .padding(deckPadding)
                .hkGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear(perform: installTypeToSelect)
        .onDisappear(perform: removeTypeToSelect)
    }

    private var keyboard: some View {
        VStack(spacing: 0) {
            ForEach(Array(KeyboardLayout.macbookProRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if key.isSpacer {
                            Color.clear.frame(width: keySize * key.width, height: keySize * key.height)
                        } else {
                            keyView(for: key)
                        }
                    }
                }
            }

            // Bottom row with the inverted-T arrow cluster
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(KeyboardLayout.bottomRow.enumerated()), id: \.offset) { _, key in
                    keyView(for: key)
                }
                keyView(for: KeyboardLayout.arrowLeft)
                VStack(spacing: 0) {
                    keyView(for: KeyboardLayout.arrowUp)
                    keyView(for: KeyboardLayout.arrowDown)
                }
                keyView(for: KeyboardLayout.arrowRight)
            }
        }
        .frame(width: keySize * unitsWide)
    }

    @ViewBuilder
    private func keyView(for key: KeyDefinition) -> some View {
        let role = role(for: key)
        let view = KeyView(
            definition: key,
            role: role,
            keySize: keySize,
            isEditing: key.keyCode != nil && key.keyCode == editingKey,
            isPressed: role == .hyper && (status?.isHyperKeyDown ?? false),
            flashTrigger: key.keyCode.flatMap { status?.triggerCounts[$0] } ?? 0,
            onTap: {
                if let keyCode = key.keyCode { editingKey = keyCode }
            }
        )

        if let keyCode = key.keyCode, role.isInteractive {
            view.popover(isPresented: editorPresented(for: keyCode), arrowEdge: .bottom) {
                BindingEditor(keyCode: keyCode, bindingStore: bindingStore) {
                    editingKey = nil
                }
            }
        } else {
            view
        }
    }

    private func role(for key: KeyDefinition) -> KeyRole {
        guard let keyCode = key.keyCode else { return .inert }
        if keyCode == bindingStore.hyperKeyCode { return .hyper }
        guard keyCode.isAssignable(hyperKey: bindingStore.hyperKeyCode) else { return .inert }
        if let binding = bindingStore.binding(for: keyCode), let presentation = BindingPresentation(binding.action) {
            return .bound(presentation)
        }
        return .available
    }

    private func editorPresented(for keyCode: KeyCode) -> Binding<Bool> {
        Binding(
            get: { editingKey == keyCode },
            set: { isPresented in
                if !isPresented, editingKey == keyCode { editingKey = nil }
            }
        )
    }

    // MARK: - Type to select

    /// Keys that keep their usual meaning (focus movement, button activation, list navigation).
    private static let navigationKeys: Set<KeyCode> = [
        .tab, .space, .returnKey, .delete, .forwardDelete, .leftArrow, .rightArrow, .upArrow, .downArrow,
    ]

    private func installTypeToSelect() {
        guard typeMonitor == nil else { return }
        let store = bindingStore
        let editing = $editingKey
        typeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard editing.wrappedValue == nil,
                      KeyRecordingCenter.shared.activeID == nil,
                      !event.isARepeat,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let window = event.window, window.attachedSheet == nil,
                      !(window.firstResponder is NSText),
                      let key = KeyCode(rawValue: event.keyCode),
                      !Self.navigationKeys.contains(key),
                      key.isAssignable(hyperKey: store.hyperKeyCode) else { return false }
                editing.wrappedValue = key
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeTypeToSelect() {
        if let typeMonitor {
            NSEvent.removeMonitor(typeMonitor)
        }
        typeMonitor = nil
    }
}
