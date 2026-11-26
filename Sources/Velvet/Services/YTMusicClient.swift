import Foundation

/// Minimal InnerTube client for YouTube Music (WEB_REMIX context).
/// Endpoints used: /search, /browse (VLLM = liked songs).
final class YTMusicClient {
    static let shared = YTMusicClient()

    private let base = "https://music.youtube.com/youtubei/v1"
    private let clientVersion = "1.20250101.03.00"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    enum APIError: LocalizedError {
        case http(Int)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code): return code == 401 || code == 403
                ? "Session expired — please sign in again."
                : "YouTube Music returned HTTP \(code)."
            case .badResponse: return "Couldn't parse the response from YouTube Music."
            }
        }
    }

    private func request(_ endpoint: String, body: [String: Any],
                         query: [String: String] = [:]) async throws -> JSON {
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US",
            ]
        ]

        var components = URLComponents(string: "\(base)/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
            + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        req.setValue(AuthManager.userAgent, forHTTPHeaderField: "User-Agent")

        let auth = await AuthManager.shared.authHeaders()
        for (k, v) in auth { req.setValue(v, forHTTPHeaderField: k) }
        if auth["Authorization"] != nil {
            req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return JSON(data: data)
    }

    // MARK: - Public API

    /// Catalog-wide search across songs, videos and albums ("everywhere"),
    /// not just the Songs shelf. Falls back to the songs filter if empty.
    func search(_ query: String) async throws -> [Track] {
        let plain = try await request("search", body: ["query": query])
        var tracks = Self.parseTracks(plain)
        if tracks.isEmpty {
            // "Songs" filter param (from the ytmusicapi project) as a fallback.
            let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
            let filtered = try await request("search", body: ["query": query, "params": songsFilter])
            tracks = Self.parseTracks(filtered)
        }
        return tracks
    }

    /// Filtered search returning playable tracks (songs/videos filters).
    func searchTracks(_ query: String, filter: SearchFilter) async throws -> [Track] {
        var body: [String: Any] = ["query": query]
        if let p = filter.param { body["params"] = p }
        return Self.parseTracks(try await request("search", body: body))
    }

    /// Filtered search returning browsable items (albums/artists/playlists).
    func searchBrowse(_ query: String, filter: SearchFilter) async throws -> [BrowseItem] {
        var body: [String: Any] = ["query": query]
        if let p = filter.param { body["params"] = p }
        return Self.parseBrowseItems(try await request("search", body: body))
    }

    // MARK: - Artist & Album pages

    struct ArtistPage {
        let name: String
        let thumbnail: String?
        let topSongs: [Track]
        let sections: [(title: String, items: [BrowseItem])]
    }

    func getArtist(_ browseId: String) async throws -> ArtistPage {
        let json = try await request("browse", body: ["browseId": browseId])
        let header = json.findFirst("musicImmersiveHeaderRenderer")
            ?? json.findFirst("musicVisualHeaderRenderer")
        let name = header?["title"].findFirst("runs")?[0]["text"].string ?? "Artist"
        let thumb = header?.findAll("url").compactMap(\.string).last

        var topSongs: [Track] = []
        var sections: [(String, [BrowseItem])] = []
        for shelf in json.findAll("musicShelfRenderer") + json.findAll("musicCarouselShelfRenderer") {
            let title = shelf.findFirst("header")?.findFirst("title")?.findFirst("runs")?[0]["text"].string
                ?? shelf.findFirst("title")?.findFirst("runs")?[0]["text"].string ?? ""
            let songs = Self.parseTracks(shelf)
            if !songs.isEmpty, title.localizedCaseInsensitiveContains("song") {
                topSongs = Array(songs.prefix(10))
            } else {
                let items = Self.parseBrowseItems(shelf)
                if !items.isEmpty { sections.append((title.isEmpty ? "More" : title, Array(items.prefix(20)))) }
            }
        }
        return ArtistPage(name: name, thumbnail: thumb, topSongs: topSongs, sections: sections)
    }

    struct AlbumPage {
        let title: String
        let subtitle: String
        let thumbnail: String?
        let tracks: [Track]
    }

    func getAlbum(_ browseId: String) async throws -> AlbumPage {
        let json = try await request("browse", body: ["browseId": browseId])
        let header = json.findFirst("musicResponsiveHeaderRenderer")
            ?? json.findFirst("musicDetailHeaderRenderer")
        let title = header?["title"].findFirst("runs")?[0]["text"].string ?? "Album"
        let subtitle = header?["straplineTextOne"].findFirst("runs")?[0]["text"].string
            ?? header?["subtitle"].findFirst("runs")?.array.compactMap { $0["text"].string }.joined() ?? ""
        let thumb = header?.findAll("url").compactMap(\.string).last
            ?? json.findAll("url").compactMap(\.string).last
        // Album rows lack their own thumbnail; borrow the album art.
        let tracks = Self.parseTracks(json).map {
            Track(id: $0.id, title: $0.title,
                  artist: $0.artist.isEmpty ? subtitle : $0.artist,
                  durationText: $0.durationText, thumbnail: $0.thumbnail ?? thumb)
        }
        return AlbumPage(title: title, subtitle: subtitle, thumbnail: thumb, tracks: tracks)
    }

    /// Parse list rows / cards that navigate to an artist, album or playlist.
    static func parseBrowseItems(_ json: JSON) -> [BrowseItem] {
        var seen = Set<String>()
        var out: [BrowseItem] = []

        func classify(_ pageType: String?) -> BrowseItem.Kind? {
            switch pageType {
            case "MUSIC_PAGE_TYPE_ARTIST": return .artist
            case "MUSIC_PAGE_TYPE_ALBUM": return .album
            case "MUSIC_PAGE_TYPE_PLAYLIST": return .playlist
            default: return nil
            }
        }

        func add(_ container: JSON, titleRuns: [String], subtitle: String, thumb: String?) {
            // Find the browseEndpoint whose pageType we recognize.
            for ep in container.findAll("browseEndpoint") {
                let pageType = ep.findFirst("pageType")?.string
                guard let kind = classify(pageType),
                      let id = ep["browseId"].string,
                      !seen.contains(id) else { continue }
                guard let title = titleRuns.first, !title.isEmpty else { return }
                seen.insert(id)
                out.append(BrowseItem(id: id, title: title, subtitle: subtitle,
                                      thumbnail: thumb, kind: kind))
                return
            }
        }

        for row in json.findAll("musicResponsiveListItemRenderer") {
            let flex = row["flexColumns"].array
            let titleRuns = flex.first?["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"]
                .array.compactMap { $0["text"].string } ?? []
            let subRuns = flex.count > 1
                ? flex[1]["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"]
                    .array.compactMap { $0["text"].string } : []
            let subtitle = subRuns.joined()
            let thumb = row["thumbnail"].findAll("url").compactMap(\.string).last
            add(row, titleRuns: titleRuns, subtitle: subtitle, thumb: thumb)
        }
        for card in json.findAll("musicTwoRowItemRenderer") {
            let titleRuns = card["title"].findFirst("runs")?.array.compactMap { $0["text"].string } ?? []
            let subtitle = card["subtitle"].findFirst("runs")?.array
                .compactMap { $0["text"].string }.joined() ?? ""
            let thumb = card["thumbnailRenderer"].findAll("url").compactMap(\.string).last
            add(card, titleRuns: titleRuns, subtitle: subtitle, thumb: thumb)
        }
        return out
    }

    /// Live autocomplete suggestions for the query-in-progress.
    func searchSuggestions(_ input: String) async throws -> [String] {
        guard input.count >= 2 else { return [] }
        let json = try await request("music/get_search_suggestions", body: ["input": input])
        var out: [String] = []
        var seen = Set<String>()
        for s in json.findAll("searchSuggestionRenderer") {
            let runs = s["suggestion"]["runs"].array.compactMap { $0["text"].string }
            let text = runs.joined()
            if !text.isEmpty, seen.insert(text).inserted { out.append(text) }
        }
        return out
    }

    /// Signed-in account's display name, handle, and avatar URL.
    func accountInfo() async throws -> (name: String?, handle: String?, photo: URL?) {
        let json = try await request("account/account_menu", body: [:])
        let name = json.findFirst("accountName")?.findFirst("runs")?[0]["text"].string
            ?? json.findFirst("accountName")?["simpleText"].string
        let handle = json.findFirst("channelHandle")?.findFirst("runs")?[0]["text"].string
            ?? json.findFirst("channelHandle")?["simpleText"].string
        let photoStr = json.findFirst("accountPhoto")?.findAll("url").compactMap(\.string).last
        return (name, handle, photoStr.flatMap { URL(string: $0) })
    }

    /// YouTube Music home feed as titled shelves. Shelves of playable song
    /// cards become .tracks sections; album / playlist / artist card shelves
    /// become navigable .items sections instead of being dropped.
    func home() async throws -> [HomeSection] {
        let json = try await request("browse", body: ["browseId": "FEmusic_home"])
        var sections: [HomeSection] = []
        for shelf in json.findAll("musicCarouselShelfRenderer") + json.findAll("musicShelfRenderer") {
            let title = shelf.findFirst("header")?.findFirst("title")?
                .findFirst("runs")?[0]["text"].string
                ?? shelf.findFirst("title")?.findFirst("runs")?[0]["text"].string
                ?? "For You"
            // Home shelves are card-based (musicTwoRowItemRenderer); cards
            // with a videoId are playable, the rest navigate somewhere.
            var tracks = Self.parseCards(shelf)
            if tracks.isEmpty { tracks = Self.parseTracks(shelf) }
            if tracks.count >= 2 {
                sections.append(.tracks(title: title, tracks: Array(tracks.prefix(20))))
            } else {
                let items = Self.parseBrowseItems(shelf)
                if items.count >= 2 {
                    sections.append(.items(title: title, items: Array(items.prefix(20))))
                }
            }
        }
        // De-dupe identical section titles, keep first.
        var seen = Set<String>()
        return sections.filter { seen.insert($0.title).inserted }
    }

    /// The user's Liked Songs (auto playlist "LM"). Requires auth.
    /// The first /browse page holds ~100 rows; the rest arrive through
    /// continuation tokens, which we follow until the playlist is exhausted.
    func likedSongs() async throws -> [Track] {
        var json = try await request("browse", body: ["browseId": "VLLM"])
        var tracks = Self.parseTracks(json)
        if tracks.isEmpty, let raw = json.raw {
            // Diagnostic: keep the last empty-parse response for inspection.
            if let data = try? JSONSerialization.data(withJSONObject: raw) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/velvet-liked-debug.json"))
            }
        }

        var seen = Set(tracks.map(\.id))
        var pages = 0
        while let token = Self.continuationToken(json), pages < 50 {
            pages += 1
            json = try await request("browse", body: ["continuation": token],
                                     query: ["ctoken": token, "continuation": token, "type": "next"])
            let more = Self.parseTracks(json).filter { seen.insert($0.id).inserted }
            if more.isEmpty { break }
            tracks += more
        }
        return tracks
    }

    /// Continuation token for the next page of a browse response, covering
    /// both the legacy and current InnerTube shapes.
    static func continuationToken(_ json: JSON) -> String? {
        json.findFirst("nextContinuationData")?["continuation"].string
            ?? json.findFirst("continuationCommand")?["token"].string
    }

    // MARK: - Parsing

    /// Both search shelves and playlist shelves render tracks as
    /// musicResponsiveListItemRenderer — parse them uniformly.
    static func parseTracks(_ json: JSON) -> [Track] {
        var seen = Set<String>()
        var tracks: [Track] = []

        for item in json.findAll("musicResponsiveListItemRenderer") {
            guard let track = parseItem(item), !seen.contains(track.id) else { continue }
            seen.insert(track.id)
            tracks.append(track)
        }
        return tracks
    }

    /// Parse card-style home items (musicTwoRowItemRenderer). Keeps only
    /// cards with a playable watchEndpoint videoId (skips albums/playlists).
    static func parseCards(_ json: JSON) -> [Track] {
        var seen = Set<String>()
        var tracks: [Track] = []
        for card in json.findAll("musicTwoRowItemRenderer") {
            guard let id = card.findFirst("watchEndpoint")?["videoId"].string,
                  !seen.contains(id) else { continue }
            let runs = card["title"].findFirst("runs")?.array.compactMap { $0["text"].string } ?? []
            guard let title = runs.first, !title.isEmpty else { continue }
            let subtitle = card["subtitle"].findFirst("runs")?.array
                .compactMap { $0["text"].string }.joined() ?? ""
            let artist = subtitle.components(separatedBy: " • ").first ?? subtitle
            let thumb = card["thumbnailRenderer"].findAll("url").compactMap(\.string).last
                ?? card.findAll("url").compactMap(\.string).last
            seen.insert(id)
            tracks.append(Track(id: id, title: title, artist: artist,
                                durationText: "", thumbnail: thumb))
        }
        return tracks
    }

    private static func parseItem(_ item: JSON) -> Track? {
        // videoId: prefer the direct playlistItemData, fall back to any
        // watchEndpoint buried in the overlay.
        var videoId = item["playlistItemData"]["videoId"].string
        if videoId == nil {
            videoId = item["overlay"].findFirst("videoId")?.string
                ?? item.findFirst("watchEndpoint")?["videoId"].string
        }
        guard let id = videoId else { return nil }

        let flex = item["flexColumns"].array
        func runs(_ col: Int) -> [String] {
            flex[safe: col]?["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"]
                .array.compactMap { $0["text"].string } ?? []
        }

        guard let title = runs(0).first, !title.isEmpty else { return nil }

        // Column 1 runs look like: Artist • Album • 3:45 (separators are their own runs)
        let meta = runs(1)
        let parts = meta.joined().components(separatedBy: " • ")
        let artist = parts.first ?? ""

        // Duration: fixedColumns (playlists) or the last mm:ss-looking run.
        var duration = item["fixedColumns"][0]["musicResponsiveListItemFixedColumnRenderer"]["text"]["runs"][0]["text"].string
        if duration == nil {
            duration = parts.reversed().first {
                $0.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil
            }
        }

        let thumb = item["thumbnail"].findAll("url").compactMap(\.string).last

        return Track(id: id,
                     title: title,
                     artist: artist,
                     durationText: duration ?? "",
                     thumbnail: thumb)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
