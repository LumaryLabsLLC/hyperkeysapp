import Foundation
import WindowEngine

public struct AppGroup: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var appBundleIdentifiers: [String]
    public var windowPositions: [String: WindowPosition]

    enum CodingKeys: String, CodingKey {
        case id, name, appBundleIdentifiers, windowPositions
    }

    public init(
        id: UUID = UUID(),
        name: String,
        appBundleIdentifiers: [String] = [],
        windowPositions: [String: WindowPosition] = [:]
    ) {
        self.id = id
        self.name = name
        self.appBundleIdentifiers = appBundleIdentifiers
        self.windowPositions = windowPositions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        appBundleIdentifiers = try container.decode([String].self, forKey: .appBundleIdentifiers)
        windowPositions = try container.decodeIfPresent([String: WindowPosition].self, forKey: .windowPositions) ?? [:]
    }
}
