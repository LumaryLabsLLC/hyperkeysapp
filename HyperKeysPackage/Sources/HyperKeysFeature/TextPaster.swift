import AppKit

/// Puts text into the app you were using: on the clipboard, then ⌘V, then the old clipboard back.
@MainActor
enum TextPaster {
    /// Call after focus has been handed back to the target app.
    /// - Parameter paste: false only copies.
    static func deliver(_ text: String, paste: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = paste ? snapshot(of: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard paste else { return }

        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            postCommandV()
            // Put back whatever was on the clipboard, unless something else has replaced it since.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let saved, pasteboard.changeCount == changeCount else { return }
                restore(saved, to: pasteboard)
            }
        }
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
