import Foundation
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings

@MainActor
struct GifAPITests {
    private let giphyGifs = #"""
    { "data": [
        { "id": "abc", "title": "Mr Bean Waiting GIF by Working Title", "url": "https://giphy.com/gifs/abc",
          "images": {
            "fixed_width": { "url": "https://media.giphy.com/abc/200w.gif", "width": "200", "height": "150" },
            "original": { "url": "https://media.giphy.com/abc/giphy.gif", "width": "480", "height": "360", "size": "1200000" },
            "downsized": { "url": "https://media.giphy.com/abc/giphy-downsized.gif", "size": "900000" } } },
        { "id": "big", "title": "Huge GIF", "url": "https://giphy.com/gifs/big",
          "images": {
            "fixed_width": { "url": "https://media.giphy.com/big/200w.gif", "width": "200", "height": "200" },
            "original": { "url": "https://media.giphy.com/big/giphy.gif", "size": "12000000" },
            "downsized": { "url": "https://media.giphy.com/big/giphy-downsized.gif", "size": "1900000" } } },
        { "id": "broken", "title": "No images" }
      ],
      "pagination": { "total_count": 100, "count": 40, "offset": 0 },
      "meta": { "status": 200 } }
    """#

    private let giphyClips = #"""
    { "data": [
        { "id": "clip1", "title": "See You Later", "url": "https://giphy.com/clips/clip1",
          "images": { "fixed_width": { "url": "https://media.giphy.com/clip1/200w.gif", "width": "200", "height": "112" } },
          "video": { "assets": {
            "360p": { "url": "https://media.giphy.com/clip1/360.mp4" },
            "720p": { "url": "https://media.giphy.com/clip1/720.mp4" } } } }
      ],
      "pagination": { "total_count": 1, "count": 1, "offset": 0 } }
    """#

    private let klipy = #"""
    { "result": true, "data": { "data": [
        { "id": 1, "slug": "happy-dance", "title": "Happy Dance", "type": "gif",
          "file": {
            "sm": { "gif": { "url": "https://static.klipy.com/sm.gif", "width": 220, "height": 160 } },
            "md": { "gif": { "url": "https://static.klipy.com/md.gif", "width": 480, "height": 350 } } } },
        { "id": 2, "slug": "sponsored", "title": "Buy now", "type": "ad", "file": {} }
      ], "current_page": 1, "per_page": 40, "has_next": true } }
    """#

    @Test func readsGiphyGifs() throws {
        let page = try GifAPI.parseGiphy(Data(giphyGifs.utf8), clips: false, offset: 0)
        #expect(page.gifs.map(\.id) == ["giphy:abc", "giphy:big"])
        let bean = try #require(page.gifs.first)
        #expect(bean.title == "Mr Bean Waiting · Working Title")
        #expect(bean.previewURL.absoluteString == "https://media.giphy.com/abc/200w.gif")
        #expect(bean.previewWidth == 200 && bean.previewHeight == 150)
        #expect(bean.mediaURL.absoluteString == "https://media.giphy.com/abc/giphy.gif")
        #expect(bean.pageURL?.absoluteString == "https://giphy.com/gifs/abc")
        #expect(!bean.isVideo)
        // Very large originals fall back to GIPHY's smaller version.
        #expect(page.gifs[1].mediaURL.lastPathComponent == "giphy-downsized.gif")
        #expect(page.next == 40)
    }

    @Test func readsGiphyClipsAsVideos() throws {
        let page = try GifAPI.parseGiphy(Data(giphyClips.utf8), clips: true, offset: 0)
        let clip = try #require(page.gifs.first)
        #expect(clip.id == "giphyClips:clip1")
        #expect(clip.mediaURL.absoluteString == "https://media.giphy.com/clip1/720.mp4")
        #expect(clip.isVideo)
        #expect(page.next == nil)
    }

    @Test func readsKlipyAndSkipsSponsoredItems() throws {
        let page = try GifAPI.parseKlipy(Data(klipy.utf8), page: 1)
        #expect(page.gifs.map(\.id) == ["klipy:happy-dance"])
        let gif = try #require(page.gifs.first)
        #expect(gif.previewURL.absoluteString == "https://static.klipy.com/sm.gif")
        #expect(gif.mediaURL.absoluteString == "https://static.klipy.com/md.gif")
        #expect(gif.pageURL?.absoluteString == "https://klipy.com/gifs/happy-dance")
        #expect(page.next == 2)
    }

    @Test func klipyRejectionsReadAsABadKey() {
        #expect(throws: GifError.badKey(.klipy)) {
            try GifAPI.parseKlipy(Data(#"{ "result": false, "errors": { "message": ["Invalid key"] } }"#.utf8), page: 1)
        }
    }

    @Test func buildsRequests() throws {
        let trending = GifAPI.giphyURL(clips: false, query: "", offset: 0, key: "K")
        #expect(trending.path == "/v1/gifs/trending")
        let search = try #require(URLComponents(url: GifAPI.giphyURL(clips: true, query: "hello there", offset: 40, key: "K"), resolvingAgainstBaseURL: false))
        #expect(search.path == "/v1/clips/search")
        #expect(search.queryItems?.first { $0.name == "q" }?.value == "hello there")
        #expect(search.queryItems?.first { $0.name == "offset" }?.value == "40")
        #expect(search.queryItems?.first { $0.name == "rating" }?.value == "pg-13")

        let klipy = try #require(URLComponents(url: GifAPI.klipyURL(query: "cats", page: 2, key: "APPKEY"), resolvingAgainstBaseURL: false))
        #expect(klipy.path == "/api/v1/APPKEY/gifs/search")
        #expect(klipy.queryItems?.first { $0.name == "page" }?.value == "2")
        #expect(klipy.queryItems?.first { $0.name == "customer_id" }?.value?.isEmpty == false)
    }

    @Test func filesAreNamedAfterTheGif() {
        let gif = Gif(
            id: "giphy:x", source: .giphy, title: "Yes / No: Maybe?", previewURL: URL(string: "https://a/p.gif")!,
            previewWidth: 1, previewHeight: 1, mediaURL: URL(string: "https://a/m.gif")!, pageURL: nil
        )
        #expect(GifMedia.fileName(for: gif) == "Yes No Maybe.gif")
        let untitled = Gif(
            id: "giphyClips:y", source: .giphyClips, title: " ", previewURL: URL(string: "https://a/p.gif")!,
            previewWidth: 1, previewHeight: 1, mediaURL: URL(string: "https://a/m.mp4")!, pageURL: nil
        )
        #expect(GifMedia.fileName(for: untitled) == "Clip.mp4")
    }

    @Test func gifSearchHasAConfigCommand() throws {
        let json = #"{ "shortcuts": [ { "key": "g", "command": "gifSearch" } ] }"#
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8)))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.first?.action == .gifSearch)
    }
}
