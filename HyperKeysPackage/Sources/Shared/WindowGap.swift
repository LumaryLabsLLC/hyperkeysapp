import Foundation

public enum WindowGap: String, Codable, CaseIterable, Sendable {
    case none
    case small
    case medium
    case large
    case extraLarge

    public var displayName: String {
        switch self {
        case .none: "None"
        case .small: "Small (4px)"
        case .medium: "Medium (8px)"
        case .large: "Large (12px)"
        case .extraLarge: "Extra Large (16px)"
        }
    }

    public var points: CGFloat {
        switch self {
        case .none: 0
        case .small: 4
        case .medium: 8
        case .large: 12
        case .extraLarge: 16
        }
    }

    public static func load() -> WindowGap {
        (try? Persistence.load(WindowGap.self, from: "windowGap.json")) ?? .none
    }

    public func save() {
        try? Persistence.save(self, to: "windowGap.json")
    }
}
