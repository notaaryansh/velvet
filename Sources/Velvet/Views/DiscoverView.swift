import SwiftUI

/// Pops one level of the Discover navigation stack. Injected through the
/// environment because `dismiss()` is unreliable for NavigationStack pops
/// on macOS.
struct PopActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var popNavigation: () -> Void {
        get { self[PopActionKey.self] }
        set { self[PopActionKey.self] = newValue }
    }
}

struct DiscoverView: View {
    var model: DiscoverModel
    @Bindable var search: SearchModel
    @State private var recents = RecentsStore.shared
    @State private var navPath: [BrowseItem] = []
    @FocusState private var searchFocused: Bool

    private var searching: Bool {
        search.query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    private var showSuggestions: Bool {
        searchFocused && !search.suppressSuggestions
            && !search.suggestions.isEmpty
            && !search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    searchBar
                    if searching {
                        searchResults
                    } else {
                        feed
                    }
                }

                if showSuggestions {
                    suggestionsDropdown
                        .padding(.horizontal, 22)
                        .padding(.top, 66)
                        .frame(maxWidth: 420 + 44, alignment: .leading)
                }
            }
            .navigationDestination(for: BrowseItem.self) { item in
                switch item.kind {
                case .artist:
                    ArtistPageView(artistId: item.id, fallbackName: item.title)
                case .album, .playlist:
                    AlbumPageView(item: item)
                }
            }
        }
        .environment(\.popNavigation) {
            if !navPath.isEmpty { navPath.removeLast() }
        }
        .task {
            if !model.loaded { await model.reload() }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        VStack(spacing: 0) {
            FilterChips(selected: Binding(get: { search.filter },
                                          set: { search.filter = $0 }))
            if search.filter.isTracks {
                TrackList(tracks: search.results,
                          title: "Results",
                          subtitle: search.results.isEmpty ? nil : "\(search.results.count) \(search.filter.rawValue.lowercased())",
                          emptyIcon: "magnifyingglass",
                          emptyTitle: search.isLoading ? "Searching…" : "No Results",
                          emptyText: search.isLoading ? "Finding your music." : "Try a different search.",
                          error: search.error)
            } else {
                BrowseItemList(items: search.items,
                               isLoading: search.isLoading)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Search songs, artists, albums", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    search.suppressSuggestions = true
                    search.suggestions = []
                }
            if search.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.8)
            } else if !search.query.isEmpty {
                Button { search.query = ""; search.suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(search.suggestions.prefix(8).enumerated()), id: \.offset) { _, s in
                Button {
                    search.choose(s)
                    searchFocused = false
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(s)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SuggestionButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private var feed: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 26) {
                // Header
                Text(greeting)
                    .font(.system(size: 26, weight: .bold))
                    .padding(.horizontal, 22)
                    .padding(.top, 2)

                if !recents.tracks.isEmpty {
                    Carousel(title: "Recently Played", tracks: recents.tracks)
                }
                if recents.mostPlayed.count >= 3 {
                    Carousel(title: "On Repeat", tracks: recents.mostPlayed)
                }
                if !model.topArtists.isEmpty {
                    BrowseCarousel(title: "Your Top Artists", items: model.topArtists)
                }
                if !model.suggested.isEmpty {
                    Carousel(title: "Suggested for You", tracks: model.suggested)
                }

                if model.isLoading && model.sections.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if model.sections.isEmpty && recents.tracks.isEmpty {
                    StateMessage(icon: "sparkles",
                                 title: "Nothing here yet",
                                 text: "Play a few songs and your recents show up here.",
                                 action: nil)
                        .frame(height: 300)
                }

                ForEach(model.sections) { section in
                    switch section {
                    case .tracks(let title, let tracks):
                        Carousel(title: title, tracks: tracks)
                    case .items(let title, let items):
                        BrowseCarousel(title: title, items: items)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
}

// MARK: - Search filter chips

struct FilterChips: View {
    @Binding var selected: SearchFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { f in
                    Button { selected = f } label: {
                        Text(f.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected == f ? .white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(
                                selected == f ? AnyShapeStyle(Velvet.accent)
                                              : AnyShapeStyle(Color.primary.opacity(0.07))))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Browse item list (artists / albums / playlists)

struct BrowseItemList: View {
    let items: [BrowseItem]
    let isLoading: Bool

    var body: some View {
        if items.isEmpty {
            StateMessage(icon: "magnifyingglass",
                         title: isLoading ? "Searching…" : "No Results",
                         text: isLoading ? "Finding your music." : "Try a different search.",
                         action: nil)
        } else {
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
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
}

struct BrowseItemRow: View {
    let item: BrowseItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: item.art(120)) {
                Rectangle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: item.kind == .artist ? "person.fill" : "square.stack")
                        .font(.system(size: 15)).foregroundStyle(.tertiary))
            }
            .frame(width: 48, height: 48)
            .clipShape(item.kind == .artist
                       ? AnyShape(Circle())
                       : AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle.isEmpty ? item.kind.rawValue.capitalized : item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(hovering ? Velvet.rowHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Row highlights on hover inside the suggestions popover.
struct SuggestionButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
            .onHover { hovering = $0 }
    }
}

/// Horizontal row of square song cards, Apple Music style.
struct Carousel: View {
    let title: String
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .padding(.horizontal, 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, track in
                        SongCard(track: track) {
                            PlayerService.shared.play(tracks: tracks, at: i)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
        }
        // Shelves are short — warm every card up front so horizontal
        // scrolling is always loaded.
        .onAppear { ArtworkCache.shared.prefetch(tracks.map { $0.art(300) }) }
    }
}

struct BrowseCard: View {
    let item: BrowseItem
    @State private var hovering = false

    private var isArtist: Bool { item.kind == .artist }

    var body: some View {
        VStack(alignment: isArtist ? .center : .leading, spacing: 7) {
            Artwork(url: item.art(300)) {
                Rectangle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: isArtist ? "person.fill" : "square.stack")
                        .font(.system(size: 22)).foregroundStyle(.tertiary))
            }
            .frame(width: 150, height: 150)
            .clipShape(isArtist
                       ? AnyShape(Circle())
                       : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .overlay {
                if isArtist {
                    Circle().strokeBorder(.white.opacity(0.08))
                } else {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08))
                }
            }
            .scaleEffect(hovering ? 1.03 : 1)

            Text(item.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            if !isArtist {
                Text(item.subtitle.isEmpty ? item.kind.rawValue.capitalized : item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: isArtist ? .center : .leading)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

struct SongCard: View {
    let track: Track
    let onPlay: () -> Void
    @State private var hovering = false
    @State private var player = PlayerService.shared

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Artwork(url: track.art(300)) {
                    Rectangle().fill(Velvet.artPlaceholder)
                        .overlay(Image(systemName: "music.note")
                            .font(.system(size: 22)).foregroundStyle(.tertiary))
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))

                // Play button appears on hover
                if hovering || isCurrent {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, Velvet.accent)
                        .shadow(radius: 4)
                        .padding(8)
                        .transition(.opacity)
                }
            }

            Text(track.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isCurrent ? Velvet.accent : .primary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(perform: onPlay)
    }
}
