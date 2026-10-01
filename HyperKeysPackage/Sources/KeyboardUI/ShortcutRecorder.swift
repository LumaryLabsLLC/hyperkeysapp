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

    public init() {}

    /// Starts listening. `handler` returns true when it accepted the event (recording then stops).
    /// Escape always cancels.
    public func begin(id: AnyHashable, handler: @escaping (NSEvent) -> Bool) {
        cancel()
        activeID = id
        self.handler = handler
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

/// A capsule that shows the hyper combo bound to something, and records a new key when clicked.
public struct ShortcutRecorder: View {
    let keyCode: KeyCode?
    let hyperKey: KeyCode
    let onRecord: (KeyCode) -> Void
    let onClear: () -> Void

    @State private var id = UUID()
    @State private var isHovered = false
    private var center: KeyRecordingCenter { .shared }

    public init(keyCode: KeyCode?, hyperKey: KeyCode, onRecord: @escaping (KeyCode) -> Void, onClear: @escaping () -> Void) {
        self.keyCode = keyCode
        self.hyperKey = hyperKey
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
            .help(isRecording ? "Press a key, or Esc to cancel" : (keyCode == nil ? "Click, then press a key" : "Click to change"))

            if keyCode != nil, !isRecording {
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
                Text("Press a key…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.purple)
            }
        } else if let keyCode {
            HyperComboView(hyperKey: hyperKey, key: keyCode, height: 18)
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
            guard event.type == .keyDown,
                  let key = KeyCode(rawValue: event.keyCode),
                  key.isAssignable(hyperKey: hyperKey) else { return false }
            onRecord(key)
            return true
        }
    }
}
