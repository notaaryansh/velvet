import Foundation
import WebKit
import CryptoKit
import Observation

/// Cookie-based Google auth, same model Kaset uses:
/// the WKWebsiteDataStore holds the Google session cookies and we sign
/// InnerTube requests with SAPISIDHASH derived from __Secure-3PAPISID.
@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    var isLoggedIn = false
    /// False until the cookie store has actually been checked after launch.
    /// The UI must show a neutral loading state, never "signed out", while
    /// this is false — WebKit's cookie store hydrates asynchronously.
    var resolved = false
    var showLogin = false
    var accountName: String?
    var accountHandle: String?
    var accountPhoto: URL?

    nonisolated static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        // Dev preview: render the signed-out experience without touching the
        // real session (`VELVET_PREVIEW_SIGNED_OUT=1 Velvet.app/...`).
        if ProcessInfo.processInfo.environment["VELVET_PREVIEW_SIGNED_OUT"] == "1" {
            resolved = true
            if isLoggedIn { isLoggedIn = false; EventBus.shared.post(.authChanged(false)) }
            return
        }
        var has = await hasAuthCookies()
        // On a cold launch the default data store can report no cookies for a
        // moment before it finishes reading from disk. Before the first
        // resolution, re-check briefly instead of flashing "signed out".
        if !has && !resolved {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(250))
                has = await hasAuthCookies()
                if has { break }
            }
        }
        resolved = true
        if has != isLoggedIn {
            isLoggedIn = has
            EventBus.shared.post(.authChanged(has))
        }
        if has, accountName == nil {
            await fetchAccount()
        }
    }

    /// The session is only usable for InnerTube once the YouTube-domain
    /// auth cookies exist — a google.com-only session is not enough.
    private func hasAuthCookies() async -> Bool {
        await allCookies().contains {
            $0.name == "__Secure-3PAPISID" && $0.domain.contains("youtube")
        }
    }

    func fetchAccount() async {
        guard let info = try? await YTMusicClient.shared.accountInfo() else { return }
        accountName = info.name
        accountHandle = info.handle
        accountPhoto = info.photo
    }

    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                cont.resume(returning: cookies)
            }
        }
    }

    /// Cookie header + SAPISIDHASH authorization for music.youtube.com.
    func authHeaders() async -> [String: String] {
        let cookies = await allCookies().filter { $0.domain.hasSuffix("youtube.com") }
        guard !cookies.isEmpty else { return [:] }

        var headers: [String: String] = [:]
        headers["Cookie"] = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        if let sapisid = cookies.first(where: { $0.name == "__Secure-3PAPISID" })?.value
            ?? cookies.first(where: { $0.name == "SAPISID" })?.value {
            let ts = Int(Date().timeIntervalSince1970)
            let origin = "https://music.youtube.com"
            let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) \(origin)".utf8))
            let hash = digest.map { String(format: "%02x", $0) }.joined()
            headers["Authorization"] = "SAPISIDHASH \(ts)_\(hash)"
            headers["X-Origin"] = origin
        }
        return headers
    }

    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
        accountName = nil
        accountHandle = nil
        accountPhoto = nil
        await refresh()
    }
}
