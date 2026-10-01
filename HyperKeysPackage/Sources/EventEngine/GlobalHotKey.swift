import AppKit
import Carbon.HIToolbox

/// A regular shortcut such as ⇧⌘V: modifiers plus a key, no Hyper key involved.
public struct KeyCombo: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// ⌃⌥⇧⌘, in the order macOS menus use.
        public var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    public var key: KeyCode
    public var modifiers: Modifiers

    public init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// From a key press while recording. Needs ⌘, ⌃ or ⌥ (Shift alone would block typing),
    /// except for function keys, which are fine on their own.
    public init?(event: NSEvent) {
        guard event.type == .keyDown, let key = KeyCode(rawValue: event.keyCode), key.isBindable else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) || key.isFunctionKey else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// "⇧⌘V"
    public var displayLabel: String {
        modifiers.symbols + key.displayLabel
    }

    /// "shift+cmd+v": how the shortcut is saved.
    public var string: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key.configName)
        return parts.joined(separator: "+")
    }

    public init?(string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, let key = KeyCode(configName: keyName), key.isBindable else { return nil }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "shift", "⇧": modifiers.insert(.shift)
            case "cmd", "command", "⌘": modifiers.insert(.command)
            default: return nil
            }
        }
        guard !modifiers.isEmpty || key.isFunctionKey else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}

extension KeyCode {
    var isFunctionKey: Bool {
        switch self {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12: true
        default: false
        }
    }
}

/// System-wide shortcuts registered with macOS (the same mechanism other launchers use).
/// They work without Input Monitoring, and macOS says when another app already owns one.
@MainActor
@Observable
public final class GlobalHotKeys {
    public static let shared = GlobalHotKeys()

    /// Shortcuts another app already holds, so they couldn't be registered.
    public private(set) var conflicts: Set<KeyCombo> = []

    /// While paused, shortcuts are released so their keys work normally again.
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for name in entries.keys { refresh(name) }
        }
    }

    private struct Entry {
        let id: UInt32
        var combo: KeyCombo
        var action: @MainActor () -> Void
        var ref: EventHotKeyRef?
    }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private var handlerInstalled = false

    private static let signature: OSType = 0x484B_6579 // "HKey"

    /// Sets, replaces or (with nil) removes the shortcut for `name`.
    public func set(_ combo: KeyCombo?, for name: String, action: @escaping @MainActor () -> Void) {
        if let old = entries[name] {
            unregister(old)
            conflicts.remove(old.combo)
            entries[name] = nil
        }
        guard let combo else { return }
        installHandlerIfNeeded()
        let entry = Entry(id: nextID, combo: combo, action: action, ref: nil)
        nextID += 1
        entries[name] = entry
        refresh(name)
    }

    fileprivate func fire(id: UInt32) {
        guard !isPaused, let entry = entries.values.first(where: { $0.id == id }) else { return }
        entry.action()
    }

    private func refresh(_ name: String) {
        guard var entry = entries[name] else { return }
        unregister(entry)
        entry.ref = nil
        conflicts.remove(entry.combo)
        if !isPaused {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(entry.combo.key.rawValue), entry.combo.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: entry.id),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr {
                entry.ref = ref
            } else {
                conflicts.insert(entry.combo)
            }
        }
        entries[name] = entry
    }

    private func unregister(_ entry: Entry) {
        if let ref = entry.ref {
            UnregisterEventHotKey(ref)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handleHotKeyEvent, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

/// macOS calls this on the main thread when a registered shortcut is pressed.
private func handleHotKeyEvent(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        GlobalHotKeys.shared.fire(id: id)
    }
    return noErr
}
