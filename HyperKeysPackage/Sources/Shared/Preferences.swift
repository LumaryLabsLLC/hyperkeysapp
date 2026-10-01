import Foundation

/// UserDefaults keys for simple app preferences.
public enum Preferences {
    /// Double-tapping the hyper key toggles the HyperKeys window. Defaults to true.
    public static let doubleTapOpensWindow = "doubleTapOpensWindow"
    /// Set once Hyper + Space has been offered as the default App Search shortcut.
    public static let didSeedAppSearch = "didSeedAppSearch"
    /// Set once Hyper + Tab has been offered as the default App Switcher shortcut.
    public static let didSeedAppSwitcher = "didSeedAppSwitcher"
    /// Bundle ids most recently opened from App Search, newest first.
    public static let appSearchRecents = "appSearchRecents"
    /// Set after the first launch so the window only opens automatically once.
    public static let hasLaunchedBefore = "hasLaunchedBefore"

    public static var isDoubleTapEnabled: Bool {
        UserDefaults.standard.object(forKey: doubleTapOpensWindow) as? Bool ?? true
    }
}

extension Preferences {
    /// App Switcher style: false = hold Hyper and release to switch (⌘-Tab); true = stays open
    /// until you pick something (navigate with h j k l / arrows, Return to switch).
    public static let switcherStaysOpen = "switcherStaysOpen"

    public static var isSwitcherStayOpen: Bool {
        UserDefaults.standard.bool(forKey: switcherStaysOpen)
    }
}
