import Foundation
import Observation

/// Which songs the signed-in account has liked, shared across every list so
/// hover hearts show the right state. Toggles optimistically and rolls back
/// if the API call fails.
@MainActor
@Observable
final class LikesStore {
    static let shared = LikesStore()

    private(set) var ids: Set<String> = []
    private var loaded = false

    private init() {}

    func isLiked(_ id: String) -> Bool { ids.contains(id) }

    /// Fetch liked-song ids once per session (and again after re-login).
    func ensureLoaded() async {
        guard !loaded, AuthManager.shared.isLoggedIn else { return }
        loaded = true
        if let tracks = try? await YTMusicClient.shared.likedSongs() {
            ids = Set(tracks.map(\.id))
        }
    }

    /// Adopt an already-fetched liked list instead of fetching again.
    func seed(_ trackIds: Set<String>) {
        ids = trackIds
        loaded = true
    }

    func reset() {
        ids = []
        loaded = false
    }

    func toggle(_ track: Track) async {
        let nowLiked = !ids.contains(track.id)
        if nowLiked { ids.insert(track.id) } else { ids.remove(track.id) }
        do {
            try await YTMusicClient.shared.rate(track.id, liked: nowLiked)
        } catch {
            // Roll back the optimistic flip.
            if nowLiked { ids.remove(track.id) } else { ids.insert(track.id) }
        }
    }
}
