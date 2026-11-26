import Foundation

/// In-memory cache of fully-parsed detail pages (playlists / albums /
/// artists), warmed ahead of navigation so opening one never shows a
/// spinner. Views serve the cached page instantly and refresh quietly.
@MainActor
final class PageCache {
    static let shared = PageCache()

    var albums: [String: YTMusicClient.AlbumPage] = [:]
    var artists: [String: YTMusicClient.ArtistPage] = [:]

    private init() {}

    /// Fetch every album/playlist page in small batches and pre-decode the
    /// row artwork, so the interior is ready before it's ever opened.
    func warmAlbums(_ items: [BrowseItem]) async {
        let pending = items.filter { albums[$0.id] == nil }
        for start in stride(from: 0, to: pending.count, by: 4) {
            let batch = pending[start..<min(start + 4, pending.count)]
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { @MainActor in
                        guard let page = try? await YTMusicClient.shared.getAlbum(item.id) else { return }
                        self.albums[item.id] = page
                        ArtworkCache.shared.prefetch(page.tracks.prefix(50).map { $0.art(96) })
                    }
                }
            }
        }
    }

    /// Same for artist pages (top songs + shelves).
    func warmArtists(_ items: [BrowseItem]) async {
        let pending = items.filter { artists[$0.id] == nil }
        for start in stride(from: 0, to: pending.count, by: 4) {
            let batch = pending[start..<min(start + 4, pending.count)]
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { @MainActor in
                        guard let page = try? await YTMusicClient.shared.getArtist(item.id) else { return }
                        self.artists[item.id] = page
                        ArtworkCache.shared.prefetch(page.topSongs.map { $0.art(96) })
                        ArtworkCache.shared.prefetch(page.sections.flatMap { $0.items.prefix(10) }.map { $0.art(300) })
                    }
                }
            }
        }
    }
}
