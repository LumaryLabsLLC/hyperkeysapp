import AppKit
import Shared

// MARK: - Sources

/// Where GIFs come from: a provider's GIFs or clips, or the ones you starred or used.
enum GifSource: String, CaseIterable, Codable, Sendable {
    case giphy
    case giphyClips
    case klipy
    case favorites
    case recent

    var title: String {
        switch self {
        case .giphy: "GIPHY GIFs"
        case .giphyClips: "GIPHY Clips"
        case .klipy: "Klipy"
        case .favorites: "Favorites"
        case .recent: "Recent"
        }
    }

    var symbol: String {
        switch self {
        case .giphy: "photo.stack"
        case .giphyClips: "film.stack"
        case .klipy: "sparkles.rectangle.stack"
        case .favorites: "star"
        case .recent: "clock"
        }
    }

    /// The service a search goes to; nil for Favorites and Recent.
    var provider: GifProvider? {
        switch self {
        case .giphy, .giphyClips: .giphy
        case .klipy: .klipy
        case .favorites, .recent: nil
        }
    }

    var searchPrompt: String {
        switch self {
        case .giphy: "Search GIFs on GIPHY…"
        case .giphyClips: "Search clips on GIPHY…"
        case .klipy: "Search GIFs on Klipy…"
        case .favorites: "Search your favorites…"
        case .recent: "Search recent GIFs…"
        }
    }

    static let providers: [GifSource] = [.giphy, .giphyClips, .klipy]
}

enum GifProvider: String, CaseIterable, Sendable {
    case giphy
    case klipy

    var name: String {
        switch self {
        case .giphy: "GIPHY"
        case .klipy: "Klipy"
        }
    }

    /// Where to sign up for a free key.
    var keyURL: URL {
        switch self {
        case .giphy: URL(string: "https://developers.giphy.com/dashboard/")!
        case .klipy: URL(string: "https://partner.klipy.com/")!
        }
    }

    var apiKey: String? {
        Keychain.string(for: "\(rawValue)-api-key").flatMap { $0.isEmpty ? nil : $0 }
    }

    func setAPIKey(_ key: String?) {
        Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: "\(rawValue)-api-key")
    }
}

// MARK: - GIFs

struct Gif: Identifiable, Codable, Hashable, Sendable {
    /// "<source>:<provider id>", unique across sources.
    let id: String
    let source: GifSource
    let title: String
    /// A small animated GIF for the grid.
    let previewURL: URL
    let previewWidth: Int
    let previewHeight: Int
    /// What gets copied: a GIF, or an MP4 for clips.
    let mediaURL: URL
    let pageURL: URL?

    var isVideo: Bool { mediaURL.pathExtension.lowercased() == "mp4" }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (isVideo ? "Clip" : "GIF") : trimmed
    }
}

struct GifPage: Sendable {
    let gifs: [Gif]
    /// Pass back to get the next page; nil at the end.
    let next: Int?
}

enum GifError: LocalizedError, Equatable {
    case missingKey(GifProvider)
    case badKey(GifProvider)
    case rateLimited(GifProvider)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "Add your \(provider.name) API key to search."
        case .badKey(let provider): "\(provider.name) didn't accept your API key. Check it in Settings."
        case .rateLimited(let provider): "\(provider.name)'s free key allows 100 searches an hour. Try again a little later."
        case .failed(let reason): reason
        }
    }
}

// MARK: - API

/// GIPHY and Klipy over HTTPS. Both want an API key; see `GifProvider.keyURL`.
enum GifAPI {
    static let pageSize = 40

    /// Trending when `query` is empty, otherwise search results.
    static func fetch(_ source: GifSource, query: String, page: Int, key: String) async throws -> GifPage {
        switch source {
        case .giphy, .giphyClips:
            return try await giphy(clips: source == .giphyClips, query: query, offset: page, key: key)
        case .klipy:
            return try await klipy(query: query, page: max(page, 1), key: key)
        case .favorites, .recent:
            return GifPage(gifs: [], next: nil)
        }
    }

    // MARK: GIPHY

