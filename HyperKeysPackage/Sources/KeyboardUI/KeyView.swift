import EventEngine
import KeyBindings
import SwiftUI

public struct KeyView: View {
    let definition: KeyDefinition
    let binding: KeyBinding?
    let isSelected: Bool
    let isHyperKey: Bool
    let keySize: CGFloat
    let onTap: () -> Void
    let onRemove: (() -> Void)?

    public init(
        definition: KeyDefinition,
        binding: KeyBinding?,
        isSelected: Bool,
        isHyperKey: Bool = false,
        keySize: CGFloat = 48,
        onTap: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.definition = definition
        self.binding = binding
        self.isSelected = isSelected
        self.isHyperKey = isHyperKey
        self.keySize = keySize
        self.onTap = onTap
        self.onRemove = onRemove
    }

    private var backgroundColor: Color {
        if isHyperKey { return .purple.opacity(0.6) }
        if isSelected { return .accentColor.opacity(0.3) }
        if binding != nil { return .accentColor.opacity(0.15) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if binding != nil { return .accentColor.opacity(0.4) }
        return Color(nsColor: .separatorColor)
    }

    // Cell dimensions (the slot this key occupies in the grid)
    private var cellWidth: CGFloat { keySize * definition.width }
    private var cellHeight: CGFloat { keySize * definition.height }

    // Visual key dimensions (inset by 1px on each side for gaps)
    private var keyWidth: CGFloat { cellWidth - 2 }
    private var keyHeight: CGFloat { cellHeight - 2 }

    /// Whether the label is a two-line modifier (e.g. "^\ncontrol", "⌥\noption").
    private var isTwoLineModifier: Bool {
        guard definition.label.contains("\n") else { return false }
        let parts = definition.label.split(separator: "\n", maxSplits: 1)
        return (parts.last?.count ?? 0) > 1
    }

    /// Whether the label is a wide text key (tab, delete, return, shift, caps lock, esc).
    /// Only keys wider than 1.0 with multi-char labels get this treatment.
    private var isTextLabel: Bool {
        !definition.label.contains("\n") && definition.width > 1.0 && definition.label.count > 1
    }

    public var body: some View {
        ZStack {
            if definition.label.contains("\n") {
                let parts = definition.label.split(separator: "\n", maxSplits: 1)
                if isTwoLineModifier {
                    // Modifier key: symbol top-left, text bottom-left
                    VStack(alignment: .leading, spacing: 0) {
                        Text(parts.first ?? "")
                            .font(.system(size: keySize * 0.2, design: .rounded))
                            .foregroundStyle(isHyperKey ? .white.opacity(0.7) : .secondary)
                        Spacer(minLength: 0)
                        Text(parts.last ?? "")
                            .font(.system(size: keySize * 0.15, design: .rounded))
                            .foregroundStyle(isHyperKey ? .white.opacity(0.7) : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    // Number row: shifted char top, main char bottom
                    VStack(spacing: 0) {
                        Text(parts.first ?? "")
                            .font(.system(size: keySize * 0.18, design: .rounded))
                            .foregroundStyle(isHyperKey ? .white.opacity(0.7) : .secondary)
                        Text(parts.last ?? "")
                            .font(.system(size: keySize * 0.24, weight: .medium, design: .rounded))
                            .foregroundStyle(isHyperKey ? .white : .primary)
                    }
                }
            } else if isTextLabel {
                // Text key: right-aligned, smaller text (delete, return, shift, etc.)
                // Exception: "tab" and "caps lock" stay left-aligned
                let alignRight = definition.label != "tab" && definition.label != "caps lock"
                VStack(alignment: alignRight ? .trailing : .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(definition.label)
                        .font(.system(size: keySize * 0.18, weight: .medium, design: .rounded))
                        .foregroundStyle(isHyperKey ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignRight ? .trailing : .leading)
            } else {
                // Single character or symbol: centered
                Text(definition.label)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isHyperKey ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            // Binding label overlay at bottom center
            if let binding {
                VStack {
                    Spacer()
                    Text(actionLabel(binding.action))
                        .font(.system(size: keySize * 0.13))
                        .foregroundStyle(isHyperKey ? .white.opacity(0.7) : .accentColor)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                }
            }
        }
        .frame(width: keyWidth, height: keyHeight)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor, lineWidth: isSelected ? 2 : 0.5))
        .frame(width: cellWidth, height: cellHeight) // outer cell for grid alignment
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            if binding != nil, let onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove Shortcut", systemImage: "trash")
                }
            }
        }
    }

    private var fontSize: CGFloat {
        if definition.height < 1.0 {
            return keySize * 0.18 // smaller font for half-height keys
        }
        if definition.width > 1.3 {
            return keySize * 0.2 // slightly smaller for wide keys with text labels
        }
        return keySize * 0.28
    }

    private var cornerRadius: CGFloat {
        definition.height < 1.0 ? 4 : 6
    }

    private func actionLabel(_ action: BoundAction) -> String {
        switch action {
        case .launchApp(_, let name): name
        case .triggerMenuItem(_, let path): path.last ?? "Menu"
        case .showAppGroup: "Group"
        case .windowAction(let pos): pos.displayName
        case .none: ""
        }
    }
}
