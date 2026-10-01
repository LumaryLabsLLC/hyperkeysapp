import AppKit
import KeyBindings
import SwiftUI

// MARK: - Brand

public enum Brand {
    /// The HyperKeys purple, matching the app icon.
    public static let purple = Color(red: 0.55, green: 0.29, blue: 0.97)

    public static let gradient = LinearGradient(
        colors: [Color(red: 0.67, green: 0.42, blue: 1.0), Color(red: 0.46, green: 0.20, blue: 0.90)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    /// A color that resolves differently in light and dark appearances. Values are 0xRRGGBB.
    static func adaptive(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }

    static let cardFill = Color.adaptive(light: 0xFFFFFF, lightAlpha: 0.75, dark: 0xFFFFFF, darkAlpha: 0.045)
    static let cardStroke = Color.adaptive(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.07)
}

// MARK: - Action kinds

/// The four things a shortcut can do, each with a consistent color and symbol.
public enum ActionKind: CaseIterable, Sendable {
    case app, appGroup, window, menu, folder, appSearch, appSwitcher, emojiPicker, snippets, emptyTrash

    public init?(_ action: BoundAction) {
        switch action {
        case .launchApp: self = .app
        case .showAppGroup: self = .appGroup
        case .windowAction: self = .window
        case .triggerMenuItem: self = .menu
        case .appSearch: self = .appSearch
        case .appSwitcher: self = .appSwitcher
        case .emojiPicker: self = .emojiPicker
        case .openFolder: self = .folder
        case .emptyTrash: self = .emptyTrash
        case .snippets: self = .snippets
        case .none: return nil
        }
    }

    public var title: String {
        switch self {
        case .app: "Open App"
        case .appGroup: "Open Apps"
        case .window: "Window Layout"
        case .menu: "Menu Command"
        case .appSearch: "App Search"
        case .appSwitcher: "App Switcher"
        case .emojiPicker: "Emoji & Symbols"
        case .folder: "Open Folder"
        case .snippets: "Snippets"
        case .emptyTrash: "Empty Trash"
        }
    }

    public var symbol: String {
        switch self {
        case .app: "app.fill"
        case .appGroup: "square.stack.fill"
        case .window: "macwindow"
        case .menu: "filemenu.and.selection"
        case .appSearch: "magnifyingglass"
        case .appSwitcher: "square.grid.2x2.fill"
        case .emojiPicker: "face.smiling.inverse"
        case .folder: "folder.fill"
        case .snippets: "text.quote"
        case .emptyTrash: "trash.fill"
        }
    }

    public var color: Color {
        switch self {
        case .app: .blue
        case .appGroup: .teal
        case .window: .green
        case .menu: .orange
        case .appSearch: .pink
        case .appSwitcher: .indigo
        case .emojiPicker: Color(red: 0.98, green: 0.62, blue: 0.1)
        case .folder: .cyan
        case .snippets: .mint
        case .emptyTrash: .gray
        }
    }
}

// MARK: - Liquid Glass with fallbacks

extension View {
    /// Liquid Glass on macOS 26+, a translucent material on earlier systems.
    @ViewBuilder
    public func hkGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.25))
                    }
                }
            }
            .overlay(shape.stroke(Color.cardStroke, lineWidth: 0.5))
        }
    }

    /// Prominent call-to-action button: glass on macOS 26+, bordered prominent before.
    @ViewBuilder
    public func hkProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Secondary button: glass on macOS 26+, bordered before.
    @ViewBuilder
    public func hkButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Quiet grouped surface for content sections, matching grouped forms.
    public func hkCard(cornerRadius: CGFloat = 14) -> some View {
        background(Color.cardFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.cardStroke, lineWidth: 0.5)
            )
    }
}

@available(macOS 26, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

/// Groups nearby glass shapes so they blend and morph together; a no-op before macOS 26.
public struct HKGlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Icon tile

/// A rounded, colored symbol tile like the ones in System Settings.
public struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    public init(symbol: String, color: Color, size: CGFloat = 28) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.mix(with: .white, by: 0.12), color], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: size * 0.26, style: .continuous)
            )
            .shadow(color: color.opacity(0.25), radius: 1.5, y: 1)
    }
}
