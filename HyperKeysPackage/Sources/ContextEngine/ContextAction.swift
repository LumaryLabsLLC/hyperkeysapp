import Foundation

public struct ContextAction: Codable, Sendable {
    public let appBundleId: String
    public let menuPath: [String]

    public init(appBundleId: String, menuPath: [String]) {
        self.appBundleId = appBundleId
        self.menuPath = menuPath
    }
}
