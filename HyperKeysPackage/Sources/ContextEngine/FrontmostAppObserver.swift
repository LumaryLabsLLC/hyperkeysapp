import AppKit

@MainActor
@Observable
public final class FrontmostAppObserver {
    public var frontmostBundleId: String?
    public var frontmostAppName: String?

    private nonisolated(unsafe) var observer: NSObjectProtocol?

    public init() {
        updateFrontmostApp()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleId = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            let appName = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frontmostBundleId = bundleId
                self.frontmostAppName = appName
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func updateFrontmostApp() {
        let app = NSWorkspace.shared.frontmostApplication
        frontmostBundleId = app?.bundleIdentifier
        frontmostAppName = app?.localizedName
    }
}
