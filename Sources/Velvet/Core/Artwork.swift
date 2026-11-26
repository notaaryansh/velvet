import SwiftUI
import AppKit

/// Two-tier artwork loader.
///
/// Memory tier: an NSCache holding decoded images — a moving window over
/// whatever the user is looking at. Rows that scroll back into view render
/// synchronously from here, so artwork never flashes in, no matter how fast
/// the scrolling is. NSCache evicts oldest entries under its limits and on
/// memory pressure, which is the "offloading" side of the window.
///
/// Disk tier: a URLCache honoring HTTP caching, so evicted or relaunch-time
/// loads skip the network.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 256 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config)
    }()

    private init() {
        memory.countLimit = 500
        memory.totalCostLimit = 192 * 1024 * 1024
    }

    /// Synchronous memory-window hit, for flash-free rendering.
    func cached(_ url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        if let running = inFlight[url] { return await running.value }

        let task = Task<NSImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url),
                  let image = NSImage(data: data) else { return nil }
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height) * 4
            memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }

    /// Warm the window ahead of the scroll position so art is already
    /// decoded before its row becomes visible.
    func prefetch(_ urls: [URL?]) {
        for url in urls.compactMap({ $0 })
        where cached(url) == nil && inFlight[url] == nil {
            Task { _ = await self.image(for: url) }
        }
    }
}

/// Drop-in AsyncImage replacement backed by ArtworkCache: cached images
/// render in the same frame (no placeholder flash on scroll-back).
struct Artwork<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: NSImage?

    var body: some View {
        ZStack {
            // Prefer the cache: rows reused by lazy stacks change their url,
            // and `loaded` may briefly belong to the previous row.
            if let image = url.flatMap({ ArtworkCache.shared.cached($0) }) ?? loaded {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            loaded = nil
            guard let url, ArtworkCache.shared.cached(url) == nil else { return }
            let image = await ArtworkCache.shared.image(for: url)
            if !Task.isCancelled { loaded = image }
        }
    }
}
