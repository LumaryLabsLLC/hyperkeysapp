import AppSwitcher
import Foundation
import Shared
import WindowEngine

/// `hyperkeys://` links, for running HyperKeys from scripts, Shortcuts, other launchers or a browser.
///
///     hyperkeys://command/clipboardHistory      any command from config.json
///     hyperkeys://window/leftHalf               a window layout, for the window in front
///     hyperkeys://app/com.apple.Safari          open an app
///     hyperkeys://folder?path=~/Downloads       open a folder
///     hyperkeys://quicklink/Search%20GitHub?argument=swiftui
///     hyperkeys://profile/Gaming                switch profile ("Default" for the default one)
///     hyperkeys://settings/snippets             open the HyperKeys window, optionally on a page
///     hyperkeys://pause, hyperkeys://resume
///
/// Any web page can ask to open one (browsers ask you first), so links only run things a
/// shortcut could, and never paste text or click menus in other apps.
public enum Deeplink: Equatable, Sendable {
    case action(BoundAction)
    case quicklink(name: String, argument: String?)
    case profile(name: String)
    case settings(page: String?)
    case setPaused(Bool)

    public static let scheme = "hyperkeys"

    public struct Failure: Error, Equatable, Sendable {
        public let message: String
    }

    @MainActor
    public static func parse(_ url: URL) -> Result<Deeplink, Failure> {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(Failure(message: "Not a hyperkeys:// link."))
        }
        let kind = (components.host ?? "").lowercased()
        // Everything after the kind, with %2F kept as part of the name.
        let value = components.percentEncodedPath
            .drop { $0 == "/" }
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        func needsValue(_ example: String) -> Result<Deeplink, Failure> {
            .failure(Failure(message: "Say which one, like hyperkeys://\(kind)/\(example)."))
        }

        switch kind {
        case "command", "run":
            guard !value.isEmpty else { return needsValue("appSearch") }
            return action(ConfigDocument.Shortcut(key: "", command: value), link: url)
        case "window":
            guard !value.isEmpty else { return needsValue("leftHalf") }
            return action(ConfigDocument.Shortcut(key: "", window: value), link: url)
        case "app":
            guard !value.isEmpty else { return needsValue("com.apple.Safari") }
            guard AppInfo.resolve(bundleId: value) != nil else {
                return .failure(Failure(message: "There's no app with the id “\(value)” on this Mac."))
            }
            return action(ConfigDocument.Shortcut(key: "", openApp: value), link: url)
        case "folder":
            let path = query["path"] ?? value
            guard !path.isEmpty else {
                return .failure(Failure(message: "Say which folder, like hyperkeys://folder?path=~/Downloads."))
            }
            // Only folders: opening a file could run a script or an app.
            guard isFolder(path) else {
                return .failure(Failure(message: "“\(path)” isn't a folder."))
            }
            return .success(.action(.openFolder(path: path)))
        case "quicklink":
            guard !value.isEmpty else { return needsValue("Search%20GitHub") }
            return .success(.quicklink(name: value, argument: query["argument"].flatMap { $0.isEmpty ? nil : $0 }))
        case "profile":
            guard !value.isEmpty else { return needsValue("Default") }
            return .success(.profile(name: value))
        case "settings":
            return .success(.settings(page: value.isEmpty ? nil : value))
        case "pause":
            return .success(.setPaused(true))
        case "resume":
            return .success(.setPaused(false))
        default:
            return .failure(Failure(message: "HyperKeys doesn't know “\(url.absoluteString)”."))
        }
    }

    @MainActor
    private static func action(_ shortcut: ConfigDocument.Shortcut, link: URL) -> Result<Deeplink, Failure> {
        var groups: [AppGroup] = []
        var warnings: [String] = []
        guard let action = ConfigCodec.action(for: shortcut, groups: &groups, warnings: &warnings, place: "Deeplink") else {
            guard let warning = warnings.first else {
                return .failure(Failure(message: "HyperKeys doesn't know “\(link.absoluteString)”."))
            }
            let problem = warning.replacingOccurrences(of: "Deeplink “”: ", with: "")
            return .failure(Failure(message: problem.prefix(1).uppercased() + problem.dropFirst()))
        }
        return .success(.action(action))
    }

    private static func isFolder(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        // Apps and other bundles are folders too, but open as what they are.
        let url = URL(fileURLWithPath: expanded)
        return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
    }

    // MARK: Making links

    /// The link that does the same as a shortcut for `action`, when there is one.
    @MainActor
    public static func url(for action: BoundAction) -> URL? {
        switch action {
        case .launchApp(let bundleId, _):
            return link("app", bundleId)
        case .windowAction(let position):
            return link("window", position.rawValue)
        case .openFolder(let path):
            var components = URLComponents()
            components.scheme = scheme
            components.host = "folder"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
            return components.url
        case .quicklink(let name):
            return link("quicklink", name)
        case .showAppGroup, .triggerMenuItem:
            return nil
        default:
            guard let shortcut = ConfigCodec.shortcut(for: KeyBinding(keyCode: .a, action: action), groups: [:]),
                  let command = shortcut.command else { return nil }
            return link("command", command)
        }
    }

    public static func url(forProfile name: String) -> URL? {
        link("profile", name)
    }

    private static func link(_ kind: String, _ value: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(scheme)://\(kind)/\(encoded)")
    }
}
