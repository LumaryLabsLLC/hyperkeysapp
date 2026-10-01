import EventEngine
import SwiftUI

/// Shared keycap surface colors, tuned to read like real keys in both appearances.
enum KeycapPalette {
    static let top = Color.adaptive(light: 0xFFFFFF, dark: 0x3C3C41)
    static let bottom = Color.adaptive(light: 0xF2F2F5, dark: 0x2E2E33)
    static let inertTop = Color.adaptive(light: 0xF4F4F6, dark: 0x2D2D31)
    static let inertBottom = Color.adaptive(light: 0xE9E9EC, dark: 0x252529)
    static let edge = Color.adaptive(light: 0x000000, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.55)
    static let highlight = Color.adaptive(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0xFFFFFF, darkAlpha: 0.09)
}

/// A small inline keycap, used wherever a key is mentioned in text (lists, recorders, headers).
public struct KeycapChip: View {
    public enum Style {
        case standard
        case hyper
    }

    let label: String
    var style: Style = .standard
    var height: CGFloat = 22

    public init(_ label: String, style: Style = .standard, height: CGFloat = 22) {
        self.label = label
        self.style = style
        self.height = height
    }

    public init(_ keyCode: KeyCode, style: Style = .standard, height: CGFloat = 22) {
        self.init(keyCode.displayLabel, style: style, height: height)
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)

        Text(label)
            .font(.system(size: height * (label.count > 2 ? 0.42 : 0.52), weight: .semibold, design: .rounded))
            .foregroundStyle(style == .hyper ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .padding(.horizontal, height * 0.28)
            .frame(minWidth: height, minHeight: height)
            .background {
                switch style {
                case .standard:
                    shape.fill(LinearGradient(colors: [KeycapPalette.top, KeycapPalette.bottom], startPoint: .top, endPoint: .bottom))
                case .hyper:
                    shape.fill(Brand.gradient)
                }
            }
            .overlay(shape.strokeBorder(KeycapPalette.highlight, lineWidth: 0.5).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .shadow(color: KeycapPalette.edge, radius: 0, y: 1)
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }
}

/// "⇪ + T" — the hyper key followed by the combo key.
public struct HyperComboView: View {
    let hyperKey: KeyCode
    let key: KeyCode
    var height: CGFloat = 22

    public init(hyperKey: KeyCode, key: KeyCode, height: CGFloat = 22) {
        self.hyperKey = hyperKey
        self.key = key
        self.height = height
    }

    public var body: some View {
        HStack(spacing: height * 0.2) {
            KeycapChip(hyperKey, style: .hyper, height: height)
            Image(systemName: "plus")
                .font(.system(size: height * 0.36, weight: .bold))
                .foregroundStyle(.tertiary)
            KeycapChip(key, height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hyper plus \(key.name)")
    }
}
