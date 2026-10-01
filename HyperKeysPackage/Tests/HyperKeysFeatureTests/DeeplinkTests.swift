import Foundation
import Testing
@testable import KeyBindings
import WindowEngine

@MainActor
struct DeeplinkTests {
    private func parse(_ string: String) -> Deeplink? {
        try? Deeplink.parse(URL(string: string)!).get()
    }

    private func failure(_ string: String) -> String? {
        if case .failure(let failure) = Deeplink.parse(URL(string: string)!) { return failure.message }
        return nil
    }

    @Test func runsCommandsWindowLayoutsAndApps() {
        #expect(parse("hyperkeys://command/clipboardHistory") == .action(.clipboardHistory))
        #expect(parse("hyperkeys://command/lockScreen") == .action(.system(.lockScreen)))
        #expect(parse("HYPERKEYS://Command/appSearch") == .action(.appSearch))
        #expect(parse("hyperkeys://window/leftHalf") == .action(.windowAction(.leftHalf)))
        guard case .action(.launchApp(let bundleId, let name)) = parse("hyperkeys://app/com.apple.finder") else {
            Issue.record("Expected Finder")
            return
        }
        #expect(bundleId == "com.apple.finder")
        #expect(name == "Finder")
    }

    @Test func opensQuicklinksWithAnArgument() {
        #expect(parse("hyperkeys://quicklink/Search%20GitHub?argument=swift%20ui") == .quicklink(name: "Search GitHub", argument: "swift ui"))
        #expect(parse("hyperkeys://quicklink/Jira") == .quicklink(name: "Jira", argument: nil))
        // A slash that's part of the name.
        #expect(parse("hyperkeys://quicklink/CI%2FCD") == .quicklink(name: "CI/CD", argument: nil))
    }

    @Test func switchesProfilesOpensSettingsAndPauses() {
        #expect(parse("hyperkeys://profile/Gaming") == .profile(name: "Gaming"))
        #expect(parse("hyperkeys://settings") == .settings(page: nil))
        #expect(parse("hyperkeys://settings/snippets") == .settings(page: "snippets"))
        #expect(parse("hyperkeys://pause") == .setPaused(true))
        #expect(parse("hyperkeys://resume") == .setPaused(false))
    }

    @Test func opensOnlyRealFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deeplink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("run.command")
        try Data("echo hi".utf8).write(to: script)

        var components = URLComponents(string: "hyperkeys://folder")!
        components.queryItems = [URLQueryItem(name: "path", value: folder.path)]
        #expect(parse(components.url!.absoluteString) == .action(.openFolder(path: folder.path)))
        #expect(parse("hyperkeys://folder?path=~") == .action(.openFolder(path: "~")))

        // Files (which could run) and apps are refused.
        components.queryItems = [URLQueryItem(name: "path", value: script.path)]
        #expect(failure(components.url!.absoluteString) != nil)
        #expect(failure("hyperkeys://folder?path=/System/Applications/Calculator.app") != nil)
    }

    @Test func explainsWhatsWrong() {
        #expect(failure("hyperkeys://command/makeCoffee")?.hasPrefix("Unknown command “makeCoffee”") == true)
        #expect(failure("hyperkeys://window/diagonal")?.contains("diagonal") == true)
        #expect(failure("hyperkeys://command") == "Say which one, like hyperkeys://command/appSearch.")
        #expect(failure("hyperkeys://app/com.example.not-installed")?.contains("com.example.not-installed") == true)
        #expect(failure("hyperkeys://snippet/Password") != nil)
        #expect(failure("hyperkeys://menu?app=com.apple.finder&path=File") != nil)
        #expect(failure("https://example.com") != nil)
    }

    @Test func linksRoundTrip() throws {
        let actions: [BoundAction] = [
            .appSearch, .clipboardHistory, .emptyTrash, .system(.caffeinate), .windowAction(.topRightSixth),
            .launchApp(bundleId: "com.apple.finder", appName: "Finder"), .quicklink(name: "Search GitHub"),
            .openFolder(path: "~"),
        ]
        for action in actions {
            let url = try #require(Deeplink.url(for: action), "\(action)")
            guard case .success(.action(let parsed)) = Deeplink.parse(url) else {
                if case .quicklink = action, case .success(.quicklink(let name, nil)) = Deeplink.parse(url) {
                    #expect(.quicklink(name: name) == action)
                    continue
                }
                Issue.record("\(url) didn't parse")
                continue
            }
            if case .launchApp(let bundleId, _) = action, case .launchApp(let parsedId, _) = parsed {
                #expect(parsedId == bundleId)
            } else {
                #expect(parsed == action)
            }
        }
        #expect(Deeplink.url(for: .quicklink(name: "Search GitHub"))?.absoluteString == "hyperkeys://quicklink/Search%20GitHub")
        #expect(Deeplink.url(for: .triggerMenuItem(appBundleId: "com.apple.finder", menuPath: ["File"])) == nil)
    }
}
