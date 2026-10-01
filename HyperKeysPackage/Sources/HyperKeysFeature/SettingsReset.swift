import KeyBindings
import Shared
import SwiftUI

/// Settings → Reset All Settings: back to how HyperKeys starts.
@MainActor
enum SettingsReset {
    /// Resets everything in config.json plus the options kept on this Mac. Snippets, quicklinks and
    /// clipboard history stay unless `includingContent`. Launch at login and iCloud sync are left alone.
    /// - Returns: The copy of the old config.json.
    @discardableResult
    static func resetAll(includingContent: Bool) -> URL? {
        let backup = ConfigStore.shared.resetToDefaults(includingContent: includingContent)

        let defaults = UserDefaults.standard
        for key in [Preferences.expandSnippetKeywords, Preferences.cycleHalves, Preferences.appSearchRecents] {
            defaults.removeObject(forKey: key)
        }
        EmojiRecents.clear()
        AppSearchController.shared.model.loadRecents()

        let clipboard = ClipboardHistoryStore.shared
        clipboard.resetOptions()
        if includingContent {
            clipboard.removeAll()
        }
        return backup
    }
}
