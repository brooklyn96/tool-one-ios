import SwiftUI

struct DashboardToolbar: View {
    let entry: DashboardEntry
    @ObservedObject var state: DashboardBrowserState
    let clearSession: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack {
            Button(action: state.goBack) { Label("dashboard.back", systemImage: "chevron.backward") }.disabled(!state.canGoBack)
            Button(action: state.goForward) { Label("dashboard.forward", systemImage: "chevron.forward") }.disabled(!state.canGoForward)
            Spacer()
            if state.isLoading {
                Button(action: state.stop) { Label("dashboard.stop", systemImage: "xmark") }
            } else {
                Button(action: state.reload) { Label("dashboard.reload", systemImage: "arrow.clockwise") }
            }
            Menu {
                Button { openURL(state.webView?.url ?? entry.startURL) } label: { Label("dashboard.safari", systemImage: "safari") }
                Button(role: .destructive, action: clearSession) { Label("dashboard.clear.action", systemImage: "trash") }
            } label: {
                Label("dashboard.more", systemImage: "ellipsis.circle")
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
