import AppKit
import KeyboardUI
import SwiftUI

// MARK: - Model

struct GifSection: Identifiable {
    let title: String
    let gifs: [Gif]
    var id: String { title }
}

@MainActor
@Observable
final class GifSearchModel {
    static let columns = 5

    var source: GifSource = GifSearchModel.savedSource {
        didSet {
            guard source != oldValue else { return }
            UserDefaults.standard.set(source.rawValue, forKey: Self.sourceKey)
            reload()
        }
    }
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    var selection = 0
    var targetAppName: String?
    private(set) var sections: [GifSection] = []
    private(set) var isLoading = false
    private(set) var error: GifError?
    /// The GIF being downloaded to copy or paste.
    var busyID: String?
    private(set) var focusRequest = 0
    /// Bumped when a key is saved, so the view refreshes "add a key" screens.
    private(set) var keyVersion = 0

    private(set) var flat: [Gif] = []
    private var rows: [[Int]] = []
    private var results: [Gif] = []
    private var next: Int?
    private var task: Task<Void, Never>?
    private var generation = 0

    private static let sourceKey = "gifSearchSource"
    private static var savedSource: GifSource {
        UserDefaults.standard.string(forKey: sourceKey).flatMap(GifSource.init) ?? .giphy
    }

    var library: GifLibrary { .shared }

    /// The provider whose key is missing for the current source, if any.
    var missingKey: GifProvider? {
        _ = keyVersion
        guard let provider = source.provider, provider.apiKey == nil else { return nil }
        return provider
    }

    var selectedGif: Gif? {
        flat.indices.contains(selection) ? flat[selection] : nil
    }

    func prepare() {
        query = ""
        reload()
        focusRequest += 1
    }

    func requestFocus() {
        focusRequest += 1
    }

    func saveKey(_ key: String, for provider: GifProvider) {
        provider.setAPIKey(key)
        saveKeyChanged()
    }

    /// A key was added or changed (here or in Settings).
    func saveKeyChanged() {
        keyVersion += 1
        reload()
    }

    // MARK: Loading

    func reload() {
        task?.cancel()
        generation += 1
        results = []
        next = nil
        error = nil
        isLoading = false
        selection = 0
        guard let provider = source.provider else {
            rebuild()
            return
        }
        guard let key = provider.apiKey else {
            rebuild()
            return
        }
        load(page: source == .klipy ? 1 : 0, key: key)
    }

    /// The next page, when the grid scrolls near its end.
    func loadMoreIfNeeded(after gif: Gif) {
        guard let next, !isLoading, let key = source.provider?.apiKey,
              let index = results.firstIndex(of: gif), index >= results.count - Self.columns * 2 else { return }
        load(page: next, key: key)
    }

    private func load(page: Int, key: String) {
        isLoading = true
        let generation = self.generation
        let source = self.source
        let query = self.query.trimmingCharacters(in: .whitespaces)
        task = Task {
            do {
                let result = try await GifAPI.fetch(source, query: query, page: page, key: key)
                guard generation == self.generation else { return }
                let known = Set(results.map(\.id))
                results += result.gifs.filter { !known.contains($0.id) }
                next = result.next
            } catch is CancellationError {
                return
            } catch let gifError as GifError {
                guard generation == self.generation else { return }
                error = gifError
            } catch {
                guard generation == self.generation else { return }
                if (error as? URLError)?.code == .cancelled { return }
                self.error = .failed("Couldn't reach \(source.provider?.name ?? "the server"). Check your connection.")
            }
            isLoading = false
            rebuild()
        }
    }

