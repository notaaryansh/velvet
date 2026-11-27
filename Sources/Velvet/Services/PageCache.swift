import Foundation

/// Bounded moving-window cache of fully-parsed detail pages (playlists /
/// albums / artists), mirroring ArtworkCache's model: most-recently-used
/// pages stay decoded in memory, oldest fall out past the window size.
/// Pages served from the window render instantly; a network refresh only
/// happens once an entry goes stale, so re-opening a playlist doesn't
/// re-fetch or re-render anything.
@MainActor
final class PageCache {
    static let shared = PageCache()

    /// The moving window: how many pages of each kind stay in memory.
    static let windowSize = 40
    /// Entries younger than this are served without any background refresh.
    static let freshFor: TimeInterval = 5 * 60

    private var albumEntries: [String: (page: YTMusicClient.AlbumPage, at: Date)] = [:]
    private var albumLRU: [String] = []
    private var artistEntries: [String: (page: YTMusicClient.ArtistPage, at: Date)] = [:]
    private var artistLRU: [String] = []

    private init() {}

    // MARK: - Albums / playlists

    func album(_ id: String) -> (page: YTMusicClient.AlbumPage, isFresh: Bool)? {
        guard let entry = albumEntries[id] else { return nil }
        touch(id, lru: &albumLRU)
        return (entry.page, Date().timeIntervalSince(entry.at) < Self.freshFor)
    }

    func setAlbum(_ page: YTMusicClient.AlbumPage, for id: String) {
        albumEntries[id] = (page, Date())
        touch(id, lru: &albumLRU)
        evict(lru: &albumLRU) { self.albumEntries[$0] = nil }
    }

    // MARK: - Artists

    func artist(_ id: String) -> (page: YTMusicClient.ArtistPage, isFresh: Bool)? {
        guard let entry = artistEntries[id] else { return nil }
        touch(id, lru: &artistLRU)
        return (entry.page, Date().timeIntervalSince(entry.at) < Self.freshFor)
    }

    func setArtist(_ page: YTMusicClient.ArtistPage, for id: String) {
        artistEntries[id] = (page, Date())
        touch(id, lru: &artistLRU)
        evict(lru: &artistLRU) { self.artistEntries[$0] = nil }
    }

    // MARK: - LRU bookkeeping

    private func touch(_ id: String, lru: inout [String]) {
        lru.removeAll { $0 == id }
        lru.append(id)
    }

    private func evict(lru: inout [String], remove: (String) -> Void) {
        while lru.count > Self.windowSize {
            remove(lru.removeFirst())
        }
    }

    // MARK: - Warmers

    /// Run one warm task per item, four at a time.
    private func warmBatched(_ items: [BrowseItem],
                             _ task: @escaping @MainActor (BrowseItem) async -> Void) async {
        for start in stride(from: 0, to: items.count, by: 4) {
            await withTaskGroup(of: Void.self) { group in
                for item in items[start..<min(start + 4, items.count)] {
                    group.addTask { @MainActor in await task(item) }
                }
            }
        }
    }

    /// Fetch every album/playlist page and pre-decode the row + header
    /// artwork, so the interior is ready before it's opened.
    func warmAlbums(_ items: [BrowseItem]) async {
        await warmBatched(items.filter { albumEntries[$0.id] == nil }) { item in
            guard let page = try? await YTMusicClient.shared.getAlbum(item.id) else { return }
            self.setAlbum(page, for: item.id)
            ArtworkCache.shared.prefetch([item.art(400)])
            ArtworkCache.shared.prefetch(page.tracks.prefix(50).map { $0.art(96) })
        }
    }

    /// Same for artist pages (top songs + shelves).
    func warmArtists(_ items: [BrowseItem]) async {
        await warmBatched(items.filter { artistEntries[$0.id] == nil }) { item in
            guard var page = try? await YTMusicClient.shared.getArtist(item.id) else { return }
            // The API sometimes omits the artist image; backfill from the
            // card we navigated from so it's never blank.
            if page.thumbnail == nil, let thumb = item.thumbnail {
                page = YTMusicClient.ArtistPage(name: page.name, thumbnail: thumb,
                                                subscribers: page.subscribers,
                                                topSongs: page.topSongs, sections: page.sections)
            }
            self.setArtist(page, for: item.id)
            ArtworkCache.shared.prefetch(page.topSongs.map { $0.art(96) })
            ArtworkCache.shared.prefetch(page.sections.flatMap { $0.items.prefix(10) }.map { $0.art(300) })
        }
    }
}
