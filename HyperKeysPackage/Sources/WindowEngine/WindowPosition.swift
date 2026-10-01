import Foundation

public enum WindowPositionCategory: String, CaseIterable, Sendable {
    case halves, quarters, thirds, fourths, sixths, special, move

    public var displayName: String {
        switch self {
        case .halves: "Halves"
        case .quarters: "Quarters"
        case .thirds: "Thirds"
        case .fourths: "Fourths"
        case .sixths: "Sixths"
        case .special: "Other"
        case .move: "Move & Display"
        }
    }

    public var positions: [WindowPosition] {
        WindowPosition.allCases.filter { $0.category == self }
    }
}

public enum WindowPosition: String, Codable, CaseIterable, Sendable {
    // Halves
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case centerHalf
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
    case centerTwoThirds
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
    case firstThreeFourths
    case lastThreeFourths
    // Special
    case fullScreen
    case center
    case maximizeHeight
    case maximizeWidth
    case reasonableSize
    case almostMaximize
    // Moves (keep the window's size, or act on it as a whole)
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case nextDisplay
    case previousDisplay
    case toggleFullScreen
    case restore

    public var displayName: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .centerHalf: "Center Half"
        case .topLeftQuarter: "Top Left"
        case .topRightQuarter: "Top Right"
        case .bottomLeftQuarter: "Bottom Left"
        case .bottomRightQuarter: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First 2/3"
        case .lastTwoThirds: "Last 2/3"
        case .centerTwoThirds: "Center 2/3"
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
        case .firstThreeFourths: "First 3/4"
        case .lastThreeFourths: "Last 3/4"
        case .fullScreen: "Maximize"
        case .center: "Center"
        case .maximizeHeight: "Max Height"
        case .maximizeWidth: "Max Width"
        case .reasonableSize: "Reasonable Size"
        case .almostMaximize: "Almost Maximize"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        case .toggleFullScreen: "Toggle Full Screen"
        case .restore: "Restore"
        }
    }

    /// For moves, which have no area to draw: an SF Symbol instead.
    public var symbol: String? {
        switch self {
        case .moveLeft: "arrow.left.to.line"
        case .moveRight: "arrow.right.to.line"
        case .moveUp: "arrow.up.to.line"
        case .moveDown: "arrow.down.to.line"
        case .nextDisplay: "arrow.right.circle"
        case .previousDisplay: "arrow.left.circle"
        case .toggleFullScreen: "arrow.up.left.and.arrow.down.right"
        case .restore: "arrow.uturn.backward"
        default: nil
        }
    }

    public var category: WindowPositionCategory {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf:
            .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            .quarters
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds, .centerTwoThirds:
            .thirds
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            .sixths
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths:
            .fourths
        case .fullScreen, .almostMaximize, .center, .maximizeHeight, .maximizeWidth, .reasonableSize:
            .special
        case .moveLeft, .moveRight, .moveUp, .moveDown, .nextDisplay, .previousDisplay, .toggleFullScreen, .restore:
            .move
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
        case .centerHalf:       CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
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
        case .centerTwoThirds: CGRect(x: 1.0 / 6, y: 0, width: 2.0 / 3, height: 1)
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
        case .firstThreeFourths: CGRect(x: 0, y: 0, width: 0.75, height: 1)
        case .lastThreeFourths:  CGRect(x: 0.25, y: 0, width: 0.75, height: 1)
        // Special
        case .fullScreen:      CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center:          CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
        case .maximizeHeight:  CGRect(x: 0.2, y: 0, width: 0.6, height: 1)
        case .maximizeWidth:   CGRect(x: 0, y: 0.2, width: 1, height: 0.6)
        case .reasonableSize:  CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
        case .almostMaximize:  CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        case .moveLeft, .moveRight, .moveUp, .moveDown, .nextDisplay, .previousDisplay, .toggleFullScreen, .restore:
            nil
        }
    }
}
