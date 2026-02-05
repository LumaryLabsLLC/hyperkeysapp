import AppKit
import CoreGraphics
import Shared

@MainActor
@Observable
public final class PermissionManager {
    public var accessibilityGranted = false
    public var inputMonitoringGranted = false
    public var hasCheckedOnce = false
    public var onboardingSkipped = false

    private var pollTask: Task<Void, Never>?

    private static let permissionsGrantedKey = "com.hyperkeys.permissionsGranted"

    public var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    /// Whether to show the main UI (permissions granted or user skipped onboarding).
    public var shouldShowMainUI: Bool {
        allPermissionsGranted || onboardingSkipped
    }

    public init() {
        // If we previously confirmed permissions, mark as skipped so we don't block
        if UserDefaults.standard.bool(forKey: Self.permissionsGrantedKey) {
            onboardingSkipped = true
        }
        checkPermissions()
    }

    public func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()

        // CGPreflightListenEventAccess is unreliable (returns false even after grant).
        // Try the preflight first; if it fails, test by actually creating an event tap.
        if CGPreflightListenEventAccess() {
            inputMonitoringGranted = true
        } else {
            inputMonitoringGranted = testEventTapAccess()
        }

        hasCheckedOnce = true

        if allPermissionsGranted {
            UserDefaults.standard.set(true, forKey: Self.permissionsGrantedKey)
            onboardingSkipped = false // no longer needed, real permissions are good
        }
    }

    public func skipOnboarding() {
        onboardingSkipped = true
    }

    public func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.checkPermissions()
                if self?.allPermissionsGranted == true {
                    break
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }

    public func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Actually try to create a CGEventTap to test if Input Monitoring is granted.
    /// More reliable than CGPreflightListenEventAccess().
    private nonisolated func testEventTapAccess() -> Bool {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap {
            // Tap created successfully — permission is granted. Clean up immediately.
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }
}
