import SwiftUI
import WebKit

struct DashboardWebView: UIViewRepresentable {
    let entry: DashboardEntry
    @ObservedObject var state: DashboardBrowserState

    func makeCoordinator() -> DashboardWebViewCoordinator {
        DashboardWebViewCoordinator(entry: entry, state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        context.coordinator.attach(to: webView)
        webView.load(URLRequest(url: entry.startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct DashboardBrowserScreen: View {
    let entry: DashboardEntry
    @StateObject private var state = DashboardBrowserState()
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading { ProgressView(value: state.progress).progressViewStyle(.linear) }
            if let error = state.errorMessage {
                HStack {
                    Text(error).font(.footnote).foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("common.retry") { state.reload() }
                }
                .padding(8)
                .background(.red.opacity(0.08))
            }
            DashboardWebView(entry: entry, state: state)
            DashboardToolbar(entry: entry, state: state, clearSession: { showClearConfirmation = true })
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("dashboard.clear.confirm", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("dashboard.clear.action", role: .destructive) {
                Task { await DashboardSessionCleaner.clear(entry: entry); state.reload() }
            }
            Button("common.cancel", role: .cancel) {}
        }
    }
}
