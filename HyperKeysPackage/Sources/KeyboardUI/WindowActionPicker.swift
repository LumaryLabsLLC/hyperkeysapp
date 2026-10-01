import KeyBindings
import SwiftUI
import WindowEngine

/// Visual grid of window layouts; one click assigns.
struct WindowActionPicker: View {
    let currentAction: BoundAction?
    let onAssign: (BoundAction) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    private var current: WindowPosition? {
        if case .windowAction(let position) = currentAction { return position }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Moves the window you're using into place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(WindowPositionCategory.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        PickerSectionHeader(title: category.displayName)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(category.positions, id: \.self) { position in
                                WindowPositionTile(position: position, isSelected: position == current) {
                                    onAssign(.windowAction(position))
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct WindowPositionTile: View {
    let position: WindowPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                WindowLayoutGlyph(position: position, color: ActionKind.window.color, isActive: isSelected || isHovered)
                    .frame(width: 56, height: 36)
                Text(position.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .top)
            }
            .padding(.top, 8)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? ActionKind.window.color.opacity(0.14) : (isHovered ? Color.primary.opacity(0.06) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? ActionKind.window.color.opacity(0.6) : .clear, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
        }
        .accessibilityLabel(position.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
