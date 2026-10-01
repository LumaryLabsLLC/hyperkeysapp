import AppKit
import EventEngine
import KeyBindings
import SwiftUI

/// What a key on the on-screen keyboard represents.
public enum KeyRole: Equatable {
    /// Modifiers, fn, esc, power — shown for realism, not assignable.
    case inert
    /// Assignable, nothing bound yet.
    case available
    case bound(BindingPresentation)
    /// The user's hyper key.
    case hyper

    var isInteractive: Bool {
        switch self {
        case .available, .bound: true
        case .inert, .hyper: false
        }
    }
}

/// A single keycap on the on-screen keyboard.
struct KeyView: View {
    let definition: KeyDefinition
    let role: KeyRole
    let keySize: CGFloat
    let isEditing: Bool
    /// True while the physical hyper key is held (only meaningful for the hyper key).
    let isPressed: Bool
    /// Changes whenever this key's shortcut fires, to flash it.
    let flashTrigger: Int
    let onTap: () -> Void

    @State private var isHovered = false

    private var cellWidth: CGFloat { keySize * definition.width }
    private var cellHeight: CGFloat { keySize * definition.height }
    private var gap: CGFloat { max(2.5, keySize * 0.075) }
    private var capWidth: CGFloat { cellWidth - gap }
    private var capHeight: CGFloat { cellHeight - gap }
    private var isHalfHeight: Bool { definition.height < 1 }
    private var radius: CGFloat { keySize * (isHalfHeight ? 0.11 : 0.14) }

