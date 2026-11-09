import AppKit
import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI

struct HyperKeyView: View {
    @Bindable var bindingStore: BindingStore
    let status: HyperKeyStatus
    let onHyperKeyChanged: (KeyCode) -> Void

    /// Trigger count when the page appeared, so the tester only reacts to new presses.
    @State private var baselineTriggerCount: Int?
    private var recorder: KeyRecordingCenter { .shared }
    private let recorderID = "hyper-key-recorder"

    private struct Preset {
        let key: KeyCode
        let title: String
        let detail: String
    }

    private let presets = [
        Preset(key: .capsLock, title: "Caps Lock", detail: "Recommended — easy to reach and rarely needed."),
        Preset(key: .grave, title: "Backtick", detail: "A quick tap still types ` as usual."),
        Preset(key: .tab, title: "Tab", detail: "A quick tap still types a tab."),
        Preset(key: .rightOption, title: "Right Option", detail: "Leaves Caps Lock free. Left Option works as usual."),
        Preset(key: .modifierHyper, title: "Keyboard Hyper key", detail: "Your keyboard's own Hyper key (⌃⌥⇧⌘), e.g. Kinesis."),
    ]

    private var hyperKey: KeyCode { bindingStore.hyperKeyCode }

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .hyperKey,
                subtitle: "One key that unlocks all of your shortcuts. Hold it, then press another key."
            )

            tester

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose your Hyper Key")
                    .font(.headline)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(presets, id: \.key) { preset in
                        optionCard(keyLabel: preset.key.displayLabel, title: preset.title, detail: preset.detail, isSelected: hyperKey == preset.key) {
                            choose(preset.key)
                        }
                    }
                    otherKeyCard
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How it works")
                    .font(.headline)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    explainer(symbol: "hand.tap.fill", color: Brand.purple, title: "Hold + press a key", detail: "Runs the shortcut on that key.")
                    explainer(symbol: "keyboard", color: .blue, title: "Tap on its own", detail: tapDetail)
                    explainer(symbol: "hand.tap", color: .orange, title: "Double-tap", detail: "Opens or closes this window (can be turned off in Settings).")
                }
            }
        }
        .onAppear { baselineTriggerCount = status.triggerCount }
        .onDisappear {
            if recorder.activeID == AnyHashable(recorderID) { recorder.cancel() }
        }
    }

    // MARK: - Live tester

    private var tester: some View {
        let isHeld = status.isHyperKeyDown

        return HStack(spacing: 24) {
            VStack(spacing: 8) {
                KeycapChip(hyperKey, style: .hyper, height: 84)
                    .scaleEffect(isHeld ? 0.93 : 1)
                    .shadow(color: Brand.purple.opacity(isHeld ? 0.8 : 0.35), radius: isHeld ? 20 : 10)
                Text(hyperKey.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy(duration: 0.18), value: isHeld)

            VStack(alignment: .leading, spacing: 6) {
                Text("TRY IT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.purple)
                Text(testerTitle)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                Text(testerDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(.snappy(duration: 0.2), value: testerTitle)

            Spacer(minLength: 0)
        }
        .padding(22)
        .hkGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Brand.purple.opacity(isHeld ? 0.3 : 0.08))
    }

    private var newTriggerKey: KeyCode? {
        guard let baselineTriggerCount, status.triggerCount > baselineTriggerCount else { return nil }
        return status.lastTriggeredKey
    }

    private var testerTitle: String {
        if status.isPaused { return "HyperKeys is paused" }
        if status.isHyperKeyDown { return "Hyper is on — press any key" }
        if let key = newTriggerKey { return "Hyper + \(key.displayLabel)" }
        return "Hold \(hyperKey.name) to test it"
    }

    private var testerDetail: String {
        if status.isPaused { return "Resume from the sidebar or the menu bar to use your shortcuts." }
        if status.isHyperKeyDown { return "Your shortcut runs as soon as you press a key." }
        if let key = newTriggerKey {
            if let binding = bindingStore.binding(for: key), let presentation = BindingPresentation(binding.action) {
                return "Ran: \(presentation.summary)"
            }
            return "Nothing is assigned to \(key.name) yet — set it up in Shortcuts."
        }
        return "The key above lights up while you hold it."
    }

    // MARK: - Options

    private func optionCard(keyLabel: String, title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                KeycapChip(keyLabel, style: isSelected ? .hyper : .standard, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .hkCard()
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Brand.purple : .clear, lineWidth: 1.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var otherKeyCard: some View {
        let isRecording = recorder.activeID == AnyHashable(recorderID)
        let isCustom = !presets.contains { $0.key == hyperKey }

        return optionCard(
            keyLabel: isCustom ? hyperKey.displayLabel : "…",
            title: isRecording ? "Press a key…" : (isCustom ? hyperKey.name : "Another key"),
            detail: isRecording ? "Press the key you want to use, or Esc to cancel." : "Click, then press any key — even Right ⌘ or your keyboard's own Hyper key.",
            isSelected: isCustom,
            action: toggleRecording
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.purple.opacity(isRecording ? 1 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }

    private func toggleRecording() {
        if recorder.activeID == AnyHashable(recorderID) {
            recorder.cancel()
            return
        }
        var capture = HyperKeyCapture(currentHyperKey: hyperKey)
        recorder.begin(id: recorderID) { event in
            guard let key = capture.handle(type: event.type, keyCode: event.keyCode, flags: event.modifierFlags) else { return false }
            choose(key)
            return true
        }
    }

    private func choose(_ key: KeyCode) {
        guard key != hyperKey else { return }
        withAnimation(.snappy) {
            onHyperKeyChanged(key)
        }
    }

    private var tapDetail: String {
        switch hyperKey {
        case .capsLock: "Caps Lock no longer toggles capitals while HyperKeys is running."
        case .modifierHyper: "Combos you haven't assigned still reach other apps as ⌃⌥⇧⌘ shortcuts."
        case let key where key.isRemappedToF18: "\(key.name) no longer works as a modifier while HyperKeys is running. The left one still does."
        default: "Types \(hyperKey.name) like normal."
        }
    }

    private func explainer(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hkCard()
    }
}

/// Turns what the "Another key" recorder hears into a hyper key choice.
struct HyperKeyCapture {
    /// The hyper key in use when recording started.
    let currentHyperKey: KeyCode
    /// A right-side modifier held on its own. It's chosen when it's released with nothing else pressed,
    /// so a keyboard's own Hyper key, which presses four modifiers in a row, isn't mistaken for one.
    private var soloModifier: KeyCode?

    init(currentHyperKey: KeyCode) {
        self.currentHyperKey = currentHyperKey
    }

    /// The key to use as the hyper key, or nil to keep listening.
    mutating func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> KeyCode? {
        let modifiers = flags.intersection([.command, .control, .option, .shift])
        let pending = soloModifier
        soloModifier = nil

        if type == .flagsChanged {
            // A keyboard with a built-in Hyper key sends ⌃⌥⇧⌘ all at once.
            if modifiers == [.command, .control, .option, .shift] { return .modifierHyper }
            if keyCode == KeyCode.capsLock.rawValue { return .capsLock }
            guard let key = KeyCode(rawValue: keyCode), let modifier = Self.rightModifier(key) else { return nil }
            if flags.rawValue & modifier.deviceMask != 0 {
                // On its own: no other modifier, not even the same one on the left.
                if modifiers == modifier.flag, flags.rawValue & Self.deviceModifierBits == modifier.deviceMask {
                    soloModifier = key
                }
                return nil
            }
            return pending == key ? key : nil
        }

        guard type == .keyDown else { return nil }
        // Caps Lock and right-side modifiers arrive as F18 while they're the hyper key.
        if keyCode == KeyCode.f18.rawValue {
            return currentHyperKey.isRemappedToF18 ? currentHyperKey : .capsLock
        }
        guard let key = KeyCode(rawValue: keyCode), key != .escape else { return nil }
        return key
    }

    /// The device bits of all eight modifier keys, left and right (NX_DEVICE*KEYMASK).
    private static let deviceModifierBits: UInt = 0x207F

    /// The modifier a right-side key holds, and its device bit in the event flags (NX_DEVICER*KEYMASK),
    /// which tells it apart from the left one and shows whether it went down or up.
    private static func rightModifier(_ key: KeyCode) -> (flag: NSEvent.ModifierFlags, deviceMask: UInt)? {
        switch key {
        case .rightControl: (.control, 0x2000)
        case .rightShift: (.shift, 0x04)
        case .rightCommand: (.command, 0x10)
        case .rightOption: (.option, 0x40)
        default: nil
        }
    }
}
