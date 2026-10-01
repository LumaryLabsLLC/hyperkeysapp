import AppKit
import EventEngine
import KeyBindings

/// Puts text into the app you were using: on the clipboard, then ⌘V, then the old clipboard back.
@MainActor
enum TextPaster {
    /// Call after focus has been handed back to the target app.
    /// - Parameter paste: false only copies.
    static func deliver(_ text: String, paste: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = paste ? snapshot(of: pasteboard) : nil

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if paste {
            // Only here for a moment, so Clipboard History leaves it out.
            item.setString("", forType: ClipboardReader.ownWriteType)
        }
        pasteboard.writeObjects([item])
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

    typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            // Putting back what was there isn't a new copy.
            item.setString("", forType: ClipboardReader.ownWriteType)
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    /// Presses ⌘V in the frontmost app, once focus has had a moment to settle.
    static func pasteSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            postCommandV()
        }
    }

    private static func postCommandV() {
        SyntheticEvent.press(keyCode: 0x09, flags: .maskCommand) // V
    }
}
