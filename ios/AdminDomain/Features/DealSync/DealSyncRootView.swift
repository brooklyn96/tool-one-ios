import SwiftUI

enum DealSyncTab: String, CaseIterable, Identifiable {
    case sync, submit, sheets, kpi, more
    var id: String { rawValue }
    var title: String {
        switch self { case .sync: return "Trả kết quả"; case .submit: return "Submit Deal"; case .sheets: return "Sheets"; case .kpi: return "KPI"; case .more: return "Thêm" }
    }
    var symbol: String {
        switch self { case .sync: return "arrow.triangle.2.circlepath"; case .submit: return "paperplane"; case .sheets: return "tablecells"; case .kpi: return "chart.bar.xaxis"; case .more: return "ellipsis.circle" }
    }
}

struct DealSyncRootView: View {
    @StateObject private var auth: DealSyncSessionStore
    @StateObject private var connectivity = ConnectivityMonitor()
    let cache: SnapshotCache?
    let onBackToToolOne: () -> Void

    init(client: DealSyncClient, cache: SnapshotCache?, onBackToToolOne: @escaping () -> Void) {
        self.cache = cache
        self.onBackToToolOne = onBackToToolOne
        _auth = StateObject(wrappedValue: DealSyncSessionStore(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgramHeader(title: "Deal Sync", state: auth.account == nil ? .unknown : .online, onBack: onBackToToolOne, onRefresh: nil)
            Group {
                if auth.isRestoring { ProgressView("Đang khôi phục Deal Sync…") }
                else if let account = auth.account { DealSyncTabShell(auth: auth, account: account, cache: cache) }
                else { DealSyncLoginView(auth: auth) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { if auth.isRestoring { await auth.restore() } }
        .environmentObject(connectivity)
        .onReceive(NotificationCenter.default.publisher(for: .dealSyncSessionInvalid)) { _ in
            auth.account = nil
            auth.error = "Phiên Deal Sync đã hết hạn. Vui lòng đăng nhập lại."
        }
    }
}

private struct DealSyncLoginView: View {
    @ObservedObject var auth: DealSyncSessionStore
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.system(size: 68)).foregroundStyle(.tint)
            Text("Deal Sync").font(.largeTitle.bold())
            Text("Đăng nhập Google bằng tài khoản BeyondK để sử dụng đầy đủ các quy trình native.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let error = auth.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button { Task { await auth.login() } } label: {
                HStack { if auth.isWorking { ProgressView() }; Label("Đăng nhập bằng Google", systemImage: "person.crop.circle.badge.checkmark") }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).disabled(auth.isWorking || !connectivity.isOnline)
            if !connectivity.isOnline { Label("Cần kết nối mạng để đăng nhập", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.orange) }
            Spacer()
        }.padding().navigationTitle("Deal Sync")
    }
}

private struct DealSyncTabShell: View {
    @ObservedObject var auth: DealSyncSessionStore
    let account: DealSyncAccount
    let cache: SnapshotCache?
    @AppStorage("deal-sync-selected-tab") private var selected = DealSyncTab.sync
    @StateObject private var operationLedger: DealSyncOperationLedger
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    init(auth: DealSyncSessionStore, account: DealSyncAccount, cache: SnapshotCache?) {
        self.auth = auth; self.account = account; self.cache = cache
        _operationLedger = StateObject(wrappedValue: DealSyncOperationLedger(accountID: account.id))
    }
    var body: some View {
        VStack(spacing: 0) {
            DealSyncOfflineBanner(isOnline: connectivity.isOnline)
            TabView(selection: $selected) {
                NavigationStack { DealSyncSyncView(client: auth.client, account: account) }.tabItem { Label(DealSyncTab.sync.title, systemImage: DealSyncTab.sync.symbol) }.tag(DealSyncTab.sync)
                NavigationStack { DealSyncSubmitView(client: auth.client, account: account) }.tabItem { Label(DealSyncTab.submit.title, systemImage: DealSyncTab.submit.symbol) }.tag(DealSyncTab.submit)
                NavigationStack { DealSyncSheetsView(client: auth.client, account: account) }.tabItem { Label(DealSyncTab.sheets.title, systemImage: DealSyncTab.sheets.symbol) }.tag(DealSyncTab.sheets)
                NavigationStack { DealSyncKPIView(client: auth.client, account: account, cache: cache) }.tabItem { Label(DealSyncTab.kpi.title, systemImage: DealSyncTab.kpi.symbol) }.tag(DealSyncTab.kpi)
                NavigationStack { DealSyncMoreView(auth: auth, account: account) }.tabItem { Label(DealSyncTab.more.title, systemImage: DealSyncTab.more.symbol) }.tag(DealSyncTab.more)
            }
            .environmentObject(operationLedger)
        }
    }
}
