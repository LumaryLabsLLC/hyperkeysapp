import EventEngine
import KeyBindings
import Permissions
import Shared
import SwiftUI

struct GeneralSettingsView: View {
    let permissionManager: PermissionManager
    @Bindable var bindingStore: BindingStore
    var onHyperKeyChanged: ((KeyCode) -> Void)?

    @State private var isCapturingHyperKey = false
    @State private var windowGap = WindowGap.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hyper Key section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hyper Key", systemImage: "command.circle")
                        .font(.title3.bold())

                    HStack {
                        Text("Current hyper key:")
                        Text(bindingStore.hyperKeyCode.displayLabel)
                            .font(.title2.bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                        Spacer()

                        if isCapturingHyperKey {
                            Text("Press any key...")
                                .foregroundStyle(.orange)
                                .font(.callout.bold())
                        } else {
                            Button("Change") {
                                isCapturingHyperKey = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    if !isCapturingHyperKey {
                        Text("Hold the hyper key + any other key to trigger your bound shortcuts.\nA quick tap of the hyper key still types the original character.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()

                // Window Management section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Window Management", systemImage: "rectangle.split.2x1")
                        .font(.title3.bold())

                    Picker("Gap between windows", selection: $windowGap) {
                        ForEach(WindowGap.allCases, id: \.self) { gap in
                            Text(gap.displayName).tag(gap)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: windowGap) { _, newValue in
                        newValue.save()
                    }

                    Text("Space between tiled windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Permissions section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Permissions", systemImage: "lock.shield")
                        .font(.title3.bold())

                    VStack(spacing: 8) {
                        permissionRow(
                            title: "Accessibility",
                            description: "Window management & menu bar reading",
                            granted: permissionManager.accessibilityGranted,
                            action: { PermissionManager.openAccessibilitySettings() }
                        )

                        permissionRow(
                            title: "Input Monitoring",
                            description: "Hyper key event tap",
                            granted: permissionManager.inputMonitoringGranted,
                            action: { PermissionManager.openInputMonitoringSettings() }
                        )
                    }

                    HStack {
                        Button {
                            permissionManager.checkPermissions()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        if !permissionManager.allPermissionsGranted {
                            Button("Restart App") {
                                permissionManager.restartApp()
                            }
                        }
                    }
                }

                Divider()

                // About section
                VStack(alignment: .leading, spacing: 8) {
                    Label("About", systemImage: "info.circle")
                        .font(.title3.bold())

                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(isCapturingHyperKey ? HyperKeyCaptureView(onCapture: { keyCode in
            isCapturingHyperKey = false
            if let kc = KeyCode(rawValue: keyCode) {
                onHyperKeyChanged?(kc)
            }
        }) : nil)
    }

    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Open Settings") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// NSView-based key capture that reads raw key codes via NSEvent monitoring.
struct HyperKeyCaptureView: NSViewRepresentable {
    let onCapture: (UInt16) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView(onCapture: onCapture)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class KeyCaptureNSView: NSView {
    let onCapture: (UInt16) -> Void

    init(onCapture: @escaping (UInt16) -> Void) {
        self.onCapture = onCapture
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onCapture(event.keyCode)
    }
}
