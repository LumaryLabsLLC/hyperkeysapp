import AppKit
import AppSwitcher
import EventEngine
import Foundation
import Shared

/// Keeps `~/.config/hyperkeys/config.json` and the running app in step, in both directions:
/// changes made in HyperKeys are written to the file, and edits to the file (by hand, `git pull`,
/// another Mac via iCloud) are loaded automatically.
///
/// Dotfiles-friendly: if `~/.config/hyperkeys` or `config.json` is a symlink, writes go *through*
/// the link instead of replacing it. A file with mistakes is never silently overwritten — the app
/// keeps its last good settings, reports the problem, and backs the file up before saving over it.
@MainActor
@Observable
public final class ConfigStore {
    public static let shared = ConfigStore()

    public enum Location: Equatable {
        /// A regular file at the config path.
        case local
        /// Linked into iCloud Drive by HyperKeys' sync setting.
        case iCloud
        /// Linked somewhere else (dotfiles, a synced folder, …), shown as an abbreviated path.
        case linked(String)
    }

    /// The config path as users know it (it may be a symlink).
    public let fileURL: URL
    /// Where the synced config lives when iCloud sync is on (`iCloud Drive/HyperKeys`).
    public let iCloudFolder: URL
    public private(set) var location: Location = .local
    /// Set when the file can't be read; the app keeps using its last good settings.
    public private(set) var loadError: String?
    /// Parts of the file that were skipped (unknown key names and the like).
    public private(set) var warnings: [String] = []
    public private(set) var lastLoaded: Date?

    /// Called when a reload changes the hyper key, so the event tap can follow.
    @ObservationIgnored public var onHyperKeyChanged: ((KeyCode) -> Void)?

    @ObservationIgnored private weak var bindingStore: BindingStore?
    @ObservationIgnored private var lastSynced: Data?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let activeProfileKey = "activeProfileName"

