import KeyBindings
import KeyboardUI
import SwiftUI

struct ProfilesView: View {
    @Bindable var bindingStore: BindingStore
    @State private var showingNewProfile = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Action Profiles")
                    .font(.headline)
                Spacer()
                Button("New Profile", systemImage: "plus") {
                    showingNewProfile = true
                }
            }
            .padding()

            List {
                profileRow(
                    icon: "keyboard",
                    name: "Default",
                    bindingCount: bindingStore.bindings.count,
                    isActive: bindingStore.activeGroupId == nil
                ) {
                    bindingStore.setActiveGroup(nil)
                }

                ForEach(bindingStore.actionGroups) { group in
                    profileRow(
                        icon: group.icon,
                        name: group.name,
                        bindingCount: group.bindings.count,
                        isActive: bindingStore.activeGroupId == group.id
                    ) {
                        bindingStore.setActiveGroup(group.id)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            bindingStore.deleteGroup(group.id)
                        }
                    }
                }
            }
        }
        .alert("New Profile", isPresented: $showingNewProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                guard !newProfileName.isEmpty else { return }
                bindingStore.addGroup(ActionGroup(name: newProfileName))
                newProfileName = ""
            }
            Button("Cancel", role: .cancel) { newProfileName = "" }
        }
    }

    private func profileRow(
        icon: String,
        name: String,
        bindingCount: Int,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(isActive ? .semibold : .regular))
                Text("\(bindingCount) binding\(bindingCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
