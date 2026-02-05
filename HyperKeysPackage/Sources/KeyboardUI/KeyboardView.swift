import EventEngine
import KeyBindings
import SwiftUI

public struct KeyboardView: View {
    @Bindable var bindingStore: BindingStore
    @State private var selectedKeyCode: KeyCode?
    @State private var showingPopover = false

    let keySize: CGFloat

    public init(bindingStore: BindingStore, keySize: CGFloat = 48) {
        self.bindingStore = bindingStore
        self.keySize = keySize
    }

    private var totalWidth: CGFloat { keySize * 14.5 }

    public var body: some View {
        VStack(spacing: 0) {
            // Main rows (function row + letter rows)
            ForEach(Array(KeyboardLayout.macbookProRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        if key.isSpacer {
                            Color.clear
                                .frame(width: keySize * key.width, height: keySize * key.height)
                        } else {
                            keyView(for: key)
                        }
                    }
                }
            }

            // Bottom row with inverted-T arrows
            HStack(spacing: 0) {
                // Modifier keys
                ForEach(Array(KeyboardLayout.bottomRow.enumerated()), id: \.offset) { _, key in
                    keyView(for: key)
                }

                // Inverted-T arrow cluster: left + VStack(up, down) + right
                keyView(for: KeyboardLayout.arrowLeft)
                VStack(spacing: 0) {
                    keyView(for: KeyboardLayout.arrowUp)
                    keyView(for: KeyboardLayout.arrowDown)
                }
                keyView(for: KeyboardLayout.arrowRight)
            }
        }
        .frame(width: totalWidth)
        .clipped()
        .padding(8)
        .onKeyPress(.delete) {
            guard let kc = selectedKeyCode else { return .ignored }
            if bindingStore.binding(for: kc) != nil {
                if let groupId = bindingStore.activeGroupId {
                    bindingStore.removeBindingInGroup(groupId: groupId, keyCode: kc)
                } else {
                    bindingStore.removeBinding(for: kc)
                }
                selectedKeyCode = nil
            }
            return .handled
        }
        .sheet(isPresented: $showingPopover) {
            if let kc = selectedKeyCode {
                BindingPopover(
                    keyCode: kc,
                    bindingStore: bindingStore,
                    onDismiss: { showingPopover = false }
                )
            }
        }
    }

    private func keyView(for key: KeyDefinition) -> some View {
        let kc = key.keyCode
        let isHyper = kc == bindingStore.hyperKeyCode
        let binding = kc.flatMap { isHyper ? nil : bindingStore.binding(for: $0) }

        return KeyView(
            definition: key,
            binding: binding,
            isSelected: kc != nil && kc == selectedKeyCode,
            isHyperKey: isHyper,
            keySize: keySize,
            onTap: {
                if let kc, kc != bindingStore.hyperKeyCode {
                    selectedKeyCode = kc
                    showingPopover = true
                }
            },
            onRemove: (binding != nil && kc != nil) ? {
                if let kc {
                    if let groupId = bindingStore.activeGroupId {
                        bindingStore.removeBindingInGroup(groupId: groupId, keyCode: kc)
                    } else {
                        bindingStore.removeBinding(for: kc)
                    }
                }
            } : nil
        )
    }
}
