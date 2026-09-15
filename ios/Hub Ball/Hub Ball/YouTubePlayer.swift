import SwiftUI
import WebKit

/// YouTube owns playback, captions, ads and fullscreen controls. No video files
/// are downloaded. App identity follows YouTube's native WebView requirements.
struct YouTubePlayer: UIViewRepresentable {
    let video: WatchVideo

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.videoID != video.id else { return }
        context.coordinator.videoID = video.id
        let identity = "https://\((Bundle.main.bundleIdentifier ?? "com.sfrancoe.HubBall").lowercased())"
        var components = URLComponents(string: "https://www.youtube.com/embed/\(video.id)")!
        components.queryItems = [URLQueryItem(name: "playsinline", value: "1"),
                                URLQueryItem(name: "origin", value: identity)]
        var request = URLRequest(url: components.url!)
        request.setValue(identity, forHTTPHeaderField: "Referer")
        view.load(request)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var videoID: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            // Let player resources navigate, but send explicitly tapped links to
            // the system so sign-in and channel links don't replace the player.
            if navigationAction.navigationType == .linkActivated {
                if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(["https", "about"].contains(url.scheme ?? "") ? .allow : .cancel)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
            return nil
        }
    }
}
