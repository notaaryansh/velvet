import SwiftUI
import WebKit

/// Google sign-in in a WebView sharing the default data store,
/// so the session cookies become available to the API client and player.
struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to YouTube Music")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(VisualEffect(material: .titlebar))

            LoginWebView {
                Task {
                    await AuthManager.shared.refresh()
                    if AuthManager.shared.isLoggedIn {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 520, height: 640)
    }
}

struct LoginWebView: NSViewRepresentable {
    let onNavigated: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onNavigated: onNavigated) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = AuthManager.userAgent
        wv.navigationDelegate = context.coordinator
        let url = URL(string:
            "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigated: () -> Void
        init(onNavigated: @escaping () -> Void) { self.onNavigated = onNavigated }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigated()
        }
    }
}
