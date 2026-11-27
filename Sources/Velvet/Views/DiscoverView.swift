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
    @State private var searchExpanded = false
    @State private var tab: DiscoverTab = .home
    @FocusState private var searchFocused: Bool

    private var searching: Bool {
        search.query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// Empty query → past searches; otherwise live suggestions.
    private var showingRecentSearches: Bool {
        search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var dropdownItems: [String] {
        showingRecentSearches ? search.recentSearches : Array(search.suggestions.prefix(8))
    }

    private var showSuggestions: Bool {
        searchFocused && !search.suppressSuggestions && !dropdownItems.isEmpty
    }

    var body: some View {
        BrowseNavigationStack {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    searchBar
                    if searching {
                        searchResults
                    } else {
                        switch tab {
                        case .home:
                            feed
                        case .charts:
                            shelfFeed(model.chartSections, loading: model.chartsLoading)
                        case .newReleases:
                            shelfFeed(model.newReleaseSections, loading: model.newReleasesLoading)
                        }
                    }
                }

                if showSuggestions {
                    suggestionsDropdown
                        .padding(.horizontal, 22)
                        .padding(.top, 66)
                        .frame(maxWidth: 420 + 44, alignment: .leading)
                }
            }
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

    private func expandSearch() {
        searchExpanded = true
        // Focus lands after the expansion begins so the field exists.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
        }
    }

    private func collapseSearch() {
        search.query = ""
        search.suggestions = []
        searchFocused = false
        searchExpanded = false
    }

    /// Top row: browse tabs on the left, search on the right. Opening
    /// search hides the tabs and expands into the field; collapsing (click
    /// away while empty, or Esc) brings the tabs back.
    private var searchBar: some View {
        HStack(spacing: 10) {
            if !searchExpanded {
                HStack(spacing: 8) {
                    ForEach(DiscoverTab.allCases) { t in
                        Button {
                            tab = t
                            Task { await model.load(t) }
                        } label: {
                            Text(t.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tab == t ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(
                                    tab == t ? AnyShapeStyle(Velvet.accent)
                                             : AnyShapeStyle(Color.primary.opacity(0.07))))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
                Spacer(minLength: 10)
            }
            searchControl
            if searchExpanded {
                Spacer(minLength: 0)
            }
        }
        .animation(.snappy(duration: 0.25), value: searchExpanded)
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .onChange(of: searchFocused) { _, focused in
            // Clicking away with nothing typed folds the bar back up.
            if !focused && search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchExpanded = false
            }
        }
    }

    private var searchControl: some View {
        HStack(spacing: 7) {
            Button {
                if !searchExpanded { expandSearch() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 21)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .help("Search (⌘F)")

            if searchExpanded {
                TextField("Search songs, artists, albums", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit {
                        search.suppressSuggestions = true
                        search.suggestions = []
                        search.recordSearch(search.query)
                    }
                    .onExitCommand {
                        // First Esc just closes the dropdown and keeps the
                        // query/results; Esc again closes the search.
                        if showSuggestions {
                            search.suppressSuggestions = true
                            search.suggestions = []
                        } else {
                            collapseSearch()
                        }
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: searchExpanded ? 420 : 36, alignment: .leading)
    }

    /// Charts / New Releases: plain shelf lists from a browse page.
    @ViewBuilder
    private func shelfFeed(_ sections: [HomeSection], loading: Bool) -> some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 26) {
                if loading && sections.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 60)
                } else if sections.isEmpty {
                    StateMessage(icon: "chart.bar",
                                 title: "Nothing here",
                                 text: "Couldn't load this page right now.",
                                 action: nil)
                        .frame(height: 300)
                }
                ForEach(sections) { SectionShelf(section: $0) }
            }
            .padding(.bottom, 20)
            .padding(.top, 2)
        }
    }

    private func dropdownRow(icon: String, text: String, dim: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.system(size: dim ? 12 : 12.5))
                    .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(SuggestionButtonStyle())
    }

    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingRecentSearches {
                Text("Recent Searches")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
            }
            ForEach(Array(dropdownItems.enumerated()), id: \.offset) { _, s in
                dropdownRow(icon: showingRecentSearches ? "clock.arrow.circlepath" : "magnifyingglass",
                            text: s) {
                    search.choose(s)
                    searchFocused = false
                }
            }
            if showingRecentSearches {
                Divider().padding(.vertical, 2)
                dropdownRow(icon: "trash", text: "Clear Recent Searches", dim: true) {
                    search.clearRecentSearches()
                }
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

                ForEach(model.sections) { SectionShelf(section: $0) }
            }
            .padding(.bottom, 20)
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
        Shelf(title: title) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { i, track in
                SongCard(track: track) {
                    PlayerService.shared.play(tracks: tracks, at: i)
                }
            }
        }
        // Shelves are short — warm every card up front so horizontal
        // scrolling is always loaded.
        .onAppear { ArtworkCache.shared.prefetch(tracks.map { $0.art(300) }) }
    }
}

struct BrowseCard: View {
    let item: BrowseItem

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
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            // Animate the badge when the playing song changes too, not just
            // on hover — switching tracks cross-fades instead of flashing.
            .animation(.snappy(duration: 0.2), value: isCurrent)
            .animation(.snappy(duration: 0.2), value: player.isPlaying)

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
