import AppKit
import EventEngine
import KeyBindings
import SwiftUI

/// Owns the single app-wide key monitor used while a recorder is listening,
/// so only one recorder can be active at a time.
@MainActor
@Observable
public final class KeyRecordingCenter {
    public static let shared = KeyRecordingCenter()

    public private(set) var activeID: AnyHashable?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var handler: ((NSEvent) -> Bool)?
    /// Whether shortcuts were already paused before recording, to put back afterwards.
    @ObservationIgnored private var hotKeysWerePaused: Bool?

    public init() {}

    /// Starts listening. `handler` returns true when it accepted the event (recording then stops).
    /// Escape always cancels.
    public func begin(id: AnyHashable, handler: @escaping (NSEvent) -> Bool) {
        cancel()
        activeID = id
        self.handler = handler
        // Otherwise pressing a shortcut HyperKeys already uses would run it instead of recording it.
        hotKeysWerePaused = GlobalHotKeys.shared.isPaused
        GlobalHotKeys.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let consumed = MainActor.assumeIsolated {
                KeyRecordingCenter.shared.handle(event)
            }
            return consumed ? nil : event
        }
    }

    public func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        handler = nil
        activeID = nil
        if let hotKeysWerePaused {
            GlobalHotKeys.shared.isPaused = hotKeysWerePaused
        }
        hotKeysWerePaused = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let handler else { return false }
        if event.type == .keyDown, event.keyCode == KeyCode.escape.rawValue {
            cancel()
            return true
        }
        if handler(event) {
            cancel()
        } else if event.type == .keyDown {
            NSSound.beep()
        }
        return true
    }
}

/// What a recorder heard: a key to use with Hyper, or a regular shortcut like ⇧⌘V.
public enum RecordedShortcut: Equatable, Sendable {
    case hyper(KeyCode)
    case combo(KeyCombo)
}

/// A capsule that shows an action's shortcut and records a new one when clicked.
/// A key on its own becomes Hyper + that key; with ⌘, ⌃ or ⌥ it's a regular shortcut.
public struct ShortcutRecorder: View {
    let keyCode: KeyCode?
    let combo: KeyCombo?
    let hyperKey: KeyCode
    let onRecord: (RecordedShortcut) -> Void
    let onClear: () -> Void

    @State private var id = UUID()
    @State private var isHovered = false
    private var center: KeyRecordingCenter { .shared }

    public init(
        keyCode: KeyCode?, combo: KeyCombo? = nil, hyperKey: KeyCode,
        onRecord: @escaping (RecordedShortcut) -> Void, onClear: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.combo = combo
        self.hyperKey = hyperKey
        self.onRecord = onRecord
        self.onClear = onClear
    }

    private var isRecording: Bool {
        center.activeID == AnyHashable(id)
    }

    private var isEmpty: Bool {
        keyCode == nil && combo == nil
    }

