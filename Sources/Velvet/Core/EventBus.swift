import Foundation
import QStream

/// A single tick of raw player state reported by the hidden WebView bridge.
struct PlayerTick: Sendable {
    let hasVideo: Bool
    let time: Double
    let duration: Double
    let paused: Bool
    let ended: Bool
    let ad: Bool
    let videoId: String
    let title: String
    let artist: String

    init?(dict: [String: Any]) {
        guard let t = dict["t"] as? Double else { return nil }
        hasVideo = dict["hasVideo"] as? Bool ?? false
        time = t
        duration = dict["d"] as? Double ?? 0
        paused = dict["paused"] as? Bool ?? true
        ended = dict["ended"] as? Bool ?? false
        ad = dict["ad"] as? Bool ?? false
        videoId = dict["vid"] as? String ?? ""
        title = dict["title"] as? String ?? ""
        artist = dict["artist"] as? String ?? ""
    }
}

/// Everything in the app flows through these QStream relays as reactive
/// streams. Consumers chain operators (throttle / debounce / compactMap /
/// removeDuplicates) so UI work stays minimal and memory stays flat.
enum AppEvent: Sendable {
    case trackChanged(Track?)
    case playbackLoaded(videoId: String)
    case authChanged(Bool)
    case error(String)
}

final class EventBus: Sendable {
    static let shared = EventBus()

    /// App-level events (auth, track changes, errors).
    let events = Relay<AppEvent>()

    /// High-frequency raw player ticks get their own relay so consumers
    /// can throttle them without filtering the main event stream.
    let ticks = Relay<PlayerTick>()

    func post(_ event: AppEvent) {
        Task { await events.send(event) }
    }

    func post(tick: PlayerTick) {
        Task { await ticks.send(tick) }
    }
}
