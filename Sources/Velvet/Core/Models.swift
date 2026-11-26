import Foundation

/// A non-song search result that navigates to a detail page.
struct BrowseItem: Identifiable, Equatable, Hashable {
    enum Kind: String { case artist, album, playlist }
    let id: String        // browseId (channelId for artists, MPRE… for albums)
    let title: String
    let subtitle: String
    let thumbnail: String?
    let kind: Kind

    func art(_ size: Int) -> URL? {
        Track(id: id, title: title, artist: "", durationText: "", thumbnail: thumbnail).art(size)
    }
}

/// One shelf of the Discover feed: either playable songs or browsable
/// albums / playlists / artists.
enum HomeSection: Identifiable {
    case tracks(title: String, tracks: [Track])
    case items(title: String, items: [BrowseItem])

    var title: String {
        switch self {
        case .tracks(let title, _): return title
        case .items(let title, _): return title
        }
    }
    var id: String { title }
}

/// Top-row tabs on Discover.
enum DiscoverTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case charts = "Charts"
    case newReleases = "New Releases"
    var id: String { rawValue }
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case videos = "Videos"
    case albums = "Albums"
    case artists = "Artists"
    case playlists = "Playlists"
    var id: String { rawValue }

    /// WEB_REMIX search filter params (from the ytmusicapi project).
    var param: String? {
        switch self {
        case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
        case .playlists: return "EgWKAQIoAWoKEAkQChAFEAMQBA%3D%3D"
        }
    }

    var isTracks: Bool { self == .songs || self == .videos }
}

struct Track: Identifiable, Equatable, Hashable {
    let id: String          // YouTube videoId
    let title: String
    let artist: String
    let durationText: String
    let thumbnail: String?  // smallest URL InnerTube gave us
    var plays: String?      // e.g. "4.2M plays", when the shelf provides it

    /// Best-effort square artwork at the requested size.
    /// googleusercontent thumbs are resizable via the =wN-hN suffix;
    /// fall back to the ytimg video frame if we have nothing.
    func art(_ size: Int) -> URL? {
        if let thumb = thumbnail {
            if thumb.contains("googleusercontent.com"),
               let range = thumb.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
                var s = thumb
                s.replaceSubrange(range, with: "=w\(size)-h\(size)")
                return URL(string: s)
            }
            if let range = thumb.range(of: #"w\d+-h\d+"#, options: .regularExpression) {
                var s = thumb
                s.replaceSubrange(range, with: "w\(size)-h\(size)")
                return URL(string: s)
            }
            return URL(string: thumb)
        }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }
}
