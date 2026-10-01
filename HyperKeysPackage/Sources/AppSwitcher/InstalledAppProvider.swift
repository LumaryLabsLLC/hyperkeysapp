import AppKit
import Shared

/// Discovers user-facing installed apps. Scanning happens off the main thread and the
/// result is shared app-wide, so pickers open instantly after the first scan.
@MainActor
@Observable
public final class InstalledAppProvider {
    public static let shared = InstalledAppProvider()

    public private(set) var apps: [AppInfo] = []
    public private(set) var isLoading = false
    private var hasLoaded = false

    public init() {}

    /// Scans once; later calls are no-ops.
    public func loadIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    public func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                Self.discoverApps()
            }.value
            apps = found
            isLoading = false
            hasLoaded = true
        }
    }

    /// Regular (Dock-visible) apps that are running right now, sorted by name.
    public static func runningApps() -> [AppInfo] {
        let ownBundleId = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleId }
            .compactMap { app -> AppInfo? in
                guard let bundleId = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return AppInfo(bundleIdentifier: bundleId, name: app.localizedName ?? bundleId, path: url.path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Discovery

    private nonisolated static func discoverApps() -> [AppInfo] {
        var found: [String: AppInfo] = [:]

        // Primary: standard application directories
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        for dir in dirs {
            scanDirectory(dir, into: &found, depth: 0)
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), into: &found)

        // Secondary: Spotlight, for apps installed elsewhere
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    let url = URL(fileURLWithPath: String(line))
                    if isUserFacingLocation(url) {
                        add(url, into: &found)
                    }
                }
            }
        }

        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func scanDirectory(_ url: URL, into found: inout [String: AppInfo], depth: Int) {
        guard depth < 3 else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            if item.pathExtension == "app" {
                add(item, into: &found)
            } else if item.hasDirectoryPath {
                scanDirectory(item, into: &found, depth: depth + 1)
            }
        }
    }

    private nonisolated static func add(_ url: URL, into found: inout [String: AppInfo]) {
        guard url.pathExtension == "app",
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier,
              found[bundleId] == nil else { return }

        let info = bundle.infoDictionary ?? [:]
        // Skip faceless helpers (e.g. CalendarFileHandler, CharacterPalette)
        if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSBackgroundOnly"] as? String) == "1" {
            return
        }
        if let type = info["CFBundlePackageType"] as? String, type != "APPL" {
            return
        }

        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        found[bundleId] = AppInfo(bundleIdentifier: bundleId, name: name, path: url.path)
    }

    /// Filters out helper apps buried inside other bundles, system internals and build products.
    private nonisolated static func isUserFacingLocation(_ url: URL) -> Bool {
        let path = url.path
        let blocked = ["/System/Library/", "/Library/", "/DerivedData/", "/.Trash/", "/private/", "/opt/"]
        let allowed = ["/System/Library/CoreServices/Applications/", "/System/Library/CoreServices/Finder.app"]
        if blocked.contains(where: path.contains), !allowed.contains(where: path.hasPrefix) {
            return false
        }

        // Nested apps are usually helpers — except developer tools shipped inside Xcode.
        let parent = url.deletingLastPathComponent().path
        if parent.contains(".app/") || parent.hasSuffix(".app") {
            return parent.hasSuffix("/Contents/Applications") || parent.hasSuffix("/Contents/Developer/Applications")
        }
        return true
    }
}