    public init(fileURL: URL = ConfigStore.defaultFileURL, iCloudFolder: URL = ConfigStore.defaultICloudFolder) {
        self.fileURL = fileURL
        self.iCloudFolder = iCloudFolder
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs/HyperKeys` — iCloud Drive's HyperKeys folder.
    public nonisolated static var defaultICloudFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/HyperKeys", isDirectory: true)
    }

    /// `$XDG_CONFIG_HOME/hyperkeys/config.json`, falling back to `~/.config/hyperkeys/config.json`.
    public nonisolated static var defaultFileURL: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("hyperkeys", isDirectory: true).appendingPathComponent("config.json")
    }

    /// Where the file actually lives once symlinks are followed.
    public var resolvedURL: URL {
        fileURL.resolvingSymlinksInPath()
    }

    // MARK: - Lifecycle

    /// Loads the config file (creating it from the current settings the first time) and starts
    /// following changes in both directions.
    public func start(bindingStore: BindingStore) {
        self.bindingStore = bindingStore
        bindingStore.onChange = { [weak self] in self?.save() }
        AppGroupStore.shared.onChange = { [weak self] in self?.save() }
        SnippetStore.shared.onChange = { [weak self] in self?.save() }
        QuicklinkStore.shared.onChange = { [weak self] in self?.save() }
        GlobalShortcutStore.shared.onChange = { [weak self] in self?.save() }
        AliasStore.shared.onChange = { [weak self] in self?.save() }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: WindowGap.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveIfPreferencesChanged() }
            },
            // Catch edits made while a watcher wasn't looking (e.g. the folder was swapped).
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
        ]

        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            reload()
        } else {
            save()
            // Re-read once so profile and group ids become stable (derived from their names).
            reload(force: true)
        }
        startWatching()
    }

    // MARK: - Saving

    /// Writes the current settings to the file (skipped when nothing changed).
    public func save() {
        guard !isApplying, let bindingStore else { return }
        if let active = bindingStore.activeGroup?.name {
            UserDefaults.standard.set(active, forKey: Self.activeProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeProfileKey)
        }

        let document = ConfigCodec.document(from: currentSettings(bindingStore))
        guard let data = try? ConfigCodec.encode(document), data != lastSynced else { return }
        do {
            if loadError != nil {
                backUpBrokenFile()
            }
            try writeThroughLinks(data)
            lastSynced = data
            loadError = nil
        } catch {
            loadError = "Couldn't save config.json: \(error.localizedDescription)"
        }
    }

    /// Writes to wherever the config path points, keeping any symlinks in place.
    func writeThroughLinks(_ data: Data) throws {
        let target = resolvedURL
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    private var lastPreferences: (Bool, Bool)?

    private func saveIfPreferencesChanged() {
        let current = (Preferences.isSwitcherStayOpen, Preferences.isDoubleTapEnabled)
        guard lastPreferences.map({ $0 != current }) ?? true else { return }
        lastPreferences = current
        save()
    }

    private func currentSettings(_ store: BindingStore) -> ConfigSettings {
        let actions = (store.bindings + store.actionGroups.flatMap(\.bindings)).map(\.action)
            + GlobalShortcutStore.shared.shortcuts.map(\.action)
            + AliasStore.shared.aliases.map(\.action)
        let referenced = Set(actions.compactMap { action -> UUID? in
            if case .showAppGroup(let id) = action { return id }
            return nil
        })
        return ConfigSettings(
            bindings: store.bindings,
            profiles: store.actionGroups,
            appGroups: AppGroupStore.shared.groups.filter { referenced.contains($0.id) },
            hyperKey: store.hyperKeyCode,
            windowGap: WindowGap.load(),
            switcherStaysOpen: Preferences.isSwitcherStayOpen,
            doubleTapOpensWindow: Preferences.isDoubleTapEnabled,
            snippets: SnippetStore.shared.snippets,
            quicklinks: QuicklinkStore.shared.quicklinks,
            hotkeys: GlobalShortcutStore.shared.shortcuts,
            aliases: AliasStore.shared.aliases
        )
    }

    private func backUpBrokenFile() {
        let target = resolvedURL
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = target.deletingLastPathComponent().appendingPathComponent("config.invalid-\(stamp).json")
        try? FileManager.default.copyItem(at: target, to: backup)
    }

    // MARK: - Loading

    /// Re-reads the file and applies it if it changed since the last read or write.
    public func reload(force: Bool = false) {
        refreshLocation()
        guard let data = try? Data(contentsOf: resolvedURL) else {
            // Deleted or moved away: write the current settings back so the file always exists.
            if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                lastSynced = nil
                save()
            }
            return
        }
        guard force || data != lastSynced else { return }

        do {
            let document = try ConfigCodec.decode(data)
            let (settings, warnings) = ConfigCodec.settings(from: document)
            apply(settings)
            self.warnings = warnings
            loadError = nil
            lastSynced = data
            lastLoaded = Date()
        } catch {
            let reason = error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            loadError = "config.json couldn't be loaded — \(reason). HyperKeys is still using your last working settings."
            lastSynced = data
        }
    }

    private func apply(_ settings: ConfigSettings) {
        guard let bindingStore else { return }
        isApplying = true
        defer { isApplying = false }

        let previousHyperKey = bindingStore.hyperKeyCode
        AppGroupStore.shared.replaceAll(settings.appGroups)
        SnippetStore.shared.replaceAll(settings.snippets)
        QuicklinkStore.shared.replaceAll(settings.quicklinks)
        GlobalShortcutStore.shared.replaceAll(settings.hotkeys)
        AliasStore.shared.replaceAll(settings.aliases)
        bindingStore.apply(bindings: settings.bindings, profiles: settings.profiles, hyperKey: settings.hyperKey)

        // The active profile is remembered by name, per Mac.
        if let name = UserDefaults.standard.string(forKey: Self.activeProfileKey),
           let profile = settings.profiles.first(where: { $0.name == name }) {
            bindingStore.activeGroupId = profile.id
        }

        if WindowGap.load() != settings.windowGap {
            settings.windowGap.save()
        }
        UserDefaults.standard.set(settings.switcherStaysOpen, forKey: Preferences.switcherStaysOpen)
        UserDefaults.standard.set(settings.doubleTapOpensWindow, forKey: Preferences.doubleTapOpensWindow)
        lastPreferences = (settings.switcherStaysOpen, settings.doubleTapOpensWindow)

        if settings.hyperKey != previousHyperKey {
            onHyperKeyChanged?(settings.hyperKey)
        }
    }

    // MARK: - Reset

    /// What a fresh install starts with: Hyper + Space for App Search, Hyper + Tab for the App Switcher,
    /// Caps Lock as the Hyper key, and every option at its default.
    public static func defaultSettings(snippets: [Snippet] = [], quicklinks: [Quicklink] = []) -> ConfigSettings {
        ConfigSettings(
            bindings: [KeyBinding(keyCode: .space, action: .appSearch), KeyBinding(keyCode: .tab, action: .appSwitcher)],
            snippets: snippets,
            quicklinks: quicklinks
        )
    }

    /// Puts shortcuts and settings back the way a fresh install has them, after copying config.json
    /// to `backupFolder`. Snippets and quicklinks are kept unless `includingContent`.
    /// - Returns: The copy of the old config, if there was one to copy.
    @discardableResult
    public func resetToDefaults(includingContent: Bool, backupFolder: URL = ConfigStore.backupFolder) -> URL? {
        guard let bindingStore else { return nil }
        let backup = copyConfig(to: backupFolder, prefix: "config.before-reset")
        UserDefaults.standard.removeObject(forKey: Self.activeProfileKey)
        bindingStore.activeGroupId = nil
        apply(includingContent
            ? Self.defaultSettings()
            : Self.defaultSettings(snippets: SnippetStore.shared.snippets, quicklinks: QuicklinkStore.shared.quicklinks))
        save()
        return backup
    }

    /// Where copies of config.json go before a reset: out of the way of dotfiles and iCloud.
    public static var backupFolder: URL {
        Persistence.appSupportURL.appendingPathComponent("Backups", isDirectory: true)
    }

    /// Copies config.json into `folder` as "<prefix>-<date>.json".
    func copyConfig(to folder: URL, prefix: String) -> URL? {
        let source = resolvedURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = folder.appendingPathComponent("\(prefix)-\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        } catch {
            return nil
        }
    }

    // MARK: - Watching

    private func startWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
        // Watch the folder the path is in and the folder the file really lives in: editors, git and
        // iCloud replace the file rather than writing into it, which only shows up as a folder change.
        let folders = Set([fileURL.deletingLastPathComponent().path, resolvedURL.deletingLastPathComponent().path])
        for folder in folders {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let descriptor = open(folder, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
                self?.startWatching()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - iCloud Drive

    /// Whether iCloud Drive is turned on (its folder exists). Only checked when the user asks for sync.
    private var isICloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: iCloudFolder.deletingLastPathComponent().path)
    }

    /// Whether another Mac has already put a config in iCloud Drive.
    public var iCloudHasConfig: Bool {
        FileManager.default.fileExists(atPath: iCloudFolder.appendingPathComponent("config.json").path)
    }

    /// Moves the config into iCloud Drive and leaves a symlink at the usual path.
    /// - Parameter keepingICloudCopy: Use the config already in iCloud (from another Mac) instead of this Mac's.
    public func enableICloudSync(keepingICloudCopy: Bool) throws {
        guard isICloudDriveAvailable else { throw ConfigError.iCloudDriveUnavailable }
        if case .linked(let path) = location { throw ConfigError.managedElsewhere(path) }
        let folder = iCloudFolder

        let fileManager = FileManager.default
        let cloudFile = folder.appendingPathComponent("config.json")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let localData = try Data(contentsOf: resolvedURL)
        if keepingICloudCopy, fileManager.fileExists(atPath: cloudFile.path) {
            // This Mac's settings are about to be replaced; keep them next to the link, just in case.
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("config.before-icloud.json")
            try? localData.write(to: backup, options: .atomic)
        } else {
            try localData.write(to: cloudFile, options: .atomic)
        }
        try? fileManager.removeItem(at: fileURL)
        try fileManager.createSymbolicLink(at: fileURL, withDestinationURL: cloudFile)

        lastSynced = nil
        reload(force: true)
        startWatching()
    }

    /// Brings the config back to a regular local file (with the latest contents from iCloud).
    public func disableICloudSync() throws {
        guard location == .iCloud else { return }
        let data = try Data(contentsOf: resolvedURL)
        try FileManager.default.removeItem(at: fileURL)
        try data.write(to: fileURL, options: .atomic)
        refreshLocation()
        startWatching()
    }

    private func refreshLocation() {
        let resolved = resolvedURL.path
        // Judged from the path alone: touching iCloud Drive can make macOS ask for permission,
        // which nobody should see unless they turn sync on.
        if resolved.hasPrefix(iCloudFolder.standardizedFileURL.path + "/") {
            location = .iCloud
        } else if resolved != fileURL.standardizedFileURL.path {
            location = .linked((resolved as NSString).abbreviatingWithTildeInPath)
        } else {
            location = .local
        }
    }
}
