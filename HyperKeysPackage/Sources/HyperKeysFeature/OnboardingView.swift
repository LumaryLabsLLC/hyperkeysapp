import AppKit
import KeyboardUI
import Permissions
import SwiftUI

public struct OnboardingView: View {
    let permissionManager: PermissionManager

    public init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    public var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: Brand.purple.opacity(0.35), radius: 18, y: 6)
                Text("Welcome to HyperKeys")
                    .font(.largeTitle.weight(.bold))
                Text("Turn Caps Lock into a Hyper Key that opens apps, snaps windows and runs menu commands — from anywhere.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            VStack(spacing: 12) {
                Text("Two quick permissions to get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PermissionStep(
                    number: 1,
                    title: "Accessibility",
                    detail: "Lets HyperKeys move windows and read app menus.",
                    isGranted: permissionManager.accessibilityGranted
                ) {
                    permissionManager.requestAccessibility()
                    PermissionManager.openAccessibilitySettings()
                }
                PermissionStep(
                    number: 2,
                    title: "Input Monitoring",
                    detail: "Lets HyperKeys notice when you hold the Hyper Key.",
                    isGranted: permissionManager.inputMonitoringGranted
                ) {
                    permissionManager.requestInputMonitoring()
                    PermissionManager.openInputMonitoringSettings()
                }
            }
            .frame(maxWidth: 500)

            footer
                .frame(maxWidth: 500)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(colors: [Brand.purple.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
        }
        .onAppear { permissionManager.startPolling() }
        .onDisappear { permissionManager.stopPolling() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if permissionManager.allPermissionsGranted {
                Label("You're all set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for permission — this page updates by itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Trouble?") {
                Button("Check Again", systemImage: "arrow.clockwise") { permissionManager.checkPermissions() }
                Button("Restart HyperKeys", systemImage: "arrow.triangle.2.circlepath") { permissionManager.restartApp() }
                Divider()
                Button("Continue Without Permissions") { permissionManager.skipOnboarding() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct PermissionStep: View {
    let number: Int
    let title: String
    let detail: String
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isGranted ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Brand.gradient))
                if isGranted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isGranted {
                Text("Granted")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings", action: onGrant)
                    .hkProminentButtonStyle()
            }
        }
        .padding(16)
        .hkGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: isGranted)
    }
}