    var body: some View {
        Button(action: onTap) {
            keycap
        }
        .buttonStyle(KeycapPressStyle())
        .disabled(!role.isInteractive)
        .frame(width: cellWidth, height: cellHeight)
        .onHover { hovering in
            guard role.isInteractive else { return }
            withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
        }
        .help(helpText)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Keycap

    private var keycap: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let flashColor = flashColor

        return ZStack {
            shape.fill(baseFill)

            if case .bound(let presentation) = role {
                shape.fill(presentation.kind.color.opacity(0.17))
            }
            if isHovered {
                shape.fill(Color.primary.opacity(0.06))
            }

            legend
                .padding(.horizontal, keySize * 0.12)
                .padding(.vertical, isHalfHeight ? 0 : keySize * 0.09)

            if isHovered, role == .available, !isHalfHeight {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: keySize * 0.2))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(keySize * 0.07)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: capWidth, height: capHeight)
        .overlay {
            // Top-edge highlight that sells the keycap depth.
            shape.strokeBorder(KeycapPalette.highlight, lineWidth: 0.75)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
        }
        .overlay {
            if case .bound(let presentation) = role {
                shape.strokeBorder(presentation.kind.color.opacity(0.55), lineWidth: 1)
            }
        }
        .overlay {
            if isEditing {
                shape.inset(by: -2.5).stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: flashTrigger) { content, glow in
            content
                .overlay(shape.fill(flashColor.opacity(glow * 0.45)))
                .scaleEffect(1 - glow * 0.05)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.07)
                SpringKeyframe(0.0, duration: 0.45)
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1)
        .shadow(color: role == .hyper ? Brand.purple.opacity(isPressed ? 0.7 : 0.35) : .clear, radius: isPressed ? 10 : 5)
        .shadow(color: KeycapPalette.edge, radius: 0, y: keySize * 0.03)
        .shadow(color: .black.opacity(0.14), radius: keySize * 0.04, y: keySize * 0.03)
        .animation(.snappy(duration: 0.18), value: isPressed)
    }

    private var baseFill: AnyShapeStyle {
        switch role {
        case .hyper:
            AnyShapeStyle(Brand.gradient)
        case .inert:
            AnyShapeStyle(LinearGradient(colors: [KeycapPalette.inertTop, KeycapPalette.inertBottom], startPoint: .top, endPoint: .bottom))
        case .available, .bound:
            AnyShapeStyle(LinearGradient(colors: [KeycapPalette.top, KeycapPalette.bottom], startPoint: .top, endPoint: .bottom))
        }
    }

    private var flashColor: Color {
        if case .bound(let presentation) = role { return presentation.kind.color }
        return .accentColor
    }

    // MARK: - Legends

    private var legendStyle: AnyShapeStyle {
        switch role {
        case .hyper: AnyShapeStyle(.white)
        case .inert: AnyShapeStyle(.tertiary)
        case .available, .bound: AnyShapeStyle(.primary)
        }
    }

    private var secondaryLegendStyle: AnyShapeStyle {
        role == .hyper ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary)
    }

    private var labelParts: [String] {
        definition.label.split(separator: "\n", maxSplits: 1).map(String.init)
    }

    /// Modifier keys like "⌥\noption".
    private var isModifierLabel: Bool {
        labelParts.count == 2 && labelParts[1].count > 1
    }

    /// Wide keys with word labels: tab, caps lock, delete, return, shift, esc.
    private var isWordLabel: Bool {
        labelParts.count == 1 && definition.label.count > 1 && !isHalfHeight && definition.label != "fn"
    }

    @ViewBuilder
    private var legend: some View {
        if case .bound(let presentation) = role {
            boundLegend(presentation)
        } else if role == .hyper {
            hyperLegend
        } else if isModifierLabel {
            VStack(alignment: definition.isRightSide ? .leading : .trailing, spacing: 0) {
                Text(labelParts[0]).font(.system(size: keySize * 0.2))
                Spacer(minLength: 0)
                Text(labelParts[1]).font(.system(size: keySize * 0.15, weight: .medium))
            }
            .foregroundStyle(legendStyle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: definition.isRightSide ? .leading : .trailing)
        } else if isWordLabel {
            Text(definition.label)
                .font(.system(size: keySize * 0.17, weight: .medium))
                .foregroundStyle(legendStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wordAlignment)
        } else if labelParts.count == 2 {
            VStack(spacing: keySize * 0.02) {
                Text(labelParts[0])
                    .font(.system(size: keySize * 0.18, weight: .medium))
                    .foregroundStyle(secondaryLegendStyle)
                Text(labelParts[1])
                    .font(.system(size: keySize * 0.25, weight: .medium))
                    .foregroundStyle(legendStyle)
            }
        } else {
            Text(definition.label)
                .font(.system(size: primaryFontSize, weight: .medium))
                .foregroundStyle(legendStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var wordAlignment: Alignment {
        switch definition.label {
        case "tab", "caps lock", "esc": .bottomLeading
        case "shift": definition.isRightSide ? .bottomTrailing : .bottomLeading
        default: .bottomTrailing
        }
    }

    private var primaryFontSize: CGFloat {
        if isHalfHeight { return keySize * 0.19 }
        if definition.label.count > 1 { return keySize * 0.22 }
        return keySize * 0.3
    }

    /// Short legend used in the corner of a bound key ("T", "1", "⇥").
    private var compactLabel: String {
        if let keyCode = definition.keyCode, isWordLabel || definition.label.isEmpty {
            return keyCode == .space ? "space" : definition.label
        }
        return labelParts.last ?? definition.label
    }

    @ViewBuilder
    private func boundLegend(_ presentation: BindingPresentation) -> some View {
        if isHalfHeight {
            HStack(spacing: keySize * 0.06) {
                Text(compactLabel)
                    .font(.system(size: keySize * 0.15, weight: .semibold))
                    .foregroundStyle(.secondary)
                boundContent(presentation, size: capHeight * 0.66)
            }
        } else {
            ZStack(alignment: .topLeading) {
                Text(compactLabel)
                    .font(.system(size: keySize * (compactLabel.count > 1 ? 0.15 : 0.2), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                boundContent(presentation, size: keySize * 0.44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, keySize * 0.16)
            }
        }
    }

    @ViewBuilder
    private func boundContent(_ presentation: BindingPresentation, size: CGFloat) -> some View {
        switch presentation.kind {
        case .app, .appGroup, .folder:
            AppIconStack(icons: presentation.icons, size: size)
        case .appSearch, .appSwitcher, .emojiPicker, .snippets, .emptyTrash:
            Image(systemName: presentation.kind.symbol)
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundStyle(presentation.kind.color)
        case .window:
            if let position = presentation.windowPosition {
                WindowLayoutGlyph(position: position, color: ActionKind.window.color)
                    .frame(width: size * 1.2, height: size * 0.8)
            }
        case .menu:
            if isHalfHeight {
                Image(systemName: ActionKind.menu.symbol)
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(ActionKind.menu.color)
            } else {
                Text(presentation.title)
                    .font(.system(size: keySize * 0.135, weight: .semibold))
                    .foregroundStyle(ActionKind.menu.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var hyperLegend: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text("HYPER")
            } icon: {
                Image(systemName: "sparkle")
            }
            .labelStyle(SparkleLabelStyle())
            .font(.system(size: keySize * 0.13, weight: .heavy))
            .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text(definition.label.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: keySize * 0.17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Accessibility & help

    private var accessibilityName: String {
        if let keyCode = definition.keyCode { return keyCode.name }
        return definition.label.replacingOccurrences(of: "\n", with: " ")
    }

    private var accessibilityValue: String {
        switch role {
        case .bound(let presentation): presentation.summary
        case .available: "Not assigned"
        case .hyper: "Hyper key"
        case .inert: ""
        }
    }

    private var helpText: String {
        switch role {
        case .bound(let presentation): "\(presentation.summary) — click to change"
        case .available: "Click to assign a shortcut"
        case .hyper: "Your Hyper Key — change it in the Hyper Key section"
        case .inert: ""
        }
    }
}

private struct SparkleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

private struct KeycapPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
