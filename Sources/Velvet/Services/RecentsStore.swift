import Foundation
import Observation

/// Remembers recently played tracks (newest first) and per-track play counts,
/// persisted to disk so Discover has something personal to show across
/// launches — recents, most played, and top artists.
@MainActor
@Observable
final class RecentsStore {
    static let shared = RecentsStore()

    private(set) var tracks: [Track] = []
    private(set) var plays: [String: Int] = [:]
    private let limit = 50

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Velvet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recents.json")
    }

    private init() { load() }

    func record(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        tracks.insert(track, at: 0)
        if tracks.count > limit {
            for dropped in tracks.suffix(from: limit) { plays[dropped.id] = nil }
            tracks = Array(tracks.prefix(limit))
        }
        plays[track.id, default: 0] += 1
        save()
    }

    /// Tracks played more than once, heaviest rotation first.
    var mostPlayed: [Track] {
        tracks.filter { plays[$0.id, default: 1] >= 2 }
            .sorted { plays[$0.id, default: 1] > plays[$1.id, default: 1] }
    }

    /// Primary artists ranked by total plays across their recent tracks.
    /// "A & B" / "A, B" credits count toward the first-named artist.
    func topArtistNames(limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for track in tracks {
            let name = track.artist
                .components(separatedBy: CharacterSet(charactersIn: ",&"))
                .first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += plays[track.id, default: 1]
        }
        return order.sorted { counts[$0, default: 0] > counts[$1, default: 0] }
            .prefix(limit).map { $0 }
    }

    // MARK: - Persistence (plain Codable snapshot of Track)

    private struct Stored: Codable {
        let id, title, artist, durationText: String
        let thumbnail: String?
        var plays: Int?
    }

    private func save() {
        let snap = tracks.map { Stored(id: $0.id, title: $0.title, artist: $0.artist,
                                       durationText: $0.durationText, thumbnail: $0.thumbnail,
                                       plays: plays[$0.id]) }
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode([Stored].self, from: data) else { return }
        tracks = snap.map { Track(id: $0.id, title: $0.title, artist: $0.artist,
                                  durationText: $0.durationText, thumbnail: $0.thumbnail) }
        for s in snap { plays[s.id] = s.plays ?? 1 }
    }
}