    public var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                label
                    .frame(minWidth: 96, minHeight: 26)
                    .padding(.horizontal, 6)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .background(
                Capsule().fill(isRecording ? Brand.purple.opacity(0.14) : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)))
            )
            .overlay(
                Capsule().strokeBorder(isRecording ? Brand.purple : Color.primary.opacity(0.1), lineWidth: isRecording ? 1.5 : 0.5)
            )
            .onHover { isHovered = $0 }
            .help(isRecording
                ? "Press a key to use it with Hyper, or a shortcut like ⇧⌘V. Esc cancels."
                : (isEmpty ? "Click, then press a key to use with Hyper, or any shortcut like ⇧⌘V" : "Click to change"))

            if !isEmpty, !isRecording {
                Button("Remove Shortcut", systemImage: "xmark.circle.fill", action: onClear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Remove shortcut")
            }
        }
        .animation(.snappy(duration: 0.2), value: isRecording)
        .onDisappear {
            if isRecording { center.cancel() }
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Brand.purple)
                    .frame(width: 6, height: 6)
                    .phaseAnimator([0.3, 1.0]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                Text("Press a shortcut…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.purple)
            }
        } else if !isEmpty {
            HStack(spacing: 6) {
                if let keyCode {
                    HyperComboView(hyperKey: hyperKey, key: keyCode, height: 18)
                }
                if keyCode != nil, combo != nil {
                    Text("·").foregroundStyle(.tertiary)
                }
                if let combo {
                    ComboKeycaps(combo: combo, height: 18)
                }
            }
        } else {
            Label("Record", systemImage: "record.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleRecording() {
        if isRecording {
            center.cancel()
            return
        }
        let hyperKey = hyperKey
        center.begin(id: id) { event in
            // Modifier presses alone keep listening.
            guard event.type == .keyDown, let key = KeyCode(rawValue: event.keyCode) else { return false }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // A key on its own (or with all four modifiers, from a keyboard's own Hyper key) is Hyper + that key.
            if flags.isDisjoint(with: [.command, .control, .option]) || flags == [.command, .control, .option, .shift] {
                guard key.isAssignable(hyperKey: hyperKey) else { return false }
                onRecord(.hyper(key))
                return true
            }
            guard let combo = KeyCombo(event: event) else { return false }
            onRecord(.combo(combo))
            return true
        }
    }
}

/// The keys of a regular shortcut as keycaps: ⇧ ⌘ V.
public struct ComboKeycaps: View {
    let combo: KeyCombo
    let height: CGFloat

    public init(combo: KeyCombo, height: CGFloat = 20) {
        self.combo = combo
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(combo.modifiers.symbols), id: \.self) { symbol in
                KeycapChip(String(symbol), height: height)
            }
            KeycapChip(combo.key, height: height)
        }
    }
}

/// A capsule that shows a regular shortcut like ⇧⌘V, and records a new one when clicked.
public struct KeyComboRecorder: View {
    let combo: KeyCombo?
    let onRecord: (KeyCombo) -> Void
    let onClear: () -> Void

    @State private var id = UUID()
    @State private var isHovered = false
    private var center: KeyRecordingCenter { .shared }

    public init(combo: KeyCombo?, onRecord: @escaping (KeyCombo) -> Void, onClear: @escaping () -> Void) {
        self.combo = combo
        self.onRecord = onRecord
        self.onClear = onClear
    }

    private var isRecording: Bool {
        center.activeID == AnyHashable(id)
    }

    public var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                label
                    .frame(minWidth: 96, minHeight: 26)
                    .padding(.horizontal, 6)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .background(
                Capsule().fill(isRecording ? Brand.purple.opacity(0.14) : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)))
            )
            .overlay(
                Capsule().strokeBorder(isRecording ? Brand.purple : Color.primary.opacity(0.1), lineWidth: isRecording ? 1.5 : 0.5)
            )
            .onHover { isHovered = $0 }
            .help(isRecording ? "Press a shortcut, or Esc to cancel" : (combo == nil ? "Click, then press a shortcut such as ⇧⌘V" : "Click to change"))

            if combo != nil, !isRecording {
                Button("Remove Shortcut", systemImage: "xmark.circle.fill", action: onClear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Remove shortcut")
            }
        }
        .animation(.snappy(duration: 0.2), value: isRecording)
        .onDisappear {
            if isRecording { center.cancel() }
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Brand.purple)
                    .frame(width: 6, height: 6)
                    .phaseAnimator([0.3, 1.0]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                Text("Press a shortcut…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.purple)
            }
        } else if let combo {
            ComboKeycaps(combo: combo, height: 18)
        } else {
            Label("Record", systemImage: "record.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleRecording() {
        if isRecording {
            center.cancel()
            return
        }
        center.begin(id: id) { event in
            // Modifier presses alone keep listening; a real key with ⌘, ⌃ or ⌥ completes it.
            guard event.type == .keyDown else { return false }
            guard let combo = KeyCombo(event: event) else { return false }
            onRecord(combo)
            return true
        }
    }
}
