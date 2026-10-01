import AppKit

/// The menu bar glyph: a keycap with the Hyper sparkle. Drawn as a template image so it
/// adapts to light/dark menu bars, and reflects state at a glance.
public enum MenuBarIcon {
    public enum State: Sendable {
        /// Running and ready.
        case active
        /// The hyper key is being held right now.
        case held
        /// Paused, or missing permissions.
        case inactive
    }

    public static func image(for state: State) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: context, size: rect.size)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = switch state {
        case .active: "HyperKeys"
        case .held: "HyperKeys – Hyper key held"
        case .inactive: "HyperKeys – inactive"
        }
        return image
    }

    static func draw(_ state: State, in context: CGContext, size: CGSize) {
        let lineWidth: CGFloat = 1.5
        let keycap = CGRect(x: 1.5, y: 1, width: size.width - 3, height: size.height - 2)
        let keycapPath = CGPath(roundedRect: keycap.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), cornerWidth: 4, cornerHeight: 4, transform: nil)
        let sparkle = sparklePath(center: CGPoint(x: keycap.midX, y: keycap.midY), radius: 4.6)

        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.round)

        switch state {
        case .active:
            context.addPath(keycapPath)
            context.strokePath()
            context.addPath(sparkle)
            context.fillPath()

        case .held:
            // Solid keycap with the sparkle knocked out.
            let solid = CGPath(roundedRect: keycap, cornerWidth: 4.6, cornerHeight: 4.6, transform: nil)
            context.addPath(solid)
            context.addPath(sparkle)
            context.fillPath(using: .evenOdd)

        case .inactive:
            context.setAlpha(0.45)
            context.addPath(keycapPath)
            context.strokePath()
            context.setLineWidth(1.1)
            context.addPath(sparkle)
            context.strokePath()
        }
    }

    /// Four-pointed star with concave sides.
    private static func sparklePath(center c: CGPoint, radius r: CGFloat) -> CGPath {
        let pinch = r * 0.16
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
        path.closeSubpath()
        return path
    }
}
