import SwiftUI

// MARK: - Artist page

@MainActor
@Observable
final class ArtistPageModel {
    var page: YTMusicClient.ArtistPage?
    var isLoading = true

    func load(_ id: String) async {
        // Cached page renders instantly; a quiet refresh follows.
        if let cached = PageCache.shared.artists[id] {
            page = cached
            isLoading = false
        } else {
            isLoading = true
        }
        if var fresh = try? await YTMusicClient.shared.getArtist(id) {
            // Never let a refresh downgrade a page we already showed: the
            // API sometimes omits the header image on re-fetch, which made
            // the artist photo flash in and then vanish.
            if fresh.thumbnail == nil, let keep = page?.thumbnail {
                fresh = YTMusicClient.ArtistPage(name: fresh.name, thumbnail: keep,
                                                 subscribers: fresh.subscribers,
                                                 topSongs: fresh.topSongs, sections: fresh.sections)
            }
            page = fresh
            PageCache.shared.artists[id] = fresh
        }
        isLoading = false
    }
}

/// Round back button that lives in the page header, beside the artwork,
/// instead of the system one up in the title bar.
struct HeaderBackButton: View {
    @Environment(\.popNavigation) private var pop
    @State private var hovering = false

    var body: some View {
        Button { pop() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.16 : 0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Back")
    }
}

struct ArtistPageView: View {
    let artistId: String
    let fallbackName: String
    @State private var model = ArtistPageModel()

    var body: some View {
        ScrollView(showsIndicators: true) {
            // Top padding keeps the back button clear of the window's
            // titlebar/toolbar strip (~52pt), which swallows clicks.
            VStack(alignment: .leading, spacing: 24) {
                header
                if let page = model.page {
                    if !page.topSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Top Songs") {
                                PlayerService.shared.play(tracks: page.topSongs, at: 0)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(page.topSongs.enumerated()), id: \.element.id) { i, t in
                                    TrackRow(track: t, number: i + 1) {
                                        PlayerService.shared.play(tracks: page.topSongs, at: i)
                                    }
                                    if i < page.topSongs.count - 1 {
                                        Divider().padding(.leading, 84).opacity(0.4)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                        BrowseCarousel(title: section.title, items: section.items)
                    }
                } else if model.isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(model.page?.name ?? fallbackName)
        .navigationBarBackButtonHidden(true)
        // NavigationStack lays an invisible window-toolbar strip over the top
        // of the page that swallows clicks meant for our in-header back
        // button — remove it entirely.
        .toolbar(.hidden, for: .windowToolbar)
        .task { await model.load(artistId) }
    }

    private var header: some View {
        HStack(spacing: 18) {
            HeaderBackButton()
            Artwork(url: model.page?.thumbnail.flatMap { thumbURL($0) }) {
                Circle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.tertiary))
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Artist").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(model.page?.name ?? fallbackName)
                    .font(.system(size: 30, weight: .bold))
                if let subs = model.page?.subscribers {
                    Text(subs)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let top = model.page?.topSongs, !top.isEmpty {
                    Button {
                        PlayerService.shared.play(tracks: top, at: 0)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 10))
                            Text("Play").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(Velvet.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
    }

    private func thumbURL(_ s: String) -> URL? { URL(string: s) }
}

// MARK: - Album / Playlist page

@MainActor
@Observable
final class AlbumPageModel {
    var page: YTMusicClient.AlbumPage?
    var isLoading = true

    func load(_ id: String) async {
        // Cached page renders instantly; a quiet refresh follows.
        if let cached = PageCache.shared.albums[id] {
            page = cached
            isLoading = false
        } else {
            isLoading = true
        }
        if var fresh = try? await YTMusicClient.shared.getAlbum(id) {
            if fresh.thumbnail == nil, let keep = page?.thumbnail {
                fresh = YTMusicClient.AlbumPage(title: fresh.title, subtitle: fresh.subtitle,
                                                thumbnail: keep, tracks: fresh.tracks)
            }
            page = fresh
            PageCache.shared.albums[id] = fresh
        }
        isLoading = false
    }
}

struct AlbumPageView: View {
    let item: BrowseItem
    @State private var model = AlbumPageModel()

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let tracks = model.page?.tracks, !tracks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                            TrackRow(track: t, number: i + 1) {
                                PlayerService.shared.play(tracks: tracks, at: i)
                            }
                            if i < tracks.count - 1 {
                                Divider().padding(.leading, 84).opacity(0.4)
                            }
                        }
                    }
                } else if model.isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(model.page?.title ?? item.title)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .windowToolbar)
        .task { await model.load(item.id) }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack {
                HeaderBackButton()
                Spacer(minLength: 0)
            }
            .frame(height: 140)
            // Prefer the SAME art the list row already loaded (just larger),
            // so opening a playlist never swaps to a different URL and
            // re-fetches; the page's own thumbnail is only a fallback.
            Artwork(url: item.art(400) ?? (model.page?.thumbnail).flatMap { URL(string: $0) }) {
                Rectangle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: "square.stack").font(.system(size: 30)).foregroundStyle(.tertiary))
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.kind.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(model.page?.title ?? item.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                Text(model.page?.subtitle ?? item.subtitle)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let tracks = model.page?.tracks, !tracks.isEmpty {
                    Button {
                        PlayerService.shared.play(tracks: tracks, at: 0)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 10))
                            Text("Play").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(Velvet.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
    }
}

// MARK: - Shared bits

struct SectionHeader: View {
    let title: String
    var onPlay: (() -> Void)?
    init(_ title: String, onPlay: (() -> Void)? = nil) { self.title = title; self.onPlay = onPlay }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .bold))
            Spacer()
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(Velvet.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
    }
}

/// Horizontal carousel of browsable cards (albums / playlists / artists)
/// that navigate to their detail pages.
struct BrowseCarousel: View {
    let title: String
    let items: [BrowseItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 19, weight: .bold)).padding(.horizontal, 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            BrowseCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
        .onAppear { ArtworkCache.shared.prefetch(items.map { $0.art(300) }) }
    }
}
