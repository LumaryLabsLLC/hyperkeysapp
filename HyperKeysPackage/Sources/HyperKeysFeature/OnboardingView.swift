import Permissions
import SwiftUI

public struct OnboardingView: View {
    let permissionManager: PermissionManager

    public init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Welcome to HyperKeys")
                .font(.largeTitle.bold())

            Text("HyperKeys needs two system permissions to work.\nGrant each one below.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                permissionRow(
                    title: "Accessibility",
                    description: "Required for window management and menu bar reading",
                    granted: permissionManager.accessibilityGranted,
                    action: {
                        permissionManager.requestAccessibility()
                        PermissionManager.openAccessibilitySettings()
                    }
                )

                permissionRow(
                    title: "Input Monitoring",
                    description: "Required for the Hyper key event tap",
                    granted: permissionManager.inputMonitoringGranted,
                    action: {
                        permissionManager.requestInputMonitoring()
                        PermissionManager.openInputMonitoringSettings()
                    }
                )
            }

            if permissionManager.allPermissionsGranted {
                Label("All permissions granted!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(spacing: 12) {
                    Button {
                        permissionManager.checkPermissions()
                    } label: {
                        Label("Refresh Permissions", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Text("Already granted permissions?")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Continue Anyway") {
                        permissionManager.skipOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 500)
        .onAppear { permissionManager.startPolling() }
        .onDisappear { permissionManager.stopPolling() }
    }

    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(granted ? .green : .secondary)
                    Text(title)
                        .font(.headline)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant") { action() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