    static func giphyURL(clips: Bool, query: String, offset: Int, key: String) -> URL {
        var components = URLComponents(string: "https://api.giphy.com/v1/\(clips ? "clips" : "gifs")/\(query.isEmpty ? "trending" : "search")")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "rating", value: "pg-13"),
        ] + (query.isEmpty ? [] : [URLQueryItem(name: "q", value: String(query.prefix(50))), URLQueryItem(name: "lang", value: "en")])
        return components.url!
    }

    private static func giphy(clips: Bool, query: String, offset: Int, key: String) async throws -> GifPage {
        let (data, response) = try await URLSession.shared.data(from: giphyURL(clips: clips, query: query, offset: offset, key: key))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw GifError.rateLimited(.giphy) }
        if status == 401 || status == 403 { throw GifError.badKey(.giphy) }
        guard status == 200 else { throw GifError.failed("GIPHY didn't answer (\(status)). Try again in a moment.") }
        return try parseGiphy(data, clips: clips, offset: offset)
    }

    static func parseGiphy(_ data: Data, clips: Bool, offset: Int) throws -> GifPage {
        struct Rendition: Decodable {
            let url: String?
            let width: String?
            let height: String?
            let size: String?
        }
        struct VideoAsset: Decodable {
            let url: String?
        }
        struct Item: Decodable {
            let id: String
            let title: String?
            let url: String?
            let images: [String: Rendition]?
            let video: Video?
            struct Video: Decodable {
                let assets: [String: VideoAsset]?
            }
        }
        struct Pagination: Decodable {
            let total_count: Int?
            let count: Int?
            let offset: Int?
        }
        struct Response: Decodable {
            let data: [Item]
            let pagination: Pagination?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let source: GifSource = clips ? .giphyClips : .giphy
        let gifs = response.data.compactMap { item -> Gif? in
            let images = item.images ?? [:]
            guard let preview = images["fixed_width"] ?? images["fixed_width_downsampled"] ?? images["downsized"],
                  let previewURL = preview.url.flatMap(URL.init(string:)) else { return nil }
            let media: URL?
            if clips {
                // Clips are videos with sound; copy a medium-size MP4.
                let assets = item.video?.assets ?? [:]
                media = ["720p", "540p", "480p", "360p", "1080p", "source"].lazy
                    .compactMap { assets[$0]?.url.flatMap(URL.init(string:)) }
                    .first
            } else {
                // The original unless it's huge; then GIPHY's under-2 MB version.
                let original = images["original"]
                let size = original?.size.flatMap(Int.init) ?? 0
                let pick = size > 8_000_000 ? (images["downsized"] ?? original) : original
                media = pick?.url.flatMap(URL.init(string:))
            }
            guard let media else { return nil }
            return Gif(
                id: "\(source.rawValue):\(item.id)", source: source, title: cleanTitle(item.title),
                previewURL: previewURL,
                previewWidth: preview.width.flatMap(Int.init) ?? 200, previewHeight: preview.height.flatMap(Int.init) ?? 200,
                mediaURL: media, pageURL: item.url.flatMap(URL.init(string:))
            )
        }
        let pagination = response.pagination
        let nextOffset = (pagination?.offset ?? offset) + (pagination?.count ?? response.data.count)
        let hasMore = (pagination?.count ?? 0) > 0 && nextOffset < min(pagination?.total_count ?? 0, 4999)
        return GifPage(gifs: gifs, next: hasMore ? nextOffset : nil)
    }

    /// GIPHY titles end in " GIF by someone"; the someone is kept, the word GIF isn't.
    static func cleanTitle(_ title: String?) -> String {
        guard var title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return "" }
        for suffix in [" GIF", " Gif"] where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        title = title.replacingOccurrences(of: " GIF by ", with: " · ")
        return title
    }

    // MARK: Klipy

    static func klipyURL(query: String, page: Int, key: String) -> URL {
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        var components = URLComponents(string: "https://api.klipy.com/api/v1/\(escaped)/gifs/\(query.isEmpty ? "trending" : "search")")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "format_filter", value: "gif"),
            URLQueryItem(name: "content_filter", value: "medium"),
            URLQueryItem(name: "customer_id", value: customerID),
        ] + (query.isEmpty ? [] : [URLQueryItem(name: "q", value: query)])
        return components.url!
    }

    private static func klipy(query: String, page: Int, key: String) async throws -> GifPage {
        let (data, response) = try await URLSession.shared.data(from: klipyURL(query: query, page: page, key: key))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw GifError.rateLimited(.klipy) }
        // Klipy answers a bad key with 404 and result: false.
        if status == 401 || status == 403 || status == 404 { throw GifError.badKey(.klipy) }
        guard status == 200 else { throw GifError.failed("Klipy didn't answer (\(status)). Try again in a moment.") }
        return try parseKlipy(data, page: page)
    }

    static func parseKlipy(_ data: Data, page: Int) throws -> GifPage {
        struct Format: Decodable {
            let url: String?
            let width: Int?
            let height: Int?
        }
        struct Variant: Decodable {
            let gif: Format?
        }
        struct Item: Decodable {
            let id: Int?
            let slug: String?
            let title: String?
            let type: String?
            let file: [String: Variant]?
        }
        struct List: Decodable {
            let data: [Item]
            let has_next: Bool?
        }
        struct Envelope: Decodable {
            let result: Bool?
            let data: List?
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.result != false, let list = envelope.data else { throw GifError.badKey(.klipy) }
        let gifs = list.data.compactMap { item -> Gif? in
            // Klipy mixes sponsored items into results; those are left out.
            guard item.type == "gif", let file = item.file else { return nil }
            func pick(_ order: [String]) -> Format? {
                order.lazy.compactMap { file[$0]?.gif }.first { $0.url != nil }
            }
            guard let preview = pick(["sm", "xs", "md", "hd"]), let previewURL = preview.url.flatMap(URL.init(string:)),
                  let full = pick(["md", "hd", "sm", "xs"]), let mediaURL = full.url.flatMap(URL.init(string:)) else { return nil }
            let slug = item.slug ?? item.id.map(String.init) ?? UUID().uuidString
            return Gif(
                id: "klipy:\(slug)", source: .klipy, title: item.title ?? "",
                previewURL: previewURL, previewWidth: preview.width ?? 200, previewHeight: preview.height ?? 200,
                mediaURL: mediaURL, pageURL: item.slug.flatMap { URL(string: "https://klipy.com/gifs/\($0)") }
            )
        }
        return GifPage(gifs: gifs, next: list.has_next == true ? page + 1 : nil)
    }

    /// Klipy asks for a per-person id; a random one, kept on this Mac, says nothing about you.
    static var customerID: String {
        let key = "gifCustomerID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

// MARK: - Favorites and recent

/// Starred and recently used GIFs, kept on this Mac (not in config.json).
@MainActor
@Observable
final class GifLibrary {
    static let shared = GifLibrary()

    private(set) var favorites: [Gif] = []
    private(set) var recent: [Gif] = []

    private static let file = "gifs.json"
    private static let recentLimit = 40

    private struct Stored: Codable {
        var favorites: [Gif]
        var recent: [Gif]
    }

    init() {
        if let stored = try? Persistence.load(Stored.self, from: Self.file) {
            favorites = stored.favorites
            recent = stored.recent
        }
    }

    func isFavorite(_ gif: Gif) -> Bool {
        favorites.contains { $0.id == gif.id }
    }

    func toggleFavorite(_ gif: Gif) {
        if isFavorite(gif) {
            favorites.removeAll { $0.id == gif.id }
        } else {
            favorites.insert(gif, at: 0)
        }
        save()
    }

    func noteUsed(_ gif: Gif) {
        recent.removeAll { $0.id == gif.id }
        recent.insert(gif, at: 0)
        recent = Array(recent.prefix(Self.recentLimit))
        save()
    }

    func clearRecent() {
        recent = []
        save()
    }

    private func save() {
        try? Persistence.save(Stored(favorites: favorites, recent: recent), to: Self.file)
    }
}

// MARK: - Media

/// Downloads previews (kept in memory) and the files that get copied (kept on disk, so a pasted
/// file stays valid).
@MainActor
enum GifMedia {
    private static let previews = NSCache<NSURL, NSImage>()

    static func cachedPreview(_ url: URL) -> NSImage? {
        previews.object(forKey: url as NSURL)
    }

    static func preview(_ url: URL) async -> NSImage? {
        if let cached = cachedPreview(url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return nil }
        previews.setObject(image, forKey: url as NSURL)
        return image
    }

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperKeys/GIFs", isDirectory: true)
    }

    /// The GIF or clip as a file named after its title, downloaded once.
    static func file(for gif: Gif) async throws -> URL {
        let name = fileName(for: gif)
        let folder = folder.appendingPathComponent(gif.id.replacingOccurrences(of: ":", with: "-"), isDirectory: true)
        let destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let (temporary, response) = try await URLSession.shared.download(from: gif.mediaURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GifError.failed("Couldn't download the \(gif.isVideo ? "clip" : "GIF"). Try again.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// "Mr Bean Waiting.gif": the title, safe for a file name.
    static func fileName(for gif: Gif) -> String {
        let base = gif.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.whitespaces))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(base.prefix(80)) + (gif.isVideo ? ".mp4" : ".gif")
    }

    /// Puts the file on the clipboard the way Finder does, plus the GIF itself for apps that take images.
    static func copy(_ file: URL, isVideo: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        if !isVideo, let data = try? Data(contentsOf: file) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        }
    }
}
