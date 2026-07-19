import SwiftUI
import WebKit

@MainActor
final class DashboardBrowserState: ObservableObject {
    @Published var progress = 0.0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stop() { webView?.stopLoading() }
}

final class DashboardWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let entry: DashboardEntry
    private let policy: DashboardNavigationPolicy
    private let state: DashboardBrowserState
    private var observations: [NSKeyValueObservation] = []

    init(entry: DashboardEntry, state: DashboardBrowserState) {
        self.entry = entry
        self.policy = DashboardNavigationPolicy(entry: entry)
        self.state = state
    }

    @MainActor
    func attach(to webView: WKWebView) {
        state.webView = webView
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak state] webView, _ in
                Task { @MainActor in state?.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak state] webView, _ in
                Task { @MainActor in state?.isLoading = webView.isLoading }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak state] webView, _ in
                Task { @MainActor in state?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak state] webView, _ in
                Task { @MainActor in state?.canGoForward = webView.canGoForward }
            }
        ]
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        switch policy.decision(for: url) {
        case .allow:
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        case .openExternally:
            Task { @MainActor in UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response as? HTTPURLResponse
        let disposition = response?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
            if let url = navigationResponse.response.url { Task { @MainActor in UIApplication.shared.open(url) } }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        Task { @MainActor in state.errorMessage = nil }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        switch policy.decision(for: url) {
        case .allow: webView.load(navigationAction.request)
        case .openExternally: Task { @MainActor in UIApplication.shared.open(url) }
        case .cancel: break
        }
        return nil
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in state.errorMessage = error.localizedDescription }
    }
}

enum DashboardSessionCleaner {
    static func clear(entry: DashboardEntry) async {
        let hosts = Set((entry.allowedHosts + entry.oauthHosts).map { $0.lowercased() })
        let store = WKWebsiteDataStore.default()
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where hosts.contains(where: { domain(cookie.domain, matches: $0) }) {
            await withCheckedContinuation { continuation in
                store.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let matching = records.filter { record in hosts.contains(where: { domain(record.displayName, matches: $0) }) }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: matching) { continuation.resume() }
        }
    }

    private static func domain(_ value: String, matches host: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized == host || normalized.hasSuffix(".\(host)")
    }
}
