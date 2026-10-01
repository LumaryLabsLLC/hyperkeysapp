import SwiftUI
import WindowEngine

/// A miniature screen with the target area of a window layout filled in.
public struct WindowLayoutGlyph: View {
    let position: WindowPosition
    var color: Color = .accentColor
    var isActive = true

    public init(position: WindowPosition, color: Color = .accentColor, isActive: Bool = true) {
        self.position = position
        self.color = color
        self.isActive = isActive
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(size.width, size.height) * 0.16
            let inset = max(1.5, min(size.width, size.height) * 0.08)
            let inner = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.16), lineWidth: 1)

                if let rect = position.normalizedRect {
                    let target = CGRect(
                        x: inner.minX + rect.minX * inner.width,
                        y: inner.minY + rect.minY * inner.height,
                        width: rect.width * inner.width,
                        height: rect.height * inner.height
                    ).insetBy(dx: 0.75, dy: 0.75)

                    RoundedRectangle(cornerRadius: max(1.5, radius * 0.6), style: .continuous)
                        .fill(isActive ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.secondary.opacity(0.55)))
                        .frame(width: target.width, height: target.height)
                        .offset(x: target.minX, y: target.minY)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Two side-by-side windows separated by the configured gap.
public struct GapPreview: View {
    let gap: CGFloat

    public init(gap: CGFloat) {
        self.gap = gap
    }

    public var body: some View {
        let scaled = gap * 0.5
        HStack(spacing: scaled) {
            pane
            VStack(spacing: scaled) {
                pane
                pane
            }
        }
        .padding(scaled)
        .padding(3)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 1))
        .animation(.snappy, value: gap)
        .accessibilityHidden(true)
    }

    private var pane: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(Color.green.gradient)
    }
}