    private func scheduleSearch() {
        guard source.provider != nil else {
            selection = 0
            rebuild()
            return
        }
        task?.cancel()
        generation += 1
        let generation = self.generation
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, generation == self.generation else { return }
            reload()
        }
    }

    // MARK: Sections

    private func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matching(_ gifs: [Gif]) -> [Gif] {
            needle.isEmpty ? gifs : gifs.filter { $0.title.lowercased().contains(needle) }
        }
        switch source {
        case .favorites:
            sections = [GifSection(title: "Favorites", gifs: matching(library.favorites))]
        case .recent:
            sections = [GifSection(title: "Recent", gifs: matching(library.recent))]
        case .giphy, .giphyClips, .klipy:
            if needle.isEmpty {
                let recent = Array(library.recent.filter { $0.source == source }.prefix(Self.columns))
                sections = [
                    GifSection(title: "Recent", gifs: recent),
                    GifSection(title: "Trending", gifs: results),
                ]
            } else {
                sections = [GifSection(title: "Results", gifs: results)]
            }
        }
        sections = sections.filter { !$0.gifs.isEmpty }

        flat = sections.flatMap(\.gifs)
        rows = []
        var offset = 0
        for section in sections {
            for start in stride(from: 0, to: section.gifs.count, by: Self.columns) {
                rows.append(Array((offset + start)..<(offset + min(start + Self.columns, section.gifs.count))))
            }
            offset += section.gifs.count
        }
        selection = min(selection, max(flat.count - 1, 0))
    }

    /// Favorites and Recent change outside a search; refresh them in place.
    func libraryChanged() {
        if source.provider == nil || query.isEmpty {
            rebuild()
        }
    }

    // MARK: Moving

    enum Move { case left, right, up, down }

    func move(_ move: Move) {
        guard !flat.isEmpty else { return }
        switch move {
        case .left:
            selection = max(selection - 1, 0)
        case .right:
            selection = min(selection + 1, flat.count - 1)
        case .up, .down:
            guard let row = rows.firstIndex(where: { $0.contains(selection) }),
                  let column = rows[row].firstIndex(of: selection) else { return }
            let target = row + (move == .down ? 1 : -1)
            guard rows.indices.contains(target) else { return }
            selection = rows[target][min(column, rows[target].count - 1)]
        }
        if let gif = selectedGif {
            loadMoreIfNeeded(after: gif)
        }
    }

    func cycleSource(forward: Bool) {
        let all = GifSource.allCases
        guard let index = all.firstIndex(of: source) else { return }
        source = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }
}

// MARK: - Controller

/// Raycast-style GIF search. Return copies the GIF (or clip), ⌘Return pastes it into the app
/// you were in, ⌘F stars it, ⇥ switches source.
@MainActor
public final class GifSearchController {
    public static let shared = GifSearchController()

    let model = GifSearchModel()
    private var host: FloatingPanelHost?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    public func warmUp() {
        _ = makeHostIfNeeded()
    }

    public func show(returningTo app: NSRunningApplication? = nil) {
        let host = makeHostIfNeeded()
        model.prepare()
        host.show(returningTo: app)
        model.targetAppName = host.previousApp?.localizedName
        DispatchQueue.main.async { [model] in
            model.requestFocus()
        }
    }

    public func hide() {
        host?.hide(restoringFocus: true)
    }

    /// Downloads the GIF, puts it on the clipboard, and (when `paste`) pastes it into the app you were in.
    func deliver(_ gif: Gif, paste: Bool) {
        guard model.busyID == nil else { return }
        model.busyID = gif.id
        Task {
            defer { model.busyID = nil }
            do {
                let file = try await GifMedia.file(for: gif)
                GifMedia.copy(file, isVideo: gif.isVideo)
                GifLibrary.shared.noteUsed(gif)
                model.libraryChanged()
                host?.hide(restoringFocus: true)
                if paste {
                    TextPaster.pasteSoon()
                }
            } catch {
                NSSound.beep()
            }
        }
    }

    func toggleFavorite(_ gif: Gif) {
        GifLibrary.shared.toggleFavorite(gif)
        model.libraryChanged()
    }

