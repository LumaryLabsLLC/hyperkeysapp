import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @Bindable var bindingStore: BindingStore

    @State private var gap = WindowGap.load()
    @AppStorage(Preferences.cycleHalves) private var cycleHalves = false

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .windows,
                subtitle: "Snap the window you're using into place from any app. Click Record next to a layout, then press a key to use with Hyper, or any shortcut like ⌃⌥←."
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
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 16)
        }
        .padding(.bottom, 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Toggle(isOn: $cycleHalves) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat Left or Right Half to change its width")
                    Text("Each press goes from ½ to ⅔ to ⅓ of the screen, then back to ½.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .hkCard()
        .onChange(of: gap) { _, newValue in
            newValue.save()
        }
    }

    // MARK: - Layout cards

    private func layoutCard(for position: WindowPosition) -> some View {
        let action = BoundAction.windowAction(position)
        let hasShortcut = bindingStore.keyCode(for: action) != nil || GlobalShortcutStore.shared.shortcut(for: action) != nil

        return HStack(spacing: 14) {
            WindowLayoutGlyph(position: position, color: ActionKind.window.color, isActive: hasShortcut)
                .frame(width: 56, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text(position.displayName)
                    .font(.callout.weight(.medium))
                ActionShortcutField(action: action, bindingStore: bindingStore)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .hkCard(cornerRadius: 12)
    }
}
