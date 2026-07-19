import SwiftUI

struct DealSyncMoreView: View {
    @ObservedObject var auth: DealSyncSessionStore; let account: DealSyncAccount
    @State private var showLogout = false
    @EnvironmentObject private var ledger: DealSyncOperationLedger
    var body: some View {
        List {
            Section("Công cụ") { NavigationLink("Duplicate Deal") { DealSyncDuplicateView(client: auth.client) }; NavigationLink("Tiến trình đang theo dõi") { DealSyncPendingOperationsView(client: auth.client) }; NavigationLink("Ủy quyền Google Projects") { ProjectAuthorizationView(client: auth.client) } }
            if account.isAdmin { Section("Quản trị") { NavigationLink("Trung tâm quản trị") { DealSyncAdminHub(client: auth.client) }; NavigationLink("Giả lập người dùng") { DealSyncImpersonationView(client: auth.client) } } }
            Section("Tài khoản") { LabeledContent("Tên", value: account.displayName); LabeledContent("Email", value: account.email); LabeledContent("Quyền Sync", value: account.capabilities.canSync ? "Có" : "Không"); LabeledContent("Quyền Submit", value: account.capabilities.canSubmitDeal ? "Có" : "Không"); LabeledContent("Quyền tạo Sheet", value: account.capabilities.canCreateSheet ? "Có" : "Không"); Button("Đăng xuất Deal Sync", role: .destructive) { showLogout = true } }
            Section { Label("Điều khiển hạ tầng nhạy cảm chỉ được giữ trên Web.", systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Thêm").alert("Đăng xuất Deal Sync?", isPresented: $showLogout) { Button("Hủy", role: .cancel) {}; Button("Đăng xuất", role: .destructive) { Task { await auth.logout() } } }
    }
}

private struct DealSyncPendingOperationsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var ledger: DealSyncOperationLedger
    @State private var operations: [DealSyncOperation] = []; @State private var error: String?
    var body: some View { List { ForEach(operations) { operation in NavigationLink { DealSyncOperationView(client: client, operation: operation) } label: { VStack(alignment: .leading) { Text(operation.kind).font(.headline); Text("\(operation.state) · \(operation.progress)%").font(.caption).foregroundStyle(.secondary) } } }; if operations.isEmpty { Text("Không có tiến trình đang theo dõi").foregroundStyle(.secondary) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Tiến trình").task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { var values: [DealSyncOperation] = []; for id in ledger.operationIDs { do { let operation: DealSyncOperation = try await client.send(DealSyncEndpoint("/api/mobile/v2/operations/\(id)")); if operation.isTerminal { ledger.complete(id) } else { values.append(operation) } } catch { self.error = error.localizedDescription } }; operations = values }
}

private struct ProjectAuthorizationView: View {
    let client: DealSyncClient; @Environment(\.openURL) private var openURL
    @State private var projects: [DealSyncProjectAuthorization] = []; @State private var error: String?
    var body: some View { List { ForEach(projects) { project in VStack(alignment: .leading, spacing: 6) { HStack { Text(project.name).font(.headline); Spacer(); Image(systemName: project.authorized && !project.expired ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").foregroundStyle(project.authorized && !project.expired ? Color.green : Color.orange) }; Text(project.authorized ? (project.expired ? "Đã hết hạn" : "Đã kết nối") : "Chưa kết nối").font(.caption); Button("Ủy quyền lại") { if let url = URL(string: project.authorizationUrl, relativeTo: DealSyncClient.productionURL) { openURL(url) } } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Google Projects").task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncProjectAuthorization> = try await client.send(DealSyncEndpoint("/api/mobile/v2/auth/projects")); projects = page.items; error = nil } catch { self.error = error.localizedDescription } }
}

private struct DealSyncDuplicateView: View {
    let client: DealSyncClient; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var schedules: [DealSyncSchedule] = []; @State private var schedule = ""; @State private var forceRefresh = false; @State private var operation: DealSyncOperation?; @State private var logs: JSONValue?; @State private var error: String?
    var body: some View { Form { Picker("Lịch", selection: $schedule) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title).tag($0.id) } }; Toggle("Bỏ cache và quét lại", isOn: $forceRefresh); Button("Quét và chọn Deal trùng") { Task { await scan() } }.disabled(schedule.isEmpty || !connectivity.isOnline); if let logs { Section("Lịch sử") { JSONValueView(value: logs) } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Duplicate Deal").task { await load() }.sheet(item: $operation) { op in NavigationStack { DealSyncDuplicateReviewView(client: client, operation: op, scheduleID: schedule) } } }
    @MainActor private func load() async { do { async let page: DealSyncCollection<DealSyncSchedule> = client.send(DealSyncEndpoint("/api/mobile/v2/schedules")); async let history: JSONValue = client.send(DealSyncEndpoint("/api/mobile/v2/duplicates/logs")); let values = try await (page, history); schedules = values.0.items; logs = values.1 } catch { self.error = error.localizedDescription } }
    @MainActor private func scan() async { struct Body: Encodable { let scheduleId: String; let forceRefresh: Bool }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/duplicates/scan", method: "POST"), body: Body(scheduleId: schedule, forceRefresh: forceRefresh)) } catch { self.error = error.localizedDescription } }
}

private struct DealSyncAdminHub: View {
    let client: DealSyncClient
    private let resources: [(String, String, String)] = [
        ("Người dùng", "/api/mobile/v2/admin/users", "person.2"), ("Permissions", "/api/mobile/v2/admin/permissions", "key"),
        ("Lịch livestream", "/api/mobile/v2/admin/schedules", "calendar"), ("Lưu trữ lịch", "/api/mobile/v2/schedule-archives", "archivebox"),
        ("Submissions", "/api/mobile/v2/admin/submissions", "paperplane"), ("GCP Projects", "/api/mobile/v2/admin/projects", "cloud"),
        ("Quota", "/api/mobile/v2/admin/quota", "gauge"), ("Clusters", "/api/mobile/v2/admin/clusters", "point.3.connected.trianglepath.dotted"),
        ("External Sheets", "/api/mobile/v2/admin/external-sheets", "tablecells"), ("Tier 2 Sessions", "/api/mobile/v2/tier2/sessions", "square.stack.3d.up"),
        ("Maintenance", "/api/mobile/v2/admin/maintenance", "wrench.and.screwdriver"), ("Settings", "/api/mobile/v2/admin/settings", "gearshape"), ("Themes", "/api/mobile/v2/admin/themes", "paintpalette")
    ]
    var body: some View {
        List {
            Section("Quản trị có thao tác") {
                NavigationLink { DealSyncUserPermissionsView(client: client) } label: { Label("Người dùng & Permissions", systemImage: "person.badge.key") }
                NavigationLink { DealSyncScheduleAdminView(client: client) } label: { Label("Lịch livestream", systemImage: "calendar") }
                NavigationLink { DealSyncArchiveAdminView(client: client) } label: { Label("Lưu trữ lịch", systemImage: "archivebox") }
                NavigationLink { DealSyncAdminSubmissionsView(client: client) } label: { Label("Submissions", systemImage: "paperplane") }
                NavigationLink { DealSyncProjectAdminView(client: client) } label: { Label("GCP Projects", systemImage: "cloud") }
                NavigationLink { DealSyncMaintenanceView(client: client) } label: { Label("Maintenance", systemImage: "wrench.and.screwdriver") }
                NavigationLink { DealSyncQuotaSettingsView(client: client) } label: { Label("Quota & Settings", systemImage: "gauge") }
                NavigationLink { DealSyncClusterToolsView(client: client) } label: { Label("Clusters", systemImage: "point.3.connected.trianglepath.dotted") }
                NavigationLink { DealSyncThemeSettingsView(client: client) } label: { Label("Themes", systemImage: "paintpalette") }
            }
            Section("Dữ liệu quản trị") { ForEach(resources.filter { !["/api/mobile/v2/admin/users", "/api/mobile/v2/admin/permissions", "/api/mobile/v2/admin/schedules", "/api/mobile/v2/schedule-archives", "/api/mobile/v2/admin/submissions", "/api/mobile/v2/admin/projects", "/api/mobile/v2/admin/maintenance", "/api/mobile/v2/admin/settings", "/api/mobile/v2/admin/clusters", "/api/mobile/v2/admin/themes"].contains($0.1) }, id: \.1) { item in NavigationLink { DealSyncAdminResourceView(client: client, title: item.0, path: item.1) } label: { Label(item.0, systemImage: item.2) } } }
            Section("Sheet tools") { NavigationLink("Create Deal List / Brand Pool") { DealSyncAdminSheetToolsView(client: client) } }
        }.navigationTitle("Quản trị Deal Sync")
    }
}

private struct DealSyncAdminResourceView: View {
    let client: DealSyncClient; let title: String; let path: String
    @State private var value: JSONValue?; @State private var error: String?
    var body: some View { List { if let value { JSONValueView(value: value) } else { ProgressView() }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle(title).task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { do { value = try await client.send(DealSyncEndpoint(path)); error = nil } catch { self.error = error.localizedDescription } }
}

private struct DealSyncAdminSheetToolsView: View {
    let client: DealSyncClient; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var action = "CREATE_DEAL_LIST"; @State private var spreadsheetId = ""; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View { Form { Picker("Công cụ", selection: $action) { Text("Create Deal List").tag("CREATE_DEAL_LIST"); Text("Scan Brand Pool").tag("BRAND_POOL_SCAN") }; TextField("Spreadsheet ID", text: $spreadsheetId); Button("Thực hiện") { Task { await execute() } }.disabled(spreadsheetId.isEmpty || !connectivity.isOnline); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Sheet tools").sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } } }
    @MainActor private func execute() async { struct Body: Encodable { let action: String; let input: [String: String] }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/sheet-operations", method: "POST"), body: Body(action: action, input: ["spreadsheetId": spreadsheetId])) } catch { self.error = error.localizedDescription } }
}

private struct DealSyncImpersonationView: View {
    let client: DealSyncClient; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var users: [DealSyncAdminUser] = []; @State private var targetUserId = ""; @State private var status: JSONValue?; @State private var error: String?
    var body: some View { Form { if let status { Section("Hiện tại") { JSONValueView(value: status) } }; Section("Chuyển tài khoản hiệu lực") { Picker("Người dùng", selection: $targetUserId) { Text("Chọn người dùng").tag(""); ForEach(users) { Text($0.title).tag($0.id) } }; Button("Bắt đầu giả lập") { Task { await start() } }.disabled(targetUserId.isEmpty || !connectivity.isOnline); Button("Trở về Admin", role: .destructive) { Task { await stop() } }.disabled(!connectivity.isOnline) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Giả lập người dùng").task { await load() } }
    @MainActor private func load() async { do { async let a: JSONValue = client.send(DealSyncEndpoint("/api/mobile/v2/impersonation")); async let b: DealSyncCollection<DealSyncAdminUser> = client.send(DealSyncEndpoint("/api/mobile/v2/admin/users")); let values = try await (a, b); status = values.0; users = values.1.items } catch { self.error = error.localizedDescription } }
    @MainActor private func start() async { struct Body: Encodable { let targetUserId: String }; do { status = try await client.send(DealSyncEndpoint("/api/mobile/v2/impersonation", method: "POST"), body: Body(targetUserId: targetUserId)) } catch { self.error = error.localizedDescription } }
    @MainActor private func stop() async { do { status = try await client.send(DealSyncEndpoint("/api/mobile/v2/impersonation", method: "DELETE"), body: DealSyncEmptyBody()) } catch { self.error = error.localizedDescription } }
}
