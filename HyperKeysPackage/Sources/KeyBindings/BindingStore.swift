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
    /// Called after any user change, so `config.json` can be updated.
    @ObservationIgnored public var onChange: (() -> Void)?

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

    /// The key currently bound to `action` in the active profile, if any.
    public func keyCode(for action: BoundAction) -> KeyCode? {
        activeBindings.first { $0.action == action && $0.isEnabled }?.keyCode
    }

    // MARK: - Editing the active profile

    public var activeGroup: ActionGroup? {
        guard let activeGroupId else { return nil }
        return actionGroups.first { $0.id == activeGroupId }
    }

    public var activeProfileName: String {
        activeGroup?.name ?? "Default"
    }

    /// Binds `action` to `keyCode` in whichever profile is active.
    public func assign(_ action: BoundAction, to keyCode: KeyCode) {
        let binding = KeyBinding(keyCode: keyCode, action: action)
        if let groupId = activeGroupId {
            setBindingInGroup(groupId: groupId, binding: binding)
        } else {
            setBinding(binding)
        }
    }

    /// Binds several keys at once in the active profile, saving once.
    public func assign(_ assignments: [(key: KeyCode, action: BoundAction)]) {
        var list = activeGroup?.bindings ?? bindings
        for assignment in assignments {
            let binding = KeyBinding(keyCode: assignment.key, action: assignment.action)
            if let index = list.firstIndex(where: { $0.keyCode == assignment.key }) {
                list[index] = binding
            } else {
                list.append(binding)
            }
        }
        if let groupId = activeGroupId, let index = actionGroups.firstIndex(where: { $0.id == groupId }) {
            actionGroups[index].bindings = list
        } else {
            bindings = list
        }
        save()
    }

    /// Points shortcuts that open the quicklink `old` at its new name, in every profile.
    public func renameQuicklink(from old: String, to new: String) {
        guard old != new else { return }
        func rename(_ list: inout [KeyBinding]) {
            for index in list.indices {
                if case .quicklink(let name) = list[index].action, name.caseInsensitiveCompare(old) == .orderedSame {
                    list[index].action = .quicklink(name: new)
                }
            }
        }
        rename(&bindings)
        for index in actionGroups.indices {
            rename(&actionGroups[index].bindings)
        }
        save()
    }

    /// Removes the binding for `keyCode` from whichever profile is active.
    public func clearBinding(for keyCode: KeyCode) {
        if let groupId = activeGroupId {
            removeBindingInGroup(groupId: groupId, keyCode: keyCode)
        } else {
            removeBinding(for: keyCode)
        }
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

    public func renameGroup(_ id: UUID, to name: String) {
        guard let idx = actionGroups.firstIndex(where: { $0.id == id }) else { return }
        actionGroups[idx].name = name
        save()
    }

    /// Creates a new profile (optionally copying the active profile's bindings) and activates it.
    @discardableResult
    public func createProfile(named name: String, copyingActive: Bool) -> ActionGroup {
        let copied = copyingActive ? activeBindings.map { KeyBinding(keyCode: $0.keyCode, action: $0.action, isEnabled: $0.isEnabled) } : []
        let group = ActionGroup(name: name, bindings: copied)
        actionGroups.append(group)
        activeGroupId = group.id
        save()
        return group
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
        onChange?()
    }

    /// Replaces everything with what `config.json` says. Doesn't trigger `onChange`.
    /// The active profile is kept when a profile with the same id (same name) still exists.
    public func apply(bindings: [KeyBinding], profiles: [ActionGroup], hyperKey: KeyCode) {
        self.bindings = bindings
        actionGroups = profiles
        hyperKeyCode = hyperKey
        if let id = activeGroupId, !profiles.contains(where: { $0.id == id }) {
            activeGroupId = nil
        }
        // Keep the legacy files in step, so an older HyperKeys still finds current settings.
        try? Persistence.save(bindings, to: bindingsFile)
        try? Persistence.save(actionGroups, to: groupsFile)
        try? Persistence.save(hyperKeyCode, to: hyperKeyFile)
    }

    public func load() {
        bindings = (try? Persistence.load([KeyBinding].self, from: bindingsFile)) ?? []
        actionGroups = (try? Persistence.load([ActionGroup].self, from: groupsFile)) ?? []
        activeGroupId = try? Persistence.load(UUID.self, from: activeGroupFile)
        if let id = activeGroupId, !actionGroups.contains(where: { $0.id == id }) {
            activeGroupId = nil
        }
        hyperKeyCode = (try? Persistence.load(KeyCode.self, from: hyperKeyFile)) ?? .capsLock
    }
}
