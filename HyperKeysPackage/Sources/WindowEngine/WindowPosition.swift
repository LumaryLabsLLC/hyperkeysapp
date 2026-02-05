import Foundation

public enum WindowPosition: String, Codable, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case fullScreen
    case center
    case nextScreen
    case previousScreen

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
        case .fullScreen: "Full Screen"
        case .center: "Center"
        case .nextScreen: "Next Screen"
        case .previousScreen: "Previous Screen"
        }
    }
}
