import AppKit
import Shared

@MainActor
@Observable
public final class InstalledAppProvider {
    public var apps: [AppInfo] = []

    public init() {}

    public func scan() {
        var found: [String: AppInfo] = [:]

        // Primary: scan standard application directories
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        for dir in dirs {
            scanDirectory(dir, into: &found, depth: 0)
        }

        // Secondary: use Spotlight to find all .app bundles the system knows about
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            for line in output.split(separator: "\n") {
                let appURL = URL(fileURLWithPath: String(line))
                guard appURL.pathExtension == "app" else { continue }
                if let bundle = Bundle(url: appURL),
                   let bundleId = bundle.bundleIdentifier,
                   found[bundleId] == nil {
                    let name = FileManager.default.displayName(atPath: appURL.path)
                        .replacingOccurrences(of: ".app", with: "")
                    found[bundleId] = AppInfo(
                        bundleIdentifier: bundleId,
                        name: name,
                        path: appURL.path
                    )
                }
            }
        }

        apps = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(_ url: URL, into found: inout [String: AppInfo], depth: Int) {
        guard depth < 3 else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            if item.pathExtension == "app" {
                if let bundle = Bundle(url: item),
                   let bundleId = bundle.bundleIdentifier {
                    let name = FileManager.default.displayName(atPath: item.path)
                        .replacingOccurrences(of: ".app", with: "")
                    if found[bundleId] == nil {
                        found[bundleId] = AppInfo(
                            bundleIdentifier: bundleId,
                            name: name,
                            path: item.path
                        )
                    }
                }
            } else if item.hasDirectoryPath {
                scanDirectory(item, into: &found, depth: depth + 1)
            }
        }
    }
}
