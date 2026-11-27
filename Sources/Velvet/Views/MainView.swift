import SwiftUI
import QStream
import Observation

enum NavSection: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case liked = "Liked Songs"
    case playlists = "Playlists"
    case history = "History"
    case queue = "Queue"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .liked: return "heart.fill"
        case .playlists: return "music.note.list"
        case .history: return "clock.arrow.circlepath"
        case .queue: return "list.bullet"
        }
    }
    /// Sidebar grouping: Discover on top, the rest under "Library".
    static let home: [NavSection] = [.discover]
    static let library: [NavSection] = [.liked, .playlists, .history, .queue]
}

// MARK: - Reactive view models

@MainActor
@Observable
final class SearchModel {
    var query = "" {
        didSet {
            let q = query
            Task { await queryStream.set(q) }
        }
    }
    var filter: SearchFilter = .songs {
        didSet { if filter != oldValue { Task { await run(query) } } }
    }
    var results: [Track] = []
    var items: [BrowseItem] = []
    var suggestions: [String] = []
    var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "velvet.recentSearches") ?? []
    var isLoading = false
    var error: String?
    /// Set true the instant a suggestion is chosen / Enter pressed, so the
    /// dropdown hides immediately instead of flashing stale suggestions.
    var suppressSuggestions = false

    @ObservationIgnored private let queryStream = Subject<String>(value: "")
    @ObservationIgnored private var subscriptions: [AnySubscription] = []

    init() {
        Task { [weak self] in
            guard let self else { return }
            // Full results: debounced 350ms so typing never spams the API.
            let debounced = await queryStream.debounce(for: .milliseconds(350))
            let deduped = await debounced.removeDuplicates()
            let sub = await deduped.subscribe { [weak self] q in
                await self?.run(q)
            }
            self.subscriptions.append(sub)

            // Suggestions: snappier 140ms so the dropdown feels live.
            let fast = await queryStream.debounce(for: .milliseconds(140))
            let fastDedup = await fast.removeDuplicates()
            let sug = await fastDedup.subscribe { [weak self] q in
                await self?.loadSuggestions(q)
            }
            self.subscriptions.append(sug)
        }
    }

    func choose(_ suggestion: String) {
        suppressSuggestions = true
        suggestions = []
        query = suggestion
        recordSearch(suggestion)
    }

    /// Remember a committed search (Enter or a chosen suggestion), newest
    /// first, de-duplicated, capped at 10, persisted across launches.
    func recordSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        recentSearches = Array(recentSearches.prefix(10))
        UserDefaults.standard.set(recentSearches, forKey: "velvet.recentSearches")
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "velvet.recentSearches")
    }

    private func loadSuggestions(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { suggestions = []; return }
        suppressSuggestions = false
        let got = (try? await YTMusicClient.shared.searchSuggestions(trimmed)) ?? []
        guard trimmed == query.trimmingCharacters(in: .whitespaces) else { return }
        suggestions = got
    }

    private func run(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []; items = []; isLoading = false
            return
        }
        isLoading = true
        error = nil
        let activeFilter = filter
        do {
            if activeFilter.isTracks {
                let tracks = try await YTMusicClient.shared.searchTracks(trimmed, filter: activeFilter)
                guard trimmed == query.trimmingCharacters(in: .whitespaces), activeFilter == filter else { return }
                results = tracks; items = []
            } else {
                let browse = try await YTMusicClient.shared.searchBrowse(trimmed, filter: activeFilter)
                guard trimmed == query.trimmingCharacters(in: .whitespaces), activeFilter == filter else { return }
                items = browse; results = []
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
@Observable
final class LikedModel {
    var tracks: [Track] = []
    var isLoading = false
    var error: String?

    @ObservationIgnored private var subscriptions: [AnySubscription] = []

    init() {
        // React to sign-in / sign-out over the event bus stream.
        Task { [weak self] in
            guard let self else { return }
            let authStream = await EventBus.shared.events
                .compactMap { event -> Bool? in
                    if case .authChanged(let v) = event { return v } else { return nil }
                }
            let sub = await authStream.subscribe { [weak self] loggedIn in
                guard let self else { return }
                if loggedIn {
                    await self.reload()
                } else {
                    await MainActor.run { self.tracks = [] }
                }
            }
            self.subscriptions.append(sub)
        }
    }

    func reload() async {
        // Re-check cookies first so a just-finished sign-in is picked up.
        await AuthManager.shared.refresh()
        guard AuthManager.shared.isLoggedIn else { return }
        isLoading = true
        error = nil
        do {
            tracks = try await YTMusicClient.shared.likedSongs()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
@Observable
final class DiscoverModel {
    var sections: [HomeSection] = []
    var suggested: [Track] = []
    var topArtists: [BrowseItem] = []
    var isLoading = false
    var loaded = false

    /// Bumped when the sidebar Discover item is re-tapped; observers reset
    /// search and navigation back to the root feed.
    var resetPulse = 0

    var chartSections: [HomeSection] = []
    var chartsLoading = false
    var newReleaseSections: [HomeSection] = []
    var newReleasesLoading = false
    @ObservationIgnored private var chartsLoaded = false
    @ObservationIgnored private var newReleasesLoaded = false

    /// Lazy per-tab loading; each browse tab fetches once per session.
    func load(_ tab: DiscoverTab) async {
        switch tab {
        case .home:
            if !loaded { await reload() }
        case .charts:
            guard !chartsLoaded else { return }
            chartsLoaded = true
            chartsLoading = true
            chartSections = (try? await YTMusicClient.shared.charts()) ?? []
            chartsLoading = false
            Self.prefetchArt(chartSections)
        case .newReleases:
            guard !newReleasesLoaded else { return }
            newReleasesLoaded = true
            newReleasesLoading = true
            newReleaseSections = (try? await YTMusicClient.shared.newReleases()) ?? []
            newReleasesLoading = false
            Self.prefetchArt(newReleaseSections)
        }
    }

    /// Decode every shelf's card art the moment the data lands — waiting
    /// for the carousels' onAppear means images pop in on first visit.
    private static func prefetchArt(_ sections: [HomeSection]) {
        for section in sections {
            switch section {
            case .tracks(_, let tracks):
                ArtworkCache.shared.prefetch(tracks.map { $0.art(300) })
            case .items(_, let items):
                ArtworkCache.shared.prefetch(items.map { $0.art(300) })
            }
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false; loaded = true }

        let recents = RecentsStore.shared
        let names = recents.topArtistNames(limit: 4)
        let recentIds = Set(recents.tracks.map(\.id))

        async let homeSections = (try? YTMusicClient.shared.home()) ?? []
        async let artists = Self.resolveArtists(names)
        async let picks = Self.suggestedTracks(names, excluding: recentIds)

        sections = await homeSections
        topArtists = await artists
        suggested = await picks

        Self.prefetchArt(sections)
        ArtworkCache.shared.prefetch(suggested.map { $0.art(300) })
        ArtworkCache.shared.prefetch(topArtists.map { $0.art(300) })

        // Warm the top artists' full pages so tapping one is instant.
        let toWarm = topArtists
        Task { await PageCache.shared.warmArtists(toWarm) }
    }

    /// Resolve the names of the user's most-played artists into navigable
    /// artist pages (we only store names + per-track art locally).
    private static func resolveArtists(_ names: [String]) async -> [BrowseItem] {
        await withTaskGroup(of: (Int, BrowseItem?).self) { group in
            for (i, name) in names.enumerated() {
                group.addTask {
                    let found = (try? await YTMusicClient.shared.searchBrowse(name, filter: .artists)) ?? []
                    return (i, found.first { $0.kind == .artist })
                }
            }
            var out: [(Int, BrowseItem)] = []
            for await (i, item) in group { if let item { out.append((i, item)) } }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Songs from the artists the user plays most, minus everything already
    /// in recents, interleaved so no single artist dominates the shelf.
    private static func suggestedTracks(_ names: [String], excluding: Set<String>) async -> [Track] {
        guard !names.isEmpty else { return [] }
        let perArtist = await withTaskGroup(of: (Int, [Track]).self) { group in
            for (i, name) in names.enumerated() {
                group.addTask {
                    (i, (try? await YTMusicClient.shared.searchTracks(name, filter: .songs)) ?? [])
                }
            }
            var out = Array(repeating: [Track](), count: names.count)
            for await (i, tracks) in group { out[i] = tracks }
            return out
        }
        var seen = excluding
        var mixed: [Track] = []
        let longest = perArtist.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in perArtist {
                if let t = list[safe: i], seen.insert(t.id).inserted { mixed.append(t) }
            }
        }
        return Array(mixed.prefix(20))
    }
}

// MARK: - Main layout

struct MainView: View {
    @State private var section: NavSection = .discover
    @State private var searchModel = SearchModel()
    @State private var likedModel = LikedModel()
    @State private var discoverModel = DiscoverModel()
    @State private var playlistsModel = PlaylistsModel()
    @State private var historyModel = HistoryModel()
    @State private var auth = AuthManager.shared
    @State private var player = PlayerService.shared
    @AppStorage("velvet.wavesEnabled") private var wavesEnabled = true

    // Launch gating: the wave splash stays up until the preloads land
    // (with a minimum display so it never flashes, and a cap so a dead
    // network can't trap the user on it).
    @State private var discoverWarm = false
    @State private var libraryWarm = false
    @State private var minSplashElapsed = false
    @State private var splashTimedOut = false

    private var showLaunch: Bool {
        !splashTimedOut && !(discoverWarm && libraryWarm && minSplashElapsed)
    }

    var body: some View {
        ZStack {
            Group {
            // One backdrop for the whole window — the icon's waves breathe
            // behind the sidebar and content alike.
            VisualEffect(material: .underWindowBackground).ignoresSafeArea()
            if wavesEnabled {
                // Heavy blur melts the wave edges into soft color fields.
                WavesBackground()
                    .blur(radius: 55)
                    .scaleEffect(1.12)   // hide the blur's faded edges
                    .ignoresSafeArea()
            }

            HStack(spacing: 0) {
                // Sidebar runs the full window height; the player bar lives
                // only under the content column.
                Sidebar(section: $section, auth: auth) {
                    // Re-tapping a section resets it to its root screen.
                    switch section {
                    case .discover: discoverModel.resetPulse += 1
                    case .playlists: playlistsModel.resetPulse += 1
                    default: break
                    }
                }
                .frame(width: 214)
                .background(Color.black.opacity(0.14).ignoresSafeArea())

                Divider().opacity(0.5)

                VStack(spacing: 0) {
                    Group {
                        switch section {
                        case .discover:
                            DiscoverView(model: discoverModel, search: searchModel)
                        case .liked:
                            LikedView(model: likedModel, auth: auth)
                        case .playlists:
                            PlaylistsView(model: playlistsModel, auth: auth)
                        case .history:
                            HistoryView(model: historyModel, auth: auth)
                        case .queue:
                            QueueView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // The bar exists only while something is loaded; it
                    // slides up when the first song starts.
                    if player.current != nil {
                        PlayerBar()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.3), value: player.current != nil)
            }
            }
            // The whole app hides while the splash shows: the window is made
            // transparent then, so only the floating icon is visible.
            .opacity(showLaunch ? 0 : 1)

            // Hidden playback engine.
            HiddenPlayerView()
                .frame(width: 2, height: 2)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .sheet(isPresented: Binding(get: { auth.showLogin },
                                    set: { auth.showLogin = $0 })) {
            LoginSheet()
        }
        // The launch icon sits over everything and crossfades away once
        // the preloads land; the window itself is transparent meanwhile.
        .overlay {
            if showLaunch {
                LaunchWaves()
                    .transition(.opacity)
            }
        }
        .background(WindowTransparency(transparent: showLaunch))
        .animation(.easeInOut(duration: 0.5), value: showLaunch)
        // Warm every top-level page at launch so switching tabs or sidebar
        // sections never shows a loading state.
        .task {
            async let home: Void = discoverModel.load(.home)
            async let charts: Void = discoverModel.load(.charts)
            async let fresh: Void = discoverModel.load(.newReleases)
            _ = await (home, charts, fresh)
            discoverWarm = true
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            minSplashElapsed = true
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            splashTimedOut = true
        }
        .task(id: "\(auth.resolved)-\(auth.isLoggedIn)") {
            guard auth.resolved else { return }
            if auth.isLoggedIn {
                async let liked: Void = likedModel.reload()
                async let playlists: Void = playlistsModel.reload()
                async let history: Void = historyModel.reload()
                _ = await (liked, playlists, history)
                // Hearts share the liked fetch instead of re-downloading it.
                LikesStore.shared.seed(Set(likedModel.tracks.map(\.id)))
            } else {
                LikesStore.shared.reset()
            }
            libraryWarm = true
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var section: NavSection
    var auth: AuthManager
    var onReTap: () -> Void = {}
    @State private var showSettings = false
    @State private var hoverAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar spacer (hidden titlebar) + wordmark
            // No header wordmark — the brand row lives in the footer.
            // Top padding clears the traffic lights.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(NavSection.home) { s in
                    SidebarItem(section: s, isSelected: section == s) {
                        if section == s { onReTap() } else { section = s }
                    }
                }

                Text("Library")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 2)

                ForEach(NavSection.library) { s in
                    SidebarItem(section: s, isSelected: section == s) {
                        if section == s { onReTap() } else { section = s }
                    }
                }
            }
            .padding(.horizontal, 10)
            // Matches the content column's 30pt top so the Discover row
            // sits level with the Home/Charts tab row.
            .padding(.top, 30)

            Spacer()

            Divider().padding(.horizontal, 12)

            // Footer rows share the nav items' exact geometry: 20pt icon
            // column, same padding, same hover treatment.
            VStack(alignment: .leading, spacing: 2) {
                if !auth.resolved {
                    SidebarFooterRow(hovering: false) {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                            .frame(width: 20)
                        Text("Checking session…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if auth.isLoggedIn {
                    Menu {
                        Text(auth.accountName ?? "Signed in")
                        if let handle = auth.accountHandle { Text(handle) }
                        Divider()
                        Button("Settings…") { showSettings = true }
                        Divider()
                        Button("Sign Out", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                    } label: {
                        SidebarFooterRow(hovering: hoverAccount) {
                            // 18pt image centered in the 20pt glyph column,
                            // matching the nav symbols' optical size.
                            Artwork(url: auth.accountPhoto) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                            .frame(width: 20)
                            Text(auth.accountName ?? "Signed in")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .onHover { hoverAccount = $0 }
                } else {
                    Button {
                        auth.showLogin = true
                    } label: {
                        SidebarFooterRow(hovering: hoverAccount) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Velvet.accent)
                                .frame(width: 20)
                            Text("Sign in")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Velvet.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { hoverAccount = $0 }
                }

                // Brand row: the wordmark lives down here; Settings moved
                // into the account dropdown above.
                SidebarFooterRow(hovering: false) {
                    AppIconMark(size: 18)
                        .frame(width: 20)
                    Text("Velvet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: 0xE3A7C0), Color(hex: 0xA84860)],
                                           startPoint: .top, endPoint: .bottom))
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .sheet(isPresented: $showSettings) { SettingsSheet() }
        }
    }
}

/// The app icon rendered crisp at small sizes: the icon bitmap carries the
/// standard macOS tile margins (~20% of the canvas), so drawn naively at
/// 18pt the visible tile is ~14pt of rescaled low-res rep — blurry. This
/// scales the margins away so the tile fills the frame, with high-quality
/// downsampling.
struct AppIconMark: View {
    let size: CGFloat
    private static let marginScale: CGFloat = 1024.0 / 824.0

    var body: some View {
        ZStack {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: size * Self.marginScale, height: size * Self.marginScale)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// Row chrome identical to SidebarItem: 10pt padding, 7pt rounded hover.
struct SidebarFooterRow<Content: View>: View {
    var hovering: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.045) : .clear)
            )
            .contentShape(Rectangle())
    }
}

/// Minimal settings: the knobs that actually exist today.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("velvet.wavesEnabled") private var wavesEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 17, weight: .bold))

            Toggle("Ambient wave background", isOn: $wavesEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button("Clear Recent Searches") {
                UserDefaults.standard.removeObject(forKey: "velvet.recentSearches")
            }
            .controlSize(.small)

            Spacer()

            HStack {
                Text("Velvet 0.1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320, height: 220)
    }
}

struct SidebarItem: View {
    let section: NavSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Velvet.accent : .secondary)
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.85))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.09)
                          : (hovering ? Color.primary.opacity(0.045) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Liked page

struct LikedView: View {
    var model: LikedModel
    var auth: AuthManager

    var body: some View {
        if !auth.resolved {
            // Session check still in flight — neutral spinner, never the
            // signed-out pitch.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !auth.isLoggedIn {
            SignedOutState(auth: auth)
        } else {
            TrackList(tracks: model.tracks,
                      title: "Liked Songs",
                      subtitle: model.tracks.isEmpty ? nil : "\(model.tracks.count) songs",
                      emptyIcon: "heart",
                      emptyTitle: model.isLoading ? "Loading…" : "No Liked Songs",
                      emptyText: model.isLoading
                        ? "Opening your collection."
                        : "Songs you like on YouTube Music appear here.",
                      error: model.error,
                      onReload: { Task { await model.reload() } })
                // Refresh every visit so hearts toggled elsewhere show up;
                // existing rows stay on screen while the reload runs.
                .task { await model.reload() }
        }
    }
}

/// Gradient sign-in capsule shared by the signed-out surfaces.
struct SignInButton: View {
    var auth: AuthManager
    var body: some View {
        Button {
            auth.showLogin = true
        } label: {
            Text("Sign In")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 9)
                .background(Capsule().fill(
                    LinearGradient(colors: [Velvet.accent, Color(hex: 0xA6182F)],
                                   startPoint: .top, endPoint: .bottom)))
        }
        .buttonStyle(.plain)
    }
}

/// Full-page signed-out state: the icon as a hero over the velvet backdrop.
struct SignedOutState: View {
    var auth: AuthManager
    var body: some View {
        VStack(spacing: 20) {
            AppIconMark(size: 84)
                .shadow(color: Color(hex: 0x8C1F3C).opacity(0.55), radius: 28, y: 10)
            Text("Sign in to continue")
                .font(.system(size: 22, weight: .bold))
            SignInButton(auth: auth)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact sign-in banner at the top of the signed-out Discover feed.
struct SignInHero: View {
    var auth: AuthManager
    var body: some View {
        HStack(spacing: 16) {
            AppIconMark(size: 46)
                .shadow(color: Color(hex: 0x8C1F3C).opacity(0.5), radius: 12, y: 4)
            Text("Sign in to continue")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            SignInButton(auth: auth)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: 0x8C1F3C).opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color(hex: 0xE3A7C0).opacity(0.14)))
        .padding(.horizontal, 22)
    }
}
