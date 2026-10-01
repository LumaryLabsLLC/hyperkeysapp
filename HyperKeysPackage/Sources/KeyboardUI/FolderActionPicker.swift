import AppKit
import KeyBindings
import Shared
import SwiftUI

/// Open a folder (or file) in Finder: common folders in one click, anything else via a picker.
/// Paths are stored with "~" so the same config works on every Mac.
struct FolderActionPicker: View {
    let currentAction: BoundAction?
    let onAssign: (BoundAction) -> Void

    private var currentPath: String? {
        if case .openFolder(let path) = currentAction { return path }
        return nil
    }

    private var suggestions: [String] {
        let candidates = ["~", "~/Desktop", "~/Documents", "~/Downloads", "/Applications", "~/Developer", "~/Pictures", "~/Movies", "~/Music"]
        return candidates.filter { FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if let currentPath, !suggestions.contains(currentPath) {
                        PickerSectionHeader(title: "Current")
                        row(currentPath)
                    }
                    PickerSectionHeader(title: "Folders")
                    ForEach(suggestions, id: \.self) { row($0) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()
            HStack {
                Text("Opens in Finder. Files open in their usual app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…", action: choose)
                    .hkButtonStyle()
            }
            .padding(12)
        }
    }

    private func row(_ path: String) -> some View {
        let expanded = (path as NSString).expandingTildeInPath
        let name = expanded == NSHomeDirectory() ? "Home" : FileManager.default.displayName(atPath: expanded)
        let isCurrent = path == currentPath

        return PickerRow(title: name, subtitle: path, isSelected: isCurrent) {
            onAssign(.openFolder(path: path))
        } leading: {
            Image(nsImage: AppIconCache.icon(forPath: expanded))
                .resizable()
                .frame(width: 24, height: 24)
        } trailing: {
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder (or file) to open with this shortcut"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onAssign(.openFolder(path: (url.path as NSString).abbreviatingWithTildeInPath))
    }
}
