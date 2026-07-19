import SwiftUI

private extension Notification.Name {
    static let externalSyncRefreshRequested = Notification.Name("ExternalSyncRefreshRequested")
}

@MainActor final class ExternalSyncAuthStore: ObservableObject {
    @Published var user: ExternalUser?
    @Published var isRestoring = true
    @Published var isWorking = false
    @Published var error: String?
    let client: ExternalSyncClient
    init(client: ExternalSyncClient) { self.client = client }
    func restore() async {
        defer { isRestoring = false }
        guard await client.hasStoredSession() else { return }
        do { user = try await client.restore() } catch { self.error = ToolOneFriendlyError.message(for: error) }
    }
    func login(username: String, password: String) async {
        isWorking = true; error = nil; defer { isWorking = false }
        do { user = try await client.login(username: username, password: password) }
        catch { self.error = ToolOneFriendlyError.message(for: error) }
    }
    func logout() async { await client.logout(); user = nil }
}

struct ExternalSyncRootView: View {
    @StateObject private var auth: ExternalSyncAuthStore
    @StateObject private var connectivity = ConnectivityMonitor()
    let cache: SnapshotCache?
    let onBackToToolOne: () -> Void
    init(client: ExternalSyncClient, cache: SnapshotCache?, onBackToToolOne: @escaping () -> Void) {
        self.cache = cache
        self.onBackToToolOne = onBackToToolOne
        _auth = StateObject(wrappedValue: ExternalSyncAuthStore(client: client))
    }
    var body: some View {
        VStack(spacing: 0) {
            ProgramHeader(
                title: "External Sync",
                state: auth.user == nil ? .unknown : .online,
                onBack: onBackToToolOne,
                onRefresh: { NotificationCenter.default.post(name: .externalSyncRefreshRequested, object: nil) }
            )
            Group {
                if auth.isRestoring { ProgressView("Đang khôi phục phiên External Sync…") }
                else if let user = auth.user { ExternalSyncTabView(auth: auth, user: user, cache: cache) }
                else { ExternalSyncLoginView(auth: auth) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { if auth.isRestoring { await auth.restore() } }
        .environmentObject(connectivity)
        .onReceive(NotificationCenter.default.publisher(for: .externalSyncSessionInvalid)) { _ in
            auth.user = nil
            auth.error = "Phiên External Sync đã hết hạn. Vui lòng đăng nhập lại."
        }
    }
}

private struct ExternalSyncLoginView: View {
    @ObservedObject var auth: ExternalSyncAuthStore
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var username = ""; @State private var password = ""; @State private var showForgot = false
    var body: some View {
        ScrollView {
            VStack(spacing: ToolOneLayout.spacingM) {
                Spacer(minLength: ToolOneLayout.spacingL)
                ZStack {
                    Circle().fill(ToolOneBrand.electric.opacity(0.12))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.largeTitle.bold())
                        .foregroundStyle(ToolOneBrand.electric)
                }
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

                VStack(spacing: ToolOneLayout.spacingXS) {
                    Text("External Sync").font(.largeTitle.bold())
                    Text("Quản lý và đồng bộ Deal List ngay trên iPhone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
                    Text("Tài khoản").font(.headline)
                    TextField("Tên đăng nhập", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: ToolOneLayout.minimumTouchTarget)
                    SecureField("Mật khẩu", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: ToolOneLayout.minimumTouchTarget)
                    if let error = auth.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button { Task { await auth.login(username: username, password: password) } } label: {
                        HStack {
                            if auth.isWorking { ProgressView() }
                            Text(auth.isWorking ? "Đang đăng nhập…" : "Đăng nhập")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ToolOneLayout.minimumTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ToolOneBrand.electric)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || auth.isWorking || !connectivity.isOnline)

                    Button("Quên mật khẩu?") { showForgot = true }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ToolOneLayout.minimumTouchTarget)
                    if !connectivity.isOnline {
                        Label("Cần kết nối mạng để đăng nhập", systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .toolOneCard()
            }
            .padding(ToolOneLayout.spacingS)
        }
        .background(ToolOneSurface.canvas)
        .sheet(isPresented: $showForgot) { ExternalForgotPasswordView(client: auth.client) }
    }
}

private struct ExternalForgotPasswordView: View {
    let client: ExternalSyncClient
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""; @State private var message: String?; @State private var error: String?
    @State private var showReset = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Khôi phục") {
                    TextField("Tên đăng nhập", text: $username).textInputAutocapitalization(.never)
                    if let message { Text(message).foregroundStyle(.green) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Gửi yêu cầu") { Task { await submit() } }.disabled(username.isEmpty)
                    Button("Tôi có mã đặt lại mật khẩu") { showReset = true }
                }
            }.navigationTitle("Quên mật khẩu").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
            .sheet(isPresented: $showReset) { ExternalResetPasswordView(client: client) }
        }
    }
    @MainActor private func submit() async {
        do { message = try await client.forgotPassword(username: username) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ExternalResetPasswordView: View {
    let client: ExternalSyncClient
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""; @State private var password = ""; @State private var confirmation = ""; @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Mã đặt lại", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Mật khẩu mới", text: $password)
                SecureField("Nhập lại mật khẩu", text: $confirmation)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Đặt lại mật khẩu") { Task { await submit() } }.disabled(token.isEmpty || password.count < 6 || password != confirmation)
            }.navigationTitle("Đặt lại mật khẩu").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        }
    }
    @MainActor private func submit() async {
        do { try await client.resetPassword(token: token, newPassword: password); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct ExternalSyncTabView: View {
    @ObservedObject var auth: ExternalSyncAuthStore
    let user: ExternalUser
    let cache: SnapshotCache?
    @AppStorage("external-sync-selected-tab") private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { ExternalHomeView(client: auth.client, user: user, cache: cache, onOpenDealLists: { selectedTab = 1 }) }
                .tabItem { Label("Trang chủ", systemImage: "house") }
                .tag(0)
            NavigationStack { ExternalDealListsView(client: auth.client, cache: cache, cacheNamespace: user.id) }
                .tabItem { Label("Deal Lists", systemImage: "list.bullet.rectangle") }
                .tag(1)
            NavigationStack { ExternalLogsView(client: auth.client, isAdmin: user.isAdmin, cache: cache, cacheNamespace: user.id) }
                .tabItem { Label("Nhật ký", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            NavigationStack { ExternalMoreView(auth: auth, user: user) }
                .tabItem { Label("Thêm", systemImage: "ellipsis.circle") }
                .tag(3)
        }
    }
}

struct ExternalHomeView: View {
    let client: ExternalSyncClient; let user: ExternalUser; let cache: SnapshotCache?
    let onOpenDealLists: () -> Void
    @State private var dashboard: DashboardDTO?; @State private var error: String?; @State private var loading = true
    @State private var isStale = false
    var body: some View {
        AsyncStateView(state: presentationState, retry: { Task { await load() } }) {
            if let dashboard {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ToolOneLayout.spacingM) {
                        if isStale {
                            Label("Đang hiển thị dữ liệu đã lưu", systemImage: "clock.badge.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if dashboard.isReadyEmpty {
                            readyEmptyState
                        } else {
                            dashboardContent(dashboard)
                        }
                    }
                    .padding(ToolOneLayout.spacingS)
                }
                .background(ToolOneSurface.canvas)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Tổng quan")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .externalSyncRefreshRequested)) { _ in
            Task { await load() }
        }
    }

    private var presentationState: AsyncPresentationState {
        if loading && dashboard == nil { return .loading(message: "Đang tải External Sync…") }
        if let error, dashboard == nil {
            return .failure(title: "Không tải được dữ liệu", message: error)
        }
        return .content
    }

    private var readyEmptyState: some View {
        VStack(spacing: ToolOneLayout.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle, design: .rounded).bold())
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("External Sync đã sẵn sàng")
                .font(.title2.bold())
            Text("Hiện chưa có Deal List. Tạo Deal List đầu tiên để bắt đầu đồng bộ dữ liệu.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryProgramButton(title: "Đi tới Deal Lists", systemImage: "list.bullet.rectangle", action: onOpenDealLists)
        }
        .frame(maxWidth: .infinity)
        .toolOneCard()
    }

    private func dashboardContent(_ dashboard: DashboardDTO) -> some View {
        VStack(alignment: .leading, spacing: ToolOneLayout.spacingM) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ToolOneLayout.spacingS) {
                MetricTile(label: "Deal Lists", value: "\(dashboard.dealLists.total)", systemImage: "list.bullet")
                MetricTile(label: "Đang chạy", value: "\(dashboard.dealLists.active)", systemImage: "play.circle")
                MetricTile(label: "Thành công", value: "\(dashboard.processes.successful)", systemImage: "checkmark.circle")
                MetricTile(label: "Thất bại", value: "\(dashboard.processes.failed)", systemImage: "xmark.circle")
            }

            HStack(spacing: ToolOneLayout.spacingS) {
                Image(systemName: dashboard.scheduler.isRunning ? "clock.badge.checkmark" : "clock.badge.xmark")
                    .foregroundStyle(dashboard.scheduler.isRunning ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboard.scheduler.isRunning ? "Scheduler đang hoạt động" : "Scheduler đang dừng").font(.headline)
                    Text("\(dashboard.scheduler.activeDealLists) Deal List đang được theo dõi")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .toolOneCard()

            VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
                Text("Hoạt động gần đây").font(.title2.bold())
                if dashboard.recentActivity.isEmpty {
                    Text("Chưa có hoạt động").foregroundStyle(.secondary).toolOneCard()
                }
                ForEach(dashboard.recentActivity.prefix(5)) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.message).font(.subheadline)
                        Text(log.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .toolOneCard()
                }
            }
        }
    }
    @MainActor private func load() async {
        loading = dashboard == nil; defer { loading = false }
        do {
            dashboard = try await client.send("/api/mobile/v2/dashboard"); error = nil; isStale = false
            if let dashboard { try? await cache?.save(dashboard, key: "external-\(user.id)-dashboard") }
        } catch {
            if dashboard == nil, let cached = try? await cache?.load(DashboardDTO.self, key: "external-\(user.id)-dashboard") { dashboard = cached; isStale = true; self.error = nil }
            else { self.error = ToolOneFriendlyError.message(for: error) }
        }
    }
}
