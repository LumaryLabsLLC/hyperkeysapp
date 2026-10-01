import Foundation
import Shared

/// In-memory, observable cache of saved app groups (`appGroups.json`).
@MainActor
@Observable
public final class AppGroupStore {
    public static let shared = AppGroupStore()

    public private(set) var groups: [AppGroup] = []
    /// Called after the user changes a group, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?
    private let file = "appGroups.json"

    public init() {
        reload()
    }

    public func reload() {
        groups = (try? Persistence.load([AppGroup].self, from: file)) ?? []
    }

    public func group(id: UUID) -> AppGroup? {
        groups.first { $0.id == id }
    }

    /// Inserts the group, or replaces the stored group with the same id.
    public func upsert(_ group: AppGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
        } else {
            groups.append(group)
        }
        try? Persistence.save(groups, to: file)
        onChange?()
    }

    /// Replaces every group (when `config.json` is loaded). Doesn't trigger `onChange`.
    public func replaceAll(_ newGroups: [AppGroup]) {
        groups = newGroups
        try? Persistence.save(groups, to: file)
    }
}
