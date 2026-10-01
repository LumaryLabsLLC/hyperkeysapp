import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @Bindable var bindingStore: BindingStore

    @State private var gap = WindowGap.load()
    @State private var conflict: Conflict?

    /// A recorded key that's already used by a different shortcut.
    private struct Conflict {
        let position: WindowPosition
        let keyCode: KeyCode
        let existing: BindingPresentation
    }

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .windows,
                subtitle: "Snap the window you're using into place from any app. Click Record next to a layout, then press the key you want."
            )

            gapCard

            ForEach(WindowPositionCategory.allCases, id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category.displayName)
                        .font(.headline)
                        .padding(.horizontal, 4)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(category.positions, id: \.self) { position in
                            layoutCard(for: position)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            conflictTitle,
            isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
            presenting: conflict
        ) { conflict in
            Button("Use for \(conflict.position.displayName)") {
                assign(conflict.position, to: conflict.keyCode)
            }
            Button("Cancel", role: .cancel) {}
        } message: { conflict in
            Text("It currently does “\(conflict.existing.summary)”. Replace it?")
        }
    }

    // MARK: - Gap

    private var gapCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gap between windows")
                        .font(.headline)
                    Text("Space left around windows when HyperKeys tiles them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Picker("Gap between windows", selection: $gap) {
                    ForEach(WindowGap.allCases, id: \.self) { option in
                        Text(option.shortName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer(minLength: 0)
            GapPreview(gap: gap.points)
                .frame(width: 128, height: 80)
        }
        .padding(16)
        .hkCard()
        .onChange(of: gap) { _, newValue in
            newValue.save()
        }
    }

    // MARK: - Layout cards

    private func layoutCard(for position: WindowPosition) -> some View {
        let keyCode = bindingStore.keyCode(for: .windowAction(position))

        return HStack(spacing: 14) {
            WindowLayoutGlyph(position: position, color: ActionKind.window.color, isActive: keyCode != nil)
                .frame(width: 56, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text(position.displayName)
                    .font(.callout.weight(.medium))
                ShortcutRecorder(
                    keyCode: keyCode,
                    hyperKey: bindingStore.hyperKeyCode,
                    onRecord: { record($0, for: position) },
                    onClear: {
                        if let keyCode { bindingStore.clearBinding(for: keyCode) }
                    }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .hkCard(cornerRadius: 12)
    }

    private func record(_ keyCode: KeyCode, for position: WindowPosition) {
        let action = BoundAction.windowAction(position)
        if let existing = bindingStore.binding(for: keyCode), existing.action != action,
           let presentation = BindingPresentation(existing.action) {
            conflict = Conflict(position: position, keyCode: keyCode, existing: presentation)
            return
        }
        assign(position, to: keyCode)
    }

    private func assign(_ position: WindowPosition, to keyCode: KeyCode) {
        let action = BoundAction.windowAction(position)
        // One key per layout: re-recording moves the shortcut rather than adding a second one.
        if let previous = bindingStore.keyCode(for: action), previous != keyCode {
            bindingStore.clearBinding(for: previous)
        }
        withAnimation(.snappy) {
            bindingStore.assign(action, to: keyCode)
        }
    }

    private var conflictTitle: String {
        guard let conflict else { return "" }
        return "Hyper + \(conflict.keyCode.displayLabel) is already in use"
    }
}
