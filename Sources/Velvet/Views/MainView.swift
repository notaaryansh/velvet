import SwiftUI
import QStream
import Observation

enum NavSection: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case liked = "Liked Songs"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .liked: return "heart.fill"
        }
    }
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
    @State private var auth = AuthManager.shared
    @State private var player = PlayerService.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Sidebar(section: $section, auth: auth) {
                    // Tapping Discover (even when already on it) returns to the
                    // feed by clearing any active search.
                    if section == .discover { searchModel.query = "" }
                }
                    .frame(width: 214)
                    .background(VisualEffect(material: .sidebar).ignoresSafeArea())

                Divider().opacity(0.5)

                Group {
                    switch section {
                    case .discover:
                        DiscoverView(model: discoverModel, search: searchModel)
                    case .liked:
                        LikedView(model: likedModel, auth: auth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VisualEffect(material: .underWindowBackground).ignoresSafeArea())
            }
            .padding(.bottom, 72) // room for the player bar

            PlayerBar()

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
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn {
                await LikesStore.shared.ensureLoaded()
            } else {
                LikesStore.shared.reset()
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Binding var section: NavSection
    var auth: AuthManager
    var onReTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar spacer (hidden titlebar) + wordmark
            HStack(spacing: 7) {
                // The real app icon; its bitmap already carries the squircle
                // shape and standard margins, so just render it slightly large.
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 27, height: 27)
                Text("Velvet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 34)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(NavSection.allCases) { s in
                    SidebarItem(section: s, isSelected: section == s) {
                        if section == s { onReTap() } else { section = s }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider().padding(.horizontal, 12)

            // Account row
            Group {
                if !auth.resolved {
                    // Cookie store still loading — don't flash "Sign in".
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Checking session…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if auth.isLoggedIn {
                    HStack(spacing: 9) {
                        avatar
                        VStack(alignment: .leading, spacing: 1) {
                            Text(auth.accountName ?? "Signed in")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(auth.accountHandle ?? "Sign out")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button {
                            Task { await auth.signOut() }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Sign out")
                    }
                } else {
                    Button {
                        auth.showLogin = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 14))
                            Text("Sign in")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(Velvet.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var avatar: some View {
        Artwork(url: auth.accountPhoto) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
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

// MARK: - Search page

struct SearchView: View {
    @Bindable var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field in the toolbar area
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search songs and artists", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                if model.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                } else if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .frame(maxWidth: 340)
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 14)

            TrackList(tracks: model.results,
                      title: "Search",
                      subtitle: model.results.isEmpty ? nil : "\(model.results.count) songs",
                      emptyIcon: "magnifyingglass",
                      emptyTitle: model.query.isEmpty ? "Search YouTube Music" : "No Results",
                      emptyText: model.query.isEmpty
                        ? "Find any song or artist."
                        : (model.isLoading ? "Searching…" : "Try a different search."),
                      error: model.error)
        }
        .onAppear { focused = true }
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

struct SignedOutState: View {
    var auth: AuthManager
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 46))
                .foregroundStyle(.tertiary)
            Text("Sign in to see your music")
                .font(.system(size: 17, weight: .semibold))
            Text("Your liked songs live in your YouTube Music account.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                auth.showLogin = true
            } label: {
                Text("Sign In")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Velvet.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
