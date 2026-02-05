import AppSwitcher
import KeyBindings
import Shared
import SwiftUI

struct AppGroupsView: View {
    @Bindable var bindingStore: BindingStore
    @State private var appGroups: [AppGroup] = []
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var editingGroup: AppGroup?
    @State private var installedApps = InstalledAppProvider()

    private let appGroupsFile = "appGroups.json"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("App Groups")
                    .font(.headline)
                Spacer()
                Button("New Group", systemImage: "plus") {
                    showingNewGroup = true
                }
            }
            .padding()

            List {
                ForEach(appGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.name)
                                .font(.body.bold())
                            Spacer()
                            Text("\(group.appBundleIdentifiers.count) app\(group.appBundleIdentifiers.count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Button("Edit") {
                                editingGroup = group
                            }
                            .buttonStyle(.borderless)
                        }

                        if !group.appBundleIdentifiers.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(group.appBundleIdentifiers, id: \.self) { bundleId in
                                    let appInfo = installedApps.apps.first(where: { $0.bundleIdentifier == bundleId })
                                    HStack(spacing: 4) {
                                        if let icon = appInfo?.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 20, height: 20)
                                        }
                                        Text(appInfo?.name ?? bundleId)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            appGroups.removeAll { $0.id == group.id }
                            saveGroups()
                        }
                    }
                }
            }
        }
        .onAppear {
            loadGroups()
            installedApps.scan()
        }
        .alert("New App Group", isPresented: $showingNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") {
                guard !newGroupName.isEmpty else { return }
                appGroups.append(AppGroup(name: newGroupName))
                saveGroups()
                newGroupName = ""
            }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .sheet(item: $editingGroup) { group in
            AppGroupEditorView(
                group: group,
                installedApps: installedApps,
                onSave: { updated in
                    if let idx = appGroups.firstIndex(where: { $0.id == updated.id }) {
                        appGroups[idx] = updated
                        saveGroups()
                    }
                    editingGroup = nil
                },
                onCancel: { editingGroup = nil }
            )
        }
    }

    private func loadGroups() {
        appGroups = (try? Persistence.load([AppGroup].self, from: appGroupsFile)) ?? []
    }

    private func saveGroups() {
        try? Persistence.save(appGroups, to: appGroupsFile)
    }
}

struct AppGroupEditorView: View {
    @State var group: AppGroup
    let installedApps: InstalledAppProvider
    let onSave: (AppGroup) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit: \(group.name)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(group) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    Text(app.name)
                    Spacer()
                    if group.appBundleIdentifiers.contains(app.bundleIdentifier) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let idx = group.appBundleIdentifiers.firstIndex(of: app.bundleIdentifier) {
                        group.appBundleIdentifiers.remove(at: idx)
                    } else {
                        group.appBundleIdentifiers.append(app.bundleIdentifier)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return installedApps.apps }
        return installedApps.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
