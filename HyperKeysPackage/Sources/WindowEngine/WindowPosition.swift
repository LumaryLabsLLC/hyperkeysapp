import Foundation

public enum WindowPositionCategory: String, CaseIterable, Sendable {
    case halves, quarters, thirds, sixths, fourths, special
}

public enum WindowPosition: String, Codable, CaseIterable, Sendable {
    // Halves
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    // Quarters
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // Thirds
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds
    // Sixths
    case topLeftSixth
    case topCenterSixth
    case topRightSixth
    case bottomLeftSixth
    case bottomCenterSixth
    case bottomRightSixth
    // Fourths
    case firstFourth
    case secondFourth
    case thirdFourth
    case lastFourth
    // Special
    case fullScreen
    case center
    case maximizeHeight
    case maximizeWidth
    case reasonableSize

    public var displayName: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeftQuarter: "Top Left"
        case .topRightQuarter: "Top Right"
        case .bottomLeftQuarter: "Bottom Left"
        case .bottomRightQuarter: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First 2/3"
        case .lastTwoThirds: "Last 2/3"
        case .topLeftSixth: "Top Left 6th"
        case .topCenterSixth: "Top Center 6th"
        case .topRightSixth: "Top Right 6th"
        case .bottomLeftSixth: "Bottom Left 6th"
        case .bottomCenterSixth: "Bottom Center 6th"
        case .bottomRightSixth: "Bottom Right 6th"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .fullScreen: "Full Screen"
        case .center: "Center"
        case .maximizeHeight: "Max Height"
        case .maximizeWidth: "Max Width"
        case .reasonableSize: "Reasonable Size"
        }
    }

    public var category: WindowPositionCategory {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            .quarters
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            .thirds
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            .sixths
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth:
            .fourths
        case .fullScreen, .center, .maximizeHeight, .maximizeWidth, .reasonableSize:
            .special
        }
    }

    /// Unit-coordinate rect for visual tile preview. Nil for display-change positions.
    public var normalizedRect: CGRect? {
        switch self {
        // Halves
        case .leftHalf:         CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:        CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf:          CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf:       CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        // Quarters
        case .topLeftQuarter:     CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRightQuarter:    CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeftQuarter:  CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRightQuarter: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        // Thirds
        case .firstThird:      CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird:     CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .lastThird:       CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .firstTwoThirds:  CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .lastTwoThirds:   CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        // Sixths
        case .topLeftSixth:      CGRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5)
        case .topCenterSixth:    CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 0.5)
        case .topRightSixth:     CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 0.5)
        case .bottomLeftSixth:   CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5)
        case .bottomCenterSixth: CGRect(x: 1.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)
        case .bottomRightSixth:  CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)
        // Fourths
        case .firstFourth:  CGRect(x: 0, y: 0, width: 0.25, height: 1)
        case .secondFourth: CGRect(x: 0.25, y: 0, width: 0.25, height: 1)
        case .thirdFourth:  CGRect(x: 0.5, y: 0, width: 0.25, height: 1)
        case .lastFourth:   CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        // Special
        case .fullScreen:      CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center:          CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
        case .maximizeHeight:  CGRect(x: 0.2, y: 0, width: 0.6, height: 1)
        case .maximizeWidth:   CGRect(x: 0, y: 0.2, width: 1, height: 0.6)
        case .reasonableSize:  CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
        }
    }
}