    func openPage(_ gif: Gif) {
        guard let url = gif.pageURL else { return }
        host?.hide(restoringFocus: false)
        NSWorkspace.shared.open(url)
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = GifSearchView(
            model: model,
            onDeliver: { [weak self] gif, paste in self?.deliver(gif, paste: paste) },
            onToggleFavorite: { [weak self] gif in self?.toggleFavorite(gif) },
            onOpenPage: { [weak self] gif in self?.openPage(gif) }
        )
        let host = FloatingPanelHost(width: GifSearchView.width, rootView: root)
        host.topFraction = 0.14
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // escape
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 48: // tab
            model.cycleSource(forward: !flags.contains(.shift))
            return true
        default:
            break
        }
        // With no GIFs on screen (adding a key, an error), keys belong to the text fields.
        guard let gif = model.selectedGif else { return false }
        switch event.keyCode {
        case 123: model.move(.left); return true
        case 124: model.move(.right); return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        case 36, 76: // return, enter
            deliver(gif, paste: flags.contains(.command))
            return true
        default:
            break
        }
        guard flags == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case "f":
            toggleFavorite(gif)
            return true
        case "o":
            openPage(gif)
            return true
        default:
            return false
        }
    }
}

// MARK: - View

struct GifSearchView: View {
    @Bindable var model: GifSearchModel
    let onDeliver: (Gif, _ paste: Bool) -> Void
    let onToggleFavorite: (Gif) -> Void
    let onOpenPage: (Gif) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var library = GifLibrary.shared

    static let tile: CGFloat = 150
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
    static var width: CGFloat {
        let columns = CGFloat(GifSearchModel.columns)
        return columns * tile + (columns - 1) * spacing + padding * 2
    }

    private let contentHeight: CGFloat = 470
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .frame(height: contentHeight)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(FloatingPanelChrome(shape: shape))
        .onChange(of: model.focusRequest) {
            isSearchFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(model.source.searchPrompt, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .focused($isSearchFocused)
            Menu {
                ForEach(GifSource.providers, id: \.self) { source in
                    Button(source.title, systemImage: source.symbol) { model.source = source }
                }
                Divider()
                Button(GifSource.favorites.title, systemImage: GifSource.favorites.symbol) { model.source = .favorites }
                Button(GifSource.recent.title, systemImage: GifSource.recent.symbol) { model.source = .recent }
            } label: {
                Label(model.source.title, systemImage: model.source.symbol)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Switch source (⇥)")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let provider = model.missingKey {
            GifKeySetup(provider: provider) { model.saveKey($0, for: provider) }
        } else if let error = model.error, model.sections.isEmpty {
            message(symbol: "exclamationmark.triangle", title: error.localizedDescription) {
                Button("Try Again") { model.reload() }
            }
        } else if model.sections.isEmpty {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                message(symbol: model.source.symbol, title: emptyText) { EmptyView() }
            }
        } else {
            grid
        }
    }

    private var emptyText: String {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        switch model.source {
        case .favorites: return query.isEmpty ? "Star a GIF with ⌘F to keep it here." : "No favorites match “\(query)”."
        case .recent: return query.isEmpty ? "GIFs you copy or paste show up here." : "No recent GIFs match “\(query)”."
        default: return query.isEmpty ? "Nothing trending right now." : "No GIFs for “\(query)”."
        }
    }

