import EventEngine
import Foundation
import Shared

@MainActor
@Observable
public final class BindingStore {
    public var bindings: [KeyBinding] = []
    public var actionGroups: [ActionGroup] = []
    public var activeGroupId: UUID?
    public var hyperKeyCode: KeyCode = .capsLock

    private let bindingsFile = "bindings.json"
    private let groupsFile = "groups.json"
    private let activeGroupFile = "activeGroup.json"
    private let hyperKeyFile = "hyperKey.json"

    public init() {
        load()
    }

    // MARK: - Active bindings

    public var activeBindings: [KeyBinding] {
        if let groupId = activeGroupId,
           let group = actionGroups.first(where: { $0.id == groupId }) {
            return group.bindings
        }
        return bindings
    }

    public func binding(for keyCode: KeyCode) -> KeyBinding? {
        activeBindings.first { $0.keyCode == keyCode && $0.isEnabled }
    }

    // MARK: - Global bindings CRUD

    public func setBinding(_ binding: KeyBinding) {
        if let idx = bindings.firstIndex(where: { $0.keyCode == binding.keyCode }) {
            bindings[idx] = binding
        } else {
            bindings.append(binding)
        }
        save()
    }

    public func removeBinding(for keyCode: KeyCode) {
        bindings.removeAll { $0.keyCode == keyCode }
        save()
    }

    // MARK: - Action Groups CRUD

    public func addGroup(_ group: ActionGroup) {
        actionGroups.append(group)
        save()
    }

    public func updateGroup(_ group: ActionGroup) {
        if let idx = actionGroups.firstIndex(where: { $0.id == group.id }) {
            actionGroups[idx] = group
            save()
        }
    }

    public func deleteGroup(_ id: UUID) {
        actionGroups.removeAll { $0.id == id }
        if activeGroupId == id { activeGroupId = nil }
        save()
    }

    public func setActiveGroup(_ id: UUID?) {
        activeGroupId = id
        save()
    }

    public func setBindingInGroup(groupId: UUID, binding: KeyBinding) {
        guard let gIdx = actionGroups.firstIndex(where: { $0.id == groupId }) else { return }
        if let bIdx = actionGroups[gIdx].bindings.firstIndex(where: { $0.keyCode == binding.keyCode }) {
            actionGroups[gIdx].bindings[bIdx] = binding
        } else {
            actionGroups[gIdx].bindings.append(binding)
        }
        save()
    }

    public func removeBindingInGroup(groupId: UUID, keyCode: KeyCode) {
        guard let gIdx = actionGroups.firstIndex(where: { $0.id == groupId }) else { return }
        actionGroups[gIdx].bindings.removeAll { $0.keyCode == keyCode }
        save()
    }

    // MARK: - Persistence

    public func setHyperKey(_ keyCode: KeyCode) {
        hyperKeyCode = keyCode
        save()
    }

    public func save() {
        try? Persistence.save(bindings, to: bindingsFile)
        try? Persistence.save(actionGroups, to: groupsFile)
        try? Persistence.save(hyperKeyCode, to: hyperKeyFile)
        if let id = activeGroupId {
            try? Persistence.save(id, to: activeGroupFile)
        } else {
            try? Persistence.delete(activeGroupFile)
        }
    }

    public func load() {
        bindings = (try? Persistence.load([KeyBinding].self, from: bindingsFile)) ?? []
        actionGroups = (try? Persistence.load([ActionGroup].self, from: groupsFile)) ?? []
        activeGroupId = try? Persistence.load(UUID.self, from: activeGroupFile)
        hyperKeyCode = (try? Persistence.load(KeyCode.self, from: hyperKeyFile)) ?? .capsLock
    }
}
