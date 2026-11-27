import SwiftUI
import Observation

// MARK: - Playlists

@MainActor
@Observable
final class PlaylistsModel {
    var items: [BrowseItem] = []
    var isLoading = false
    var error: String?

    func reload() async {
        isLoading = true
        error = nil
        do {
            items = try await YTMusicClient.shared.libraryPlaylists()
            // Warm the list art and every playlist's interior so opening
            // one never shows a spinner.
            ArtworkCache.shared.prefetch(items.map { $0.art(120) })
            // Header-size art too, so the detail page renders from memory.
            ArtworkCache.shared.prefetch(items.map { $0.art(400) })
            let toWarm = items
            Task { await PageCache.shared.warmAlbums(toWarm) }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct PlaylistsView: View {
    var model: PlaylistsModel
    var auth: AuthManager
    @State private var navPath: [BrowseItem] = []

    var body: some View {
        if !auth.resolved {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !auth.isLoggedIn {
            SignedOutState(auth: auth)
        } else {
            NavigationStack(path: $navPath) {
                Group {
                    if model.items.isEmpty {
                        StateMessage(icon: "music.note.list",
                                     title: model.isLoading ? "Loading…" : "No Playlists",
                                     text: model.isLoading
                                        ? "Opening your playlists."
                                        : "Playlists you save on YouTube Music appear here.",
                                     action: nil)
                    } else {
                        ScrollView(showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                Text("Playlists")
                                    .font(.system(size: 26, weight: .bold))
                                    .padding(.horizontal, 22)
                                    .padding(.top, 30)
                                    .padding(.bottom, 10)
                                ForEach(model.items) { item in
                                    NavigationLink(value: item) {
                                        BrowseItemRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 84).opacity(0.4)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                .navigationDestination(for: BrowseItem.self) { item in
                    switch item.kind {
                    case .artist:
                        ArtistPageView(artistId: item.id, fallbackName: item.title, fallbackArt: item.art(400))
                    case .album, .playlist:
                        AlbumPageView(item: item)
                    }
                }
            }
            .environment(\.popNavigation) {
                if !navPath.isEmpty { navPath.removeLast() }
            }
            .task { if model.items.isEmpty { await model.reload() } }
        }
    }
}

// MARK: - History

@MainActor
@Observable
final class HistoryModel {
    var sections: [(title: String, tracks: [Track])] = []
    var isLoading = false
    var error: String?

    func reload() async {
        isLoading = true
        error = nil
        do {
            sections = try await YTMusicClient.shared.history()
            ArtworkCache.shared.prefetch(sections.flatMap(\.tracks).prefix(80).map { $0.art(96) })
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct HistoryView: View {
    var model: HistoryModel
    var auth: AuthManager

    var body: some View {
        if !auth.resolved {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !auth.isLoggedIn {
            SignedOutState(auth: auth)
        } else if model.sections.isEmpty {
            StateMessage(icon: "clock.arrow.circlepath",
                         title: model.isLoading ? "Loading…" : "No History",
                         text: model.isLoading
                            ? "Opening your listening history."
                            : "Songs you play show up here.",
                         action: nil)
                .task { if model.sections.isEmpty { await model.reload() } }
        } else {
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("History")
                        .font(.system(size: 26, weight: .bold))
                        .padding(.horizontal, 22)
                        .padding(.top, 30)
                        .padding(.bottom, 4)
                    ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                        Text(section.title)
                            .font(.system(size: 17, weight: .bold))
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                        ForEach(Array(section.tracks.enumerated()), id: \.element.id) { i, t in
                            TrackRow(track: t, number: i + 1) {
                                PlayerService.shared.play(tracks: section.tracks, at: i)
                            }
                            if i < section.tracks.count - 1 {
                                Divider().padding(.leading, 84).opacity(0.4)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .task { await model.reload() }
        }
    }
}

// MARK: - Queue

struct QueueView: View {
    @State private var player = PlayerService.shared

    var body: some View {
        if player.queue.isEmpty {
            StateMessage(icon: "list.bullet",
                         title: "Queue is empty",
                         text: "Play something and the up-next list shows here.",
                         action: nil)
        } else {
            TrackList(tracks: player.queue,
                      title: "Queue",
                      subtitle: "\(player.queue.count) songs",
                      emptyIcon: "list.bullet",
                      emptyTitle: "Queue is empty",
                      emptyText: "Play something and the up-next list shows here.")
        }
    }
}