    private func message<Actions: View>(symbol: String, title: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.spacing, alignment: .top), count: GifSearchModel.columns)
        var offsets: [Int] = []
        var running = 0
        for section in model.sections {
            offsets.append(running)
            running += section.gifs.count
        }

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                        Text(section.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, index == 0 ? 0 : 12)
                            .padding(.horizontal, 2)
                        LazyVGrid(columns: columns, spacing: Self.spacing) {
                            ForEach(Array(section.gifs.enumerated()), id: \.offset) { position, gif in
                                let global = offsets[index] + position
                                GifTile(
                                    gif: gif,
                                    isSelected: global == model.selection,
                                    isFavorite: library.isFavorite(gif),
                                    isBusy: model.busyID == gif.id
                                )
                                .id(global)
                                .onTapGesture {
                                    model.selection = global
                                    onDeliver(gif, false)
                                }
                                .onAppear { model.loadMoreIfNeeded(after: gif) }
                                .contextMenu {
                                    Button("Copy", systemImage: "doc.on.doc") { onDeliver(gif, false) }
                                    Button("Paste", systemImage: "arrow.down.doc") { onDeliver(gif, true) }
                                    Button(library.isFavorite(gif) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
                                        onToggleFavorite(gif)
                                    }
                                    if gif.pageURL != nil {
                                        Button("Open in Browser", systemImage: "safari") { onOpenPage(gif) }
                                    }
                                }
                            }
                        }
                    }
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(Self.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) {
                proxy.scrollTo(model.selection)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let provider = model.source.provider {
                Text("Powered by \(provider == .giphy ? "GIPHY" : "KLIPY")")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            } else if let gif = model.selectedGif {
                Text(gif.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.busyID != nil {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let gif = model.selectedGif {
                action(gif.isVideo ? "Copy Clip" : "Copy GIF", keys: ["↩"])
                action(model.targetAppName.map { "Paste to \($0)" } ?? "Paste", keys: ["⌘", "↩"])
                action(library.isFavorite(gif) ? "Unstar" : "Star", keys: ["⌘", "F"])
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private func action(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ForEach(keys, id: \.self) { KeycapChip($0, height: 18) }
        }
    }
}

// MARK: - Tile

private struct GifTile: View {
    let gif: Gif
    let isSelected: Bool
    let isFavorite: Bool
    let isBusy: Bool

    @State private var image: NSImage?

    private let size = GifSearchView.tile
    private let corner: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let image {
                    AnimatedImage(image: image)
                        .frame(width: fill.width, height: fill.height)
                        .frame(width: size, height: size)
                        .clipShape(.rect(cornerRadius: corner, style: .continuous))
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(5)
                        .background(.black.opacity(0.45), in: .circle)
                        .padding(6)
                }
                if gif.isVideo {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: .circle)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.3), in: .rect(cornerRadius: corner, style: .continuous))
                }
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Brand.purple, lineWidth: isSelected ? 3 : 0)
            )
            Text(gif.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: size, alignment: .leading)
        }
        .contentShape(.rect)
        .help(gif.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gif.displayTitle)
        .task(id: gif.previewURL) {
            image = GifMedia.cachedPreview(gif.previewURL)
            if image == nil {
                image = await GifMedia.preview(gif.previewURL)
            }
        }
    }

    /// The preview scaled to cover the square tile.
    private var fill: CGSize {
        let width = CGFloat(max(gif.previewWidth, 1))
        let height = CGFloat(max(gif.previewHeight, 1))
        let scale = max(size / width, size / height)
        return CGSize(width: (width * scale).rounded(.up), height: (height * scale).rounded(.up))
    }
}

/// An animated GIF; SwiftUI's Image shows only the first frame.
private struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleAxesIndependently
        view.imageFrameStyle = .none
        view.isEditable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
    }
}

// MARK: - Adding a key

/// Shown in the panel until there's a key for the chosen source.
struct GifKeySetup: View {
    let provider: GifProvider
    let onSave: (String) -> Void

    @State private var key = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Add your \(provider.name) API key")
                .font(.headline)
            Text("\(provider.name) needs a free key for searches. Create one at \(provider.keyURL.host() ?? provider.name), then paste it here. It's kept in your keychain on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 8) {
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Link("Get a Free Key", destination: provider.keyURL)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        key = ""
    }
}

// MARK: - Settings

/// The GIPHY and Klipy keys, on the Search & Switch page.
struct GifKeysEditor: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(GifProvider.allCases, id: \.self) { provider in
                GifKeyRow(provider: provider)
            }
        }
    }
}

private struct GifKeyRow: View {
    let provider: GifProvider

    @State private var hasKey = false
    @State private var isEditing = false
    @State private var key = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.name)
                .font(.callout.weight(.medium))
                .frame(width: 52, alignment: .leading)
            if hasKey, !isEditing {
                Label("Key saved", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                Button("Change") { isEditing = true }
                    .controlSize(.small)
                Button("Remove", role: .destructive) {
                    provider.setAPIKey(nil)
                    refresh()
                }
                .controlSize(.small)
            } else {
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 220)
                    .onSubmit(save)
                Button("Save", action: save)
                    .controlSize(.small)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get a free key", destination: provider.keyURL)
                    .font(.caption)
            }
        }
        .onAppear(perform: refresh)
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        provider.setAPIKey(trimmed)
        key = ""
        refresh()
        GifSearchController.shared.model.saveKeyChanged()
    }

    private func refresh() {
        hasKey = provider.apiKey != nil
        isEditing = false
    }
}
