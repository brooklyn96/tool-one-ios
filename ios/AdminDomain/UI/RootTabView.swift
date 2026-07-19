import SwiftUI

struct RootTabView: View {
    @ObservedObject var router: AppRouter
    let environment: AppEnvironment
    let api: APIClient
    let cache: SnapshotCache?
    let keychain: KeychainStore
    @ObservedObject var programsStore: ProgramsStore
    @ObservedObject var externalSyncLiveStore: ExternalSyncLiveStore
    let onUnpaired: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                OverviewView(store: programsStore, api: api, onOpenProgram: router.open)
            }
            .tabItem { Label(AppTab.overview.localizedTitle, systemImage: AppTab.overview.systemImage) }
            .tag(AppTab.overview)

            NavigationStack {
                ActivityView(store: programsStore, api: api)
            }
            .tabItem { Label(AppTab.activity.localizedTitle, systemImage: AppTab.activity.systemImage) }
            .tag(AppTab.activity)

            NavigationStack {
                SettingsView(environment: environment, api: api, cache: cache, keychain: keychain, onUnpaired: onUnpaired)
            }
            .tabItem { Label(AppTab.settings.localizedTitle, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: router.selectedTab)
        .onReceive(externalSyncLiveStore.$summary) { summary in
            if let summary {
                programsStore.applyExternalSync(summary)
            }
        }
    }
}

private struct SettingsView: View {
    let environment: AppEnvironment
    let api: APIClient
    let cache: SnapshotCache?
    let keychain: KeychainStore
    let onUnpaired: () async -> Void
    @State private var showConfirmation = false
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        List {
            Section("settings.environment") {
                LabeledContent("settings.mode", value: environment.deployment.rawValue)
                LabeledContent("settings.api", value: environment.baseURL.host ?? "—")
            }
            Section("settings.security") {
                Label("settings.httpsOnly", systemImage: "lock.shield").foregroundStyle(.secondary)
                Button("Ghép nối lại để cấp quyền thao tác", role: .destructive) { showConfirmation = true }.frame(minHeight: 44)
            }
            Section("settings.webDashboards") {
                NavigationLink {
                    DashboardCatalogView(api: api, cache: cache)
                } label: {
                    Label("settings.webDashboards.detail", systemImage: "safari")
                }
                .frame(minHeight: ToolOneLayout.minimumTouchTarget)
            }
            Section("settings.accessibility") {
                Label(
                    accessibilityReduceMotion ? "Giảm chuyển động đang bật" : "Tôn trọng cài đặt Giảm chuyển động",
                    systemImage: "accessibility"
                )
                .foregroundStyle(.secondary)
                Label("Hỗ trợ Dynamic Type và VoiceOver", systemImage: "textformat.size")
                    .foregroundStyle(.secondary)
            }
            Section("settings.about") {
                LabeledContent("settings.version", value: versionDescription)
                LabeledContent("Thiết bị mục tiêu", value: "iPhone · iOS 16+")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("settings.title")
        .alert("Ghép nối lại thiết bị?", isPresented: $showConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Ghép nối lại", role: .destructive) { Task { await unpair() } }
        } message: { Text("Phiên hiện tại sẽ bị thu hồi. Dữ liệu trên web không bị thay đổi.") }
    }

    @MainActor private func unpair() async {
        do {
            let _: EmptyResponse = try await api.send("/v1/auth/revoke", method: "POST")
            try keychain.delete(account: "refresh-token")
            try? keychain.delete(account: "device-id")
            await onUnpaired()
        } catch { self.error = ToolOneFriendlyError.message(for: error) }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    let environment = try! AppEnvironment(deployment: .development, baseURL: URL(string: "https://invalid.example")!)
    let api = APIClient(baseURL: environment.baseURL)
    let keychain = KeychainStore(service: "preview")
    RootTabView(
        router: AppRouter(),
        environment: environment,
        api: api,
        cache: nil,
        keychain: keychain,
        programsStore: ProgramsStore(api: api, cache: nil),
        externalSyncLiveStore: ExternalSyncLiveStore(client: ExternalSyncClient(keychain: keychain), cache: nil),
        onUnpaired: {}
    )
}
