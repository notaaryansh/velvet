import Foundation
import WebKit
import QStream
import Observation
import SwiftUI

/// Singleton playback engine: one hidden WKWebView loads
/// music.youtube.com/watch?v=… and plays through WebKit (DRM-capable).
/// An injected observer script streams state back over the EventBus;
/// Velvet's own queue is the source of truth — if YouTube auto-advances
/// on its own, we immediately steer back to our queue.
@MainActor
@Observable
final class PlayerService: NSObject {
    static let shared = PlayerService()

    // Observable playback state
    var current: Track?
    var queue: [Track] = []
    var index: Int = 0
    var isPlaying = false
    /// True from pressing play until audio actually starts — drives the
    /// spinner in the transport.
    var isBuffering = false
    var adPlaying = false
    var progress: Double = 0
    var duration: Double = 0
    var volume: Double = 1.0
    var shuffleEnabled = false
    var lastTickAt: Date = .distantPast
    @ObservationIgnored private var unshuffledQueue: [Track] = []
    /// Latched while an end-of-song advance is in flight: ended ticks keep
    /// arriving every 500ms during the async suggestions fetch, and without
    /// the latch next() ran once per tick, racing the queue index away from
    /// the playing video (frozen playhead).
    @ObservationIgnored private var advancing = false
    /// True after the user explicitly paused; the auto-start nudges must
    /// never override this, only an explicit play clears it.
    @ObservationIgnored private var userPaused = false

    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var lastLoadAt: Date = .distantPast
    @ObservationIgnored private var lastReassertAt: Date = .distantPast
    @ObservationIgnored private var reassertCount = 0
    @ObservationIgnored private var subscriptions: [AnySubscription] = []

    private override init() {
        super.init()
        // Reactive pipeline: raw bridge ticks -> throttled stream -> state.
        Task { [weak self] in
            let throttled = await EventBus.shared.ticks
                .throttle(for: .milliseconds(250))
            let sub = await throttled.subscribe { tick in
                await MainActor.run { PlayerService.shared.handle(tick) }
            }
            self?.subscriptions.append(sub)
        }
        // After a real sign-in, reload the player shell so playback
        // uses the signed-in session (library, premium, no false anon state).
        Task { [weak self] in
            let authStream = await EventBus.shared.events
                .compactMap { event -> Bool? in
                    if case .authChanged(let v) = event { return v } else { return nil }
                }
            let sub = await authStream.subscribe { loggedIn in
                await MainActor.run {
                    let service = PlayerService.shared
                    if loggedIn, service.current == nil {
                        service.webViewReloadHome()
                    }
                }
            }
            self?.subscriptions.append(sub)
        }
    }

    func webViewReloadHome() {
        webView?.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
    }

