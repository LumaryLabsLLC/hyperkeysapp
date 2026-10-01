import AppKit
import KeyBindings
import OSLog
import SwiftUI

/// Runs `hyperkeys://` links (see `Deeplink`). A link that can't run beeps and is logged.
@MainActor
public final class DeeplinkRouter {
    public static let shared = DeeplinkRouter()

    /// Provided by the app layer.
    public var bindingStore: BindingStore?
    public var perform: ((BoundAction) -> Void)?
    public var setPaused: ((Bool) -> Void)?

    private let logger = Logger(subsystem: "com.hyperkeys.app", category: "Deeplink")

    public func open(_ url: URL) {
        switch Deeplink.parse(url) {
        case .failure(let failure):
            report(failure.message)
        case .success(let link):
            run(link)
        }
    }

    private func run(_ link: Deeplink) {
        switch link {
        case .action(let action):
            perform?(action)
        case .quicklink(let name, let argument):
            guard let quicklink = QuicklinkStore.shared.quicklink(named: name) else {
                report("There's no quicklink named “\(name)”.")
                return
            }
            QuicklinkRunner.open(quicklink, from: NSWorkspace.shared.frontmostApplication, argument: argument)
        case .profile(let name):
            guard let bindingStore else { return }
            if name.caseInsensitiveCompare("Default") == .orderedSame {
                bindingStore.setActiveGroup(nil)
            } else if let profile = bindingStore.actionGroups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                bindingStore.setActiveGroup(profile.id)
            } else {
                report("There's no profile named “\(name)”.")
            }
        case .settings(let page):
            guard let page else {
                HyperKeysWindow.open?()
                return
            }
            guard let pane = Pane.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(page) == .orderedSame }) else {
                report("There's no settings page called “\(page)”. Use one of: \(Pane.allCases.map(\.rawValue).joined(separator: ", ")).")
                return
            }
            HyperKeysWindow.open(on: pane)
        case .setPaused(let paused):
            setPaused?(paused)
        }
    }

    private func report(_ message: String) {
        NSSound.beep()
        logger.error("\(message, privacy: .public)")
    }
}

/// "Copy Deeplink" for a context menu; nothing when the action has no link.
struct CopyDeeplinkButton: View {
    let url: URL?

    init(_ url: URL?) {
        self.url = url
    }

    init(for action: BoundAction) {
        url = Deeplink.url(for: action)
    }

    var body: some View {
        if let url {
            Button("Copy Deeplink", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }
}
