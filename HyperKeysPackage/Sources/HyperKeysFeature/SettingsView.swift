import AppKit
import KeyBindings
import KeyboardUI
import Permissions
import ServiceManagement
import Shared
import SwiftUI

struct SettingsView: View {
    @Bindable var bindingStore: BindingStore
    let permissionManager: PermissionManager
    let status: HyperKeyStatus
    let onPauseChanged: (Bool) -> Void

    @AppStorage(Preferences.doubleTapOpensWindow) private var doubleTapOpensWindow = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var config = ConfigStore.shared
    @State private var isChoosingICloudCopy = false
    @State private var syncError: String?
    @State private var isImportingFromRaycast = false
    @State private var isConfirmingReset = false
    @State private var didReset = false
    @State private var resetBackup: URL?

    var body: some View {
        Form {
            Section {
                PageHeader(pane: .settings, subtitle: "Startup, your config file and iCloud sync, permissions and app info.")
                    .padding(.vertical, 4)
            }

            Section("General") {
                Toggle("Launch HyperKeys at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Toggle("Double-tap the Hyper Key to open this window", isOn: $doubleTapOpensWindow)
                Toggle("Pause all shortcuts", isOn: Binding(get: { status.isPaused }, set: { onPauseChanged($0) }))
            }

            configurationSection

            Section {
                PermissionRow(
                    symbol: "accessibility",
                    color: .blue,
                    title: "Accessibility",
                    detail: "Move windows and read app menus.",
                    isGranted: permissionManager.accessibilityGranted
                ) {
                    permissionManager.requestAccessibility()
                    PermissionManager.openAccessibilitySettings()
                }
                PermissionRow(
                    symbol: "keyboard.fill",
                    color: .orange,
                    title: "Input Monitoring",
                    detail: "Notice when you hold the Hyper Key.",
                    isGranted: permissionManager.inputMonitoringGranted
                ) {
                    permissionManager.requestInputMonitoring()
                    PermissionManager.openInputMonitoringSettings()
                }
            } header: {
                Text("Permissions")
            } footer: {
                HStack {
                    if !permissionManager.allPermissionsGranted {
                        Text("Granted access but it still says “Not granted”? Restart HyperKeys.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Again", systemImage: "arrow.clockwise") {
                        permissionManager.checkPermissions()
                    }
                    if !permissionManager.allPermissionsGranted {
                        Button("Restart HyperKeys") { permissionManager.restartApp() }
                    }
                }
                .font(.caption)
            }

            Section {
                LabeledContent {
                    Button("Reset…", role: .destructive) { isConfirmingReset = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset all settings")
                        Text("Go back to the shortcuts and settings HyperKeys starts with.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HyperKeys")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let logoURL = Bundle.module.url(forResource: "lumary-logo", withExtension: "svg"),
                       let logo = NSImage(contentsOf: logoURL) {
                        Link(destination: URL(string: "https://lumarylabs.com/")!) {
                            Image(nsImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 40)
                        }
                        .buttonStyle(.plain)
                        .help("Lumary Labs")
                    }
                }
                LabeledContent("Source code") {
                    Link("github.com/LumaryLabsLLC/hyperkeysapp", destination: URL(string: "https://github.com/LumaryLabsLLC/hyperkeysapp")!)
                }
                LabeledContent("Made by") {
                    Link("Lumary Labs", destination: URL(string: "https://lumarylabs.com/")!)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isImportingFromRaycast) {
            RaycastImportSheet(bindingStore: bindingStore)
        }
        .confirmationDialog("HyperKeys settings are already in iCloud", isPresented: $isChoosingICloudCopy) {
            Button("Use the Settings in iCloud") { enableICloudSync(keepingICloudCopy: true) }
            Button("Use This Mac's Settings") { enableICloudSync(keepingICloudCopy: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Another Mac already syncs HyperKeys. Choose which settings all your Macs should use.")
        }
        .alert("iCloud Sync", isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncError ?? "")
        }
        .confirmationDialog("Reset all settings?", isPresented: $isConfirmingReset) {
            Button("Reset Settings", role: .destructive) { reset(includingContent: false) }
            Button("Reset Everything", role: .destructive) { reset(includingContent: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetMessage)
        }
        .alert("Settings reset", isPresented: $didReset, presenting: resetBackup) { backup in
            Button("Show Old Config") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
            Button("OK", role: .cancel) {}
        } message: { _ in
            Text("Your old config.json was saved, in case you want something back.")
        }
        .alert("Couldn't change login item", isPresented: Binding(get: { loginItemError != nil }, set: { if !$0 { loginItemError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
        .onAppear {
            permissionManager.checkPermissions()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        Section {
            LabeledContent {
                HStack {
                    Button("Open") { NSWorkspace.shared.open(config.resolvedURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([config.resolvedURL]) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Config file")
                    Text((config.fileURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let error = config.loadError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Try Again") { config.reload(force: true) }
                }
            }

            if !config.warnings.isEmpty {
                DisclosureGroup {
                    ForEach(config.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("\(config.warnings.count) part\(config.warnings.count == 1 ? " was" : "s were") skipped", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }

            Toggle(isOn: iCloudSyncBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with iCloud Drive")
                    Text(iCloudDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isLinkedElsewhere)

            LabeledContent {
                Button("Import…") { isImportingFromRaycast = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Raycast")
                    Text("Bring over your snippets and Hyper shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Configuration")
        } footer: {
            Text("Everything you set up here is saved to this file. Edit it by hand or keep it in your dotfiles — symlinks are followed, and HyperKeys reloads it whenever it changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resetMessage: String {
        var message = "Your shortcuts, Hyper Key, aliases, profiles and options go back to how HyperKeys starts. "
            + "Reset Everything also deletes your snippets, quicklinks and clipboard history. "
            + "A copy of config.json is saved first."
        if config.location == .iCloud {
            message += " Your other Macs syncing with iCloud get the reset too."
        }
        return message
    }

    private func reset(includingContent: Bool) {
        resetBackup = SettingsReset.resetAll(includingContent: includingContent)
        onPauseChanged(false)
        // Let the confirmation close before the next alert opens.
        DispatchQueue.main.async { didReset = resetBackup != nil }
    }

    private var isLinkedElsewhere: Bool {
        if case .linked = config.location { return true }
        return false
    }

    private var iCloudDetail: String {
        switch config.location {
        case .iCloud: "On — config.json lives in iCloud Drive › HyperKeys and stays the same on all your Macs."
        case .linked(let path): "config.json links to \(path). Sync it from there, like the rest of your dotfiles."
        case .local: "Keep the same shortcuts and settings on all your Macs."
        }
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { config.location == .iCloud },
            set: { enabled in
                if enabled {
                    if config.iCloudHasConfig {
                        isChoosingICloudCopy = true
                    } else {
                        enableICloudSync(keepingICloudCopy: false)
                    }
                } else {
                    do {
                        try config.disableICloudSync()
                    } catch {
                        syncError = error.localizedDescription
                    }
                }
            }
        )
    }

    private func enableICloudSync(keepingICloudCopy: Bool) {
        do {
            try config.enableICloudSync(keepingICloudCopy: keepingICloudCopy)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let isEnabled = SMAppService.mainApp.status == .enabled
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = isEnabled
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button("Grant Access…", action: onGrant)
                    .hkProminentButtonStyle()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
