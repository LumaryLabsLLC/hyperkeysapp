import Foundation

public struct AppGroup: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var appBundleIdentifiers: [String]

    public init(id: UUID = UUID(), name: String, appBundleIdentifiers: [String] = []) {
        self.id = id
        self.name = name
        self.appBundleIdentifiers = appBundleIdentifiers
    }
}
