import AppKit
import Observation

/// Website icons for links, fetched from the site itself (never a third-party service) and
/// kept on disk, so each site is asked once. Views that read an icon redraw when it arrives.
@MainActor
@Observable
public final class FaviconCache {
    public static let shared = FaviconCache()

    private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let session: URLSession

    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperKeys/Favicons", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh) HyperKeys"]
        session = URLSession(configuration: configuration)
    }

    /// The icon for `host` ("github.com") if it's ready. The first call starts fetching it.
    public func icon(forHost host: String) -> NSImage? {
        let key = host.lowercased()
        if let icon = icons[key] { return icon }
        if !requested.contains(key) {
            requested.insert(key)
            Task { await load(key) }
        }
        return nil
    }

    private func load(_ host: String) async {
        let file = folder.appendingPathComponent("\(host).png")
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            icons[host] = image
            return
        }
        guard let image = await fetch(host) else { return }
        icons[host] = image
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
    }

    /// Icons the page declares (largest first), then the usual file names.
    private func fetch(_ host: String) async -> NSImage? {
        guard let base = URL(string: "https://\(host)/") else { return nil }
        var candidates: [URL] = []
        if let (data, response) = try? await session.data(from: base), data.count < 2_000_000 {
            let page = String(decoding: data, as: UTF8.self)
            candidates += Self.declaredIcons(in: page, base: response.url ?? base)
        }
        candidates += ["apple-touch-icon.png", "favicon.ico"].compactMap { URL(string: $0, relativeTo: base) }

        for url in candidates {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = NSImage(data: data), image.isValid, image.size.width >= 16
            else { continue }
            return image
        }
        return nil
    }

    /// `<link rel="icon" …>` and `<link rel="apple-touch-icon" …>`, biggest first; SVGs last.
    static func declaredIcons(in html: String, base: URL) -> [URL] {
        var found: [(url: URL, score: Int)] = []
        for tag in html.matches(of: #/<link\b[^>]*>/#.ignoresCase()) {
            let text = String(tag.output)
            guard let rel = attribute("rel", in: text)?.lowercased(), rel.contains("icon"),
                  !rel.contains("mask-icon"),
                  let href = attribute("href", in: text), let url = URL(string: href, relativeTo: base)?.absoluteURL
            else { continue }
            let size = attribute("sizes", in: text)?.split(separator: "x").first.flatMap { Int($0) } ?? (rel.contains("apple") ? 180 : 32)
            let score = href.lowercased().hasSuffix(".svg") ? -1 : size
            found.append((url, score))
        }
        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try? Regex<(Substring, Substring)>("\(name)\\s*=\\s*[\"']([^\"']*)[\"']").ignoresCase()
        guard let pattern, let match = tag.firstMatch(of: pattern) else { return nil }
        return String(match.output.1)
    }
}