    /// Smoothly interpolated progress for fluid UI between sparse ticks.
    var liveProgress: Double {
        guard isPlaying, duration > 0 else { return progress }
        return min(progress + Date().timeIntervalSince(lastTickAt), duration)
    }

    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index + 1 < queue.count }

    // MARK: - WebView lifecycle

    func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []

        let script = WKUserScript(source: Self.observerJS,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(BridgeHandler(), name: "velvet")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = AuthManager.userAgent
        wv.navigationDelegate = self
        webView = wv

        // Warm the shell so first playback starts fast and cookies stay fresh.
        wv.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
        return wv
    }

    // MARK: - Controls

    func play(tracks: [Track], at i: Int) {
        guard tracks.indices.contains(i) else { return }
        // Browsing is open; listening needs the account.
        guard AuthManager.shared.isLoggedIn else {
            AuthManager.shared.showLogin = true
            return
        }
        queue = tracks
        index = i
        if shuffleEnabled { applyShuffle() }
        RecentsStore.shared.record(queue[index])
        load(queue[index])
    }

    /// Shuffle on: current track leads, the rest of the queue randomized.
    /// Shuffle off: the original order returns, cursor back on the current.
    func toggleShuffle() {
        shuffleEnabled.toggle()
        guard !queue.isEmpty else { return }
        if shuffleEnabled {
            applyShuffle()
        } else if !unshuffledQueue.isEmpty {
            let playing = queue[index]
            queue = unshuffledQueue
            index = queue.firstIndex(of: playing) ?? 0
        }
    }

    private func applyShuffle() {
        unshuffledQueue = queue
        let playing = queue[index]
        var rest = queue
        rest.remove(at: index)
        rest.shuffle()
        queue = [playing] + rest
        index = 0
    }

    func togglePlay() {
        guard current != nil else { return }
        if isPlaying {
            userPaused = true
            isBuffering = false
            eval("window.__velvetPaused = true; var p = document.getElementById('movie_player'); if (p && p.pauseVideo) { p.pauseVideo(); } else { document.querySelector('video')?.pause(); }")
        } else {
            userPaused = false
            forcePlay()
        }
    }

    func next() {
        if index + 1 < queue.count {
            index += 1
            load(queue[index])
            return
        }
        guard let cur = current else { return }
        if shuffleEnabled {
            // End of queue with shuffle on: keep going with YTM's
            // suggestions, like the official client's autoplay.
            isBuffering = true
            Task { @MainActor in
                let recent = Set(queue.suffix(40).map(\.id))
                let fresh = ((try? await YTMusicClient.shared.related(cur.id)) ?? [])
                    .filter { !recent.contains($0.id) }
                    .prefix(25)
                if fresh.isEmpty {
                    index = 0
                } else {
                    queue += fresh
                    if !unshuffledQueue.isEmpty { unshuffledQueue += fresh }
                    index += 1
                }
                RecentsStore.shared.record(queue[index])
                load(queue[index])
            }
        } else {
            // Shuffle off: loop the queue.
            index = 0
            load(queue[index])
        }
    }

    func previous() {
        // Restart the song if we're a few seconds in, Persona would approve.
        if progress > 4 || !hasPrevious {
            seek(to: 0)
            return
        }
        index -= 1
        load(queue[index])
    }

    func seek(to seconds: Double) {
        progress = seconds
        lastTickAt = Date()
        eval("(function(){var v=document.querySelector('video'); if(v){v.currentTime=\(seconds);}})()")
    }

    func setVolume(_ v: Double) {
        volume = min(max(v, 0), 1)
        applyVolume()
    }

    /// Loudness perception is roughly logarithmic, so feeding the slider
    /// fraction straight into `video.volume` crams all the audible change
    /// into the bottom of the track. A square curve makes the slider feel
    /// linear: `volume` stays the UI fraction, this is what the player gets.
    private var appliedVolume: Double { volume * volume }

    /// YTM's player-API volume scale (0-100), with the perceptual curve.
    private var volumePercent: Int { Int((appliedVolume * 100).rounded()) }

    private func applyVolume() {
        eval("""
        (function(){
          var pct = \(volumePercent);
          window.__velvetVolPct = pct;
          var p = document.getElementById('movie_player');
          if (p && p.setVolume) {
            p.setVolume(pct);
            if (pct === 0 && p.mute) { p.mute(); } else if (p.unMute) { p.unMute(); }
          } else {
            var v = document.querySelector('video');
            if (v) { v.volume = \(appliedVolume); v.muted = \(volume <= 0 ? "true" : "false"); }
          }
        })()
        """)
    }

    /// Robust start: try the <video> element AND click YouTube Music's own
    /// play button, which some restricted tracks require.
    private func forcePlay() {
        eval("""
        (function(){
          window.__velvetPaused = false;
          window.__velvetVolPct = \(volumePercent);
          var mp = document.getElementById('movie_player');
          if (mp && mp.setVolume) { mp.setVolume(\(volumePercent)); }
          if (mp && mp.playVideo) { mp.playVideo(); }
          var v = document.querySelector('video');
          if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function(){}); }
          var btn = document.querySelector('#play-pause-button, tp-yt-paper-icon-button.play-pause-button, ytmusic-player-bar tp-yt-paper-icon-button[aria-label]');
          // Only click if it's currently showing "Play" (paused state).
          if (v && v.paused && btn && (btn.getAttribute('title')||'').toLowerCase().indexOf('play') === 0) { btn.click(); }
        })()
        """)
    }

    // MARK: - Internals

    private func load(_ track: Track) {
        // A fresh user-driven load resets drift tracking; a reassert reload
        // keeps the same track so we don't reset the counter there.
        if current?.id != track.id {
            reassertCount = 0
        }
        current = track
        progress = 0
        duration = 0
        isPlaying = false
        isBuffering = true
        userPaused = false
        advancing = false
        lastLoadAt = Date()

        let wv = ensureWebView()
        let url = URL(string: "https://music.youtube.com/watch?v=\(track.id)")!
        wv.load(URLRequest(url: url))
    }

    private func handle(_ tick: PlayerTick) {
        guard let cur = current else { return }
        let sinceLoad = Date().timeIntervalSince(lastLoadAt)

        // Ad break: audio is an ad, not our song. Freeze progress, never
        // advance — the real track starts when the ad class clears.
        if tick.ad {
            adPlaying = true
            isPlaying = !tick.paused
            lastTickAt = Date()
            return
        }
        adPlaying = false

        // YouTube drifted to a different song (its autoplay/radio took over).
        // Our queue is the source of truth, so steer BACK to the current track
        // once — never advance. If it still mismatches (YTM serves the same
        // song under a different id), stop fighting and just let it play so we
        // don't loop. We NEVER call next() here — that was the skip bug.
        if !tick.videoId.isEmpty, tick.videoId != cur.id, sinceLoad > 10 {
            if reassertCount < 1, Date().timeIntervalSince(lastReassertAt) > 8 {
                reassertCount += 1
                lastReassertAt = Date()
                load(cur)
            }
            return
        }

        guard tick.videoId == cur.id || tick.videoId.isEmpty else { return }

        // Advance only when the *song* truly finished. A track cannot end
        // before roughly its own duration has elapsed in real wall-clock time,
        // so require that much time since load. This defeats "unplayable"
        // tracks (e.g. restricted Prince songs) that load correct metadata but
        // fire `ended` immediately with currentTime snapped to the end — the
        // old cause of "plays a few seconds, then skips".
        if tick.ended,
           !advancing,
           tick.duration > 1,
           tick.time >= tick.duration - 2,
           durationLooksLikeCurrentTrack(tick.duration),
           sinceLoad >= tick.duration - 6 {
            advancing = true
            next()
            return
        }

        if tick.hasVideo {
            isPlaying = !tick.paused
            if !tick.paused || tick.time > 0.3 { isBuffering = false }
            if tick.duration.isFinite, tick.duration > 1,
               durationLooksLikeCurrentTrack(tick.duration) {
                duration = tick.duration
            }
            progress = tick.time
            lastTickAt = Date()
        }
    }

    /// True when a reported media duration plausibly belongs to the current
    /// track rather than an ad. Uses the track's listed duration when known.
    private func durationLooksLikeCurrentTrack(_ reported: Double) -> Bool {
        guard let cur = current else { return false }
        let parts = cur.durationText.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return reported > 60 }   // unknown: ads are short
        let expected = parts.reduce(0) { $0 * 60 + $1 }
        return abs(reported - expected) < 15
    }

    private func eval(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Message handler kept as a tiny NSObject so the user content
    /// controller doesn't retain PlayerService in a cycle.
    private final class BridgeHandler: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "velvet",
                  let dict = message.body as? [String: Any],
                  let tick = PlayerTick(dict: dict) else { return }
            EventBus.shared.post(tick: tick)
        }
    }

    private static let observerJS = """
    (function () {
      if (window.__velvet) return;
      window.__velvet = true;
      setInterval(function () {
        try {
          var v = document.querySelector('video');
          // Keep YTM's own player state aligned with Velvet's intent, via
          // YTM's player API so there's no competing writer on the element.
          var p = document.getElementById('movie_player');
          if (p && typeof window.__velvetVolPct === 'number' && p.getVolume &&
              Math.abs(p.getVolume() - window.__velvetVolPct) > 1) {
            p.setVolume(window.__velvetVolPct);
          }
          if (window.__velvetPaused === true && p && p.getPlayerState && p.getPlayerState() === 1) {
            p.pauseVideo();
          }
          var vid = new URLSearchParams(location.search).get('v') || '';
          var ad = !!document.querySelector('.ad-showing, .ad-interrupting, ytmusic-player[ad-showing]');
          window.webkit.messageHandlers.velvet.postMessage({
            hasVideo: !!v,
            t: v ? (v.currentTime || 0) : 0,
            d: v ? (v.duration || 0) : 0,
            paused: v ? v.paused : true,
            ended: v ? v.ended : false,
            ad: ad,
            vid: vid
          });
        } catch (e) {}
      }, 500);
    })();
    """
}

// MARK: - Navigation delegate: nudge autoplay after each watch-page load

extension PlayerService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard self.current != nil else { return }
            // Persistent start nudges — restricted tracks (e.g. Prince) need
            // several tries and a click on YTM's own play button.
            for delay in [0.6, 1.4, 2.6, 4.0, 6.0, 8.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let service = PlayerService.shared
                    // Stand down once playback started OR the user paused —
                    // a nudge must never undo an explicit pause.
                    guard !service.isPlaying, !service.userPaused else { return }
                    service.forcePlay()
                }
            }
        }
    }
}

// MARK: - Hidden host view (keeps the WebView in the window hierarchy)

struct HiddenPlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
        let wv = PlayerService.shared.ensureWebView()
        wv.frame = container.bounds
        wv.autoresizingMask = [.width, .height]
        if wv.superview !== container {
            wv.removeFromSuperview()
            container.addSubview(wv)
        }
        container.alphaValue = 0.02
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
