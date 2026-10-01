import EventEngine
import KeyBindings
import KeyboardUI
import SwiftUI
import UniformTypeIdentifiers

/// Brings snippets and Hyper shortcuts over from a Raycast export: pick the file, unlock it,
/// then choose what to keep.
struct RaycastImportSheet: View {
    @Bindable var bindingStore: BindingStore

    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case choose
        case unlock(Data, fileName: String)
        case review(RaycastImportPlan)
        case done(shortcuts: Int, snippets: Int)
    }

    @State private var step: Step = .choose
    @State private var snippetStore = SnippetStore.shared
    @State private var isPickingFile = false
    @State private var isDropTargeted = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var password = ""
    @State private var chosenShortcuts: Set<Int> = []
    @State private var chosenSnippets: Set<Int> = []
    @FocusState private var isPasswordFocused: Bool

    private static let fileTypes: [UTType] = [.json, UTType(filenameExtension: "rayconfig") ?? .data]

    var body: some View {
        Group {
            switch step {
            case .choose:
                chooseStep
            case .unlock(let data, let fileName):
                unlockStep(data, fileName: fileName)
            case .review(let plan):
                reviewStep(plan)
            case .done(let shortcuts, let snippets):
                doneStep(shortcuts: shortcuts, snippets: snippets)
            }
        }
        .frame(width: 600)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: Self.fileTypes) { result in
            if case .success(let url) = result { open(url) }
        }
    }

    // MARK: - Choose a file

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Import from Raycast", subtitle: "Bring over your snippets and Hyper shortcuts.")

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text("Drop a Raycast export here")
                    .font(.headline)
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Choose File…") { isPickingFile = true }
                        .hkProminentButtonStyle()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15))
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                open(url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            VStack(alignment: .leading, spacing: 14) {
                hint(
                    symbol: "keyboard",
                    title: "Shortcuts and snippets",
                    text: "In Raycast, run **Export Settings & Data** and pick the .rayconfig file it saves. You’ll need its password."
                )
                hint(
                    symbol: "text.quote",
                    title: "Just snippets",
                    text: "In Raycast, run **Export Snippets** and pick the .json file."
                )
            }

            errorLabel

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
    }

    private func hint(symbol: String, title: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Unlock

    private func unlockStep(_ data: Data, fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Enter the export password", subtitle: fileName)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isPasswordFocused)
                .onSubmit { unlock(data) }
                .disabled(isWorking)

            Text("It’s the password Raycast asked for when you exported. If you never set one, Raycast made one for you — find it in Raycast Settings → Extensions → Export Settings & Data.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            errorLabel

            HStack {
                Button("Back") {
                    errorMessage = nil
                    step = .choose
                }
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock") { unlock(data) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isWorking)
            }
        }
        .padding(24)
        .onAppear { isPasswordFocused = true }
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewStep(_ plan: RaycastImportPlan) -> some View {
        if plan.isEmpty {
            nothingToImport(plan)
        } else {
            VStack(spacing: 0) {
                header("Choose what to import", subtitle: summary(of: plan))
                    .padding(24)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        let hyper = plan.shortcuts.filter(\.usesHyper)
                        let other = plan.shortcuts.filter { !$0.usesHyper }
                        if !hyper.isEmpty {
                            group("Hyper Shortcuts", count: hyper.count) {
                                ForEach(hyper) { item in
                                    shortcutRow(item)
                                    if item.id != hyper.last?.id { Divider().padding(.leading, 14) }
                                }
                            }
                        }
                        if !other.isEmpty {
                            group(
                                "Other Shortcuts",
                                count: other.count,
                                note: "Raycast ran these with other keys. Turn one on to use it with Hyper instead."
                            ) {
                                ForEach(other) { item in
                                    shortcutRow(item)
                                    if item.id != other.last?.id { Divider().padding(.leading, 14) }
                                }
                            }
                        }
                        if !plan.snippets.isEmpty {
                            group("Snippets", count: plan.snippets.count, note: keywordNote(plan), trailing: AnyView(snippetSelectionButton(plan))) {
                                ForEach(plan.snippets) { item in
                                    snippetRow(item)
                                    if item.id != plan.snippets.last?.id { Divider().padding(.leading, 14) }
                                }
                            }
                        }
                        if !plan.skipped.isEmpty {
                            skippedList(plan.skipped)
                        }
                    }
                    .padding(24)
                }
                .frame(height: 420)

                Divider()

                HStack(spacing: 10) {
                    if !chosenShortcuts.isEmpty {
                        Text("Shortcuts go into your “\(bindingStore.activeProfileName)” profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(importTitle) { importChosen(plan) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosenShortcuts.isEmpty && chosenSnippets.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private func nothingToImport(_ plan: RaycastImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(
                "Nothing new to import",
                subtitle: plan.alreadyPresent > 0
                    ? "HyperKeys already has everything in this export it can use."
                    : "This export has no snippets or shortcuts HyperKeys can use."
            )
            if !plan.skipped.isEmpty {
                ScrollView {
                    skippedList(plan.skipped)
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Button("Back") { step = .choose }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func summary(of plan: RaycastImportPlan) -> String {
        var parts: [String] = []
        if !plan.shortcuts.isEmpty { parts.append(count(plan.shortcuts.count, "shortcut")) }
        if !plan.snippets.isEmpty { parts.append(count(plan.snippets.count, "snippet")) }
        var text = "Found \(parts.joined(separator: " and "))."
        if plan.alreadyPresent > 0 {
            text += " \(count(plan.alreadyPresent, "item")) \(plan.alreadyPresent == 1 ? "is" : "are") already in HyperKeys."
        }
        return text
    }

    private var importTitle: String {
        let total = chosenShortcuts.count + chosenSnippets.count
        return total == 0 ? "Import" : "Import \(count(total, "Item"))"
    }

    private func keywordNote(_ plan: RaycastImportPlan) -> String? {
        guard let keyword = plan.snippets.lazy.compactMap(\.keyword).first else { return nil }
        return "Keywords like “\(keyword)” come along too: type one anywhere and it turns into its snippet."
    }

    private func snippetSelectionButton(_ plan: RaycastImportPlan) -> some View {
        let all = Set(plan.snippets.map(\.id))
        let isAllChosen = chosenSnippets == all
        return Button(isAllChosen ? "Select None" : "Select All") {
            chosenSnippets = isAllChosen ? [] : all
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private func group<Rows: View>(
        _ title: String,
        count: Int,
        note: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                Spacer()
                trailing
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                rows()
            }
            .hkCard()
        }
    }

    private func shortcutRow(_ item: RaycastImportPlan.Shortcut) -> some View {
        let presentation = BindingPresentation(item.action)
        let title = presentation?.title ?? item.raycastTitle
        var detail = "In Raycast: \(item.raycastShortcut)"
        if item.raycastTitle != title {
            detail += " · \(item.raycastTitle)"
        }

        return CheckRow(isOn: shortcutBinding(item)) {
            HyperComboView(hyperKey: bindingStore.hyperKeyCode, key: item.key, height: 22)
                .frame(width: 92, alignment: .leading)
            if let presentation {
                BindingIcon(presentation: presentation, size: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let replacing = item.replacing.flatMap(BindingPresentation.init) {
                Text("Replaces \(replacing.title)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func snippetRow(_ item: RaycastImportPlan.SnippetItem) -> some View {
        CheckRow(isOn: snippetBinding(item)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.snippet.name)
                    .lineLimit(1)
                Text(item.snippet.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let original = item.originalName {
                    Text("Renamed — you already have a snippet called “\(original)”")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !item.unsupportedPlaceholders.isEmpty {
                    Text("\(ListFormatter.localizedString(byJoining: item.unsupportedPlaceholders)) will paste as written")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func skippedList(_ skipped: [RaycastImportPlan.Skipped]) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(skipped) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.raycastShortcut)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if item.id != skipped.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .hkCard()
            .padding(.top, 8)
        } label: {
            Text("Not imported (\(skipped.count))")
                .font(.headline)
        }
    }

    // MARK: - Done

    private func doneStep(shortcuts: Int, snippets: Int) -> some View {
        var parts: [String] = []
        if shortcuts > 0 { parts.append(count(shortcuts, "shortcut")) }
        if snippets > 0 { parts.append(count(snippets, "snippet")) }

        return VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("Imported \(parts.joined(separator: " and "))")
                .font(.title3.weight(.semibold))
            Text("They’re saved in config.json with the rest of your settings.")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .hkProminentButtonStyle()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }

    // MARK: - Pieces

    private func header(_ title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: "square.and.arrow.down.on.square", color: .red, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    // MARK: - Selection

    private func shortcutBinding(_ item: RaycastImportPlan.Shortcut) -> Binding<Bool> {
        Binding(
            get: { chosenShortcuts.contains(item.id) },
            set: { isOn in
                guard case .review(let plan) = step else { return }
                if isOn {
                    // One action per key: choosing this one drops any other choice for the same key.
                    let sameKey = plan.shortcuts.filter { $0.key == item.key }.map(\.id)
                    chosenShortcuts.subtract(sameKey)
                    chosenShortcuts.insert(item.id)
                } else {
                    chosenShortcuts.remove(item.id)
                }
            }
        )
    }

    private func snippetBinding(_ item: RaycastImportPlan.SnippetItem) -> Binding<Bool> {
        Binding(
            get: { chosenSnippets.contains(item.id) },
            set: { isOn in
                if isOn { chosenSnippets.insert(item.id) } else { chosenSnippets.remove(item.id) }
            }
        )
    }

    // MARK: - Actions

    private func open(_ url: URL) {
        errorMessage = nil
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Couldn’t read “\(url.lastPathComponent)”."
            return
        }
        if RaycastArchive.needsPassword(data) {
            password = ""
            step = .unlock(data, fileName: url.lastPathComponent)
        } else {
            read(data, password: nil)
        }
    }

    private func unlock(_ data: Data) {
        guard !password.isEmpty, !isWorking else { return }
        read(data, password: password)
    }

    private func read(_ data: Data, password: String?) {
        isWorking = true
        errorMessage = nil
        Task {
            // Unlocking runs scrypt over 16 MB, so keep it off the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try RaycastArchive.read(data, password: password) }
            }.value
            isWorking = false
            switch result {
            case .success(let export):
                review(export)
            case .failure(let error):
                errorMessage = error.localizedDescription
                if case .unlock = step {
                    isPasswordFocused = true
                }
            }
        }
    }

    private func review(_ export: RaycastExport) {
        let plan = RaycastImportPlan(
            export: export,
            hyperKey: bindingStore.hyperKeyCode,
            existingBindings: bindingStore.activeBindings,
            existingSnippets: snippetStore.snippets
        )
        password = ""
        chosenShortcuts = plan.suggestedShortcuts
        chosenSnippets = Set(plan.snippets.map(\.id))
        step = .review(plan)
    }

    private func importChosen(_ plan: RaycastImportPlan) {
        let result = plan.apply(
            shortcuts: chosenShortcuts,
            snippets: chosenSnippets,
            bindingStore: bindingStore,
            snippetStore: snippetStore
        )
        withAnimation(.snappy) {
            step = .done(shortcuts: result.shortcuts, snippets: result.snippets)
        }
    }
}

/// A list row led by a checkbox; clicking anywhere on the row toggles it.
private struct CheckRow<Content: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
        .opacity(isOn ? 1 : 0.6)
    }
}
