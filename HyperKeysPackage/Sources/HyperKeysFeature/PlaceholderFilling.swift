import AppKit
import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI

// MARK: - Filling in a snippet or link

@MainActor
enum PlaceholderFiller {
    /// Fills in `text`'s placeholders, asking for any `{argument}`s first.
    /// Returns nil when you cancel the prompt.
    static func fill(
        _ text: String, title: String, icon: NSImage? = nil,
        app: NSRunningApplication?, encodesValues: Bool = false, presetArguments: [String: String] = [:]
    ) async -> String? {
        // Read the selection before anything else can change focus.
        let selection = Placeholders.needsSelection(text) ? await SelectedText.capture(from: app) : nil

        var answers = presetArguments
        let fields = Placeholders.arguments(in: text).filter { presetArguments[$0.name] == nil }
        if !fields.isEmpty {
            guard let values = await ArgumentPrompt.shared.ask(title: title, icon: icon, fields: fields, returningTo: app) else {
                return nil
            }
            answers.merge(values) { _, typed in typed }
        }

        let context = PlaceholderContext(
            clipboard: recentClipboardTexts(),
            selection: selection,
            arguments: answers,
            snippet: { name in
                SnippetStore.shared.snippets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.text
            },
            encodesValues: encodesValues
        )
        return Placeholders.expand(text, context: context)
    }

    /// The clipboard now, then older copies from Clipboard History (`{clipboard offset=1}`).
    static func recentClipboardTexts() -> [String] {
        var texts = ClipboardHistoryStore.shared.items
            .filter { $0.kind == .text || $0.kind == .link }
            .map(\.text)
        if let current = NSPasteboard.general.string(forType: .string), texts.first != current {
            texts.insert(current, at: 0)
        }
        return texts
    }
}

// MARK: - Selected text

@MainActor
enum SelectedText {
    /// The text selected in `app`: asked for through Accessibility, or — for apps that don't
    /// say (many web views) — copied with ⌘C, with the clipboard put back afterwards.
    static func capture(from app: NSRunningApplication?) async -> String? {
        if let text = viaAccessibility(app) {
            return text
        }
        let pasteboard = NSPasteboard.general
        let saved = TextPaster.snapshot(of: pasteboard)
        let before = pasteboard.changeCount
        ClipboardMonitor.shared.ignoreChanges(for: 1)
        // Give the app a moment to be in front again, then copy.
        try? await Task.sleep(for: .milliseconds(120))
        postCopy()
        try? await Task.sleep(for: .milliseconds(180))
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        TextPaster.restore(saved, to: pasteboard)
        return text?.isEmpty == false ? text : nil
    }

    private static func viaAccessibility(_ app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(pid)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return nil }
        var selected: AnyObject?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.isEmpty
        else { return nil }
        return text
    }

    private static func postCopy() {
        SyntheticEvent.press(keyCode: 0x08, flags: .maskCommand) // C
    }
}

// MARK: - Argument prompt

@MainActor
@Observable
final class ArgumentPromptModel {
    var title = ""
    var icon: NSImage?
    var fields: [ArgumentField] = []
    var values: [String: String] = [:]
    private(set) var focusRequest = 0

    func requestFocus() {
        focusRequest += 1
    }

    func binding(for field: ArgumentField) -> Binding<String> {
        Binding(get: { self.values[field.name] ?? "" }, set: { self.values[field.name] = $0 })
    }
}

/// Asks for the `{argument}`s of a snippet or quicklink, Raycast-style.
@MainActor
final class ArgumentPrompt {
    static let shared = ArgumentPrompt()

    let model = ArgumentPromptModel()
    private var host: FloatingPanelHost?
    private var continuation: CheckedContinuation<[String: String]?, Never>?

    /// The values typed, by argument name — or nil if the prompt was dismissed.
    func ask(title: String, icon: NSImage?, fields: [ArgumentField], returningTo app: NSRunningApplication?) async -> [String: String]? {
        finish(nil)
        model.title = title
        model.icon = icon
        model.fields = fields
        model.values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.defaultValue ?? $0.options.first ?? "") })
        let host = makeHostIfNeeded()
        host.show(returningTo: app)
        DispatchQueue.main.async { [model] in model.requestFocus() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func submit() {
        let values = model.values
        finish(values)
        host?.hide(restoringFocus: true)
    }

    func cancel() {
        finish(nil)
        host?.hide(restoringFocus: true)
    }

    private func finish(_ values: [String: String]?) {
        continuation?.resume(returning: values)
        continuation = nil
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = ArgumentPromptView(model: model, onSubmit: { [weak self] in self?.submit() })
        let host = FloatingPanelHost(width: ArgumentPromptView.width, rootView: root)
        host.topFraction = 0.24
        host.onKeyDown = { [weak self] event in
            if event.keyCode == 53 { // escape
                self?.cancel()
                return true
            }
            return false
        }
        // Clicking away counts as cancelling.
        host.onHide = { [weak self] in self?.finish(nil) }
        self.host = host
        return host
    }
}

struct ArgumentPromptView: View {
    @Bindable var model: ArgumentPromptModel
    let onSubmit: () -> Void

    @FocusState private var focused: String?

    static let width: CGFloat = 520
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let icon = model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                Text(model.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(height: 50)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.fields) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(field.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        if field.options.isEmpty {
                            TextField(field.defaultValue ?? field.label, text: model.binding(for: field))
                                .textFieldStyle(.plain)
                                .font(.system(size: 16))
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
                                .focused($focused, equals: field.name)
                                .onSubmit(onSubmit)
                        } else {
                            Picker(field.label, selection: model.binding(for: field)) {
                                ForEach(field.options, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .padding(18)

            Divider().opacity(0.5)

            HStack(spacing: 14) {
                Spacer()
                hint("Cancel", keys: ["esc"])
                hint("Continue", keys: ["↩"])
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
        .onChange(of: model.focusRequest) {
            focused = model.fields.first { $0.options.isEmpty }?.name
        }
    }

    private func hint(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(keys, id: \.self) { KeycapChip($0, height: 18) }
        }
    }
}
