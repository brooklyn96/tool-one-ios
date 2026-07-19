import SwiftUI

struct DealSyncKPIView: View {
    let client: DealSyncClient; let account: DealSyncAccount
    private let snapshotStore: DealSyncSnapshotStore?
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var month = Date(); @State private var snapshot: JSONValue?; @State private var cachedAt: Date?; @State private var schedules: [DealSyncSchedule] = []; @State private var scheduleID = ""; @State private var statusColumn = ""; @State private var operation: DealSyncOperation?; @State private var loading = false; @State private var error: String?
    init(client: DealSyncClient, account: DealSyncAccount, cache: SnapshotCache?) { self.client = client; self.account = account; snapshotStore = cache.map(DealSyncSnapshotStore.init) }
    private var monthString: String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"; return formatter.string(from: month) }
    var body: some View {
        List {
            Section("Bộ lọc") { DatePicker("Tháng", selection: $month, displayedComponents: .date); Button("Tải KPI tháng \(monthString)") { Task { await load() } } }
            if loading { ProgressView("Đang tính KPI…") }
            if let snapshot { Section("Tổng hợp") { if let cachedAt { Label("Bản lưu lúc \(cachedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }; JSONValueView(value: snapshot) } }
            if account.isAdmin {
                Section("BD Check") { Picker("Lịch", selection: $scheduleID) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title).tag($0.id) } }; TextField("Cột trạng thái", text: $statusColumn); Button("Chạy BD Check") { Task { await bdCheck() } }.disabled(scheduleID.isEmpty || statusColumn.isEmpty || !connectivity.isOnline) }
                Section("Cache & xuất") {
                    Button("Làm mới cache tháng") { Task { await clearCache() } }.disabled(!connectivity.isOnline)
                    Button("Chuẩn bị dữ liệu xuất báo cáo") { Task { await export() } }.disabled(!connectivity.isOnline)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("KPI").task { await bootstrap() }.refreshable { await load() }.sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } }
    }
    @MainActor private func bootstrap() async { guard account.isAdmin else { error = "KPI hiện chỉ dành cho Admin."; return }; do { let page: DealSyncCollection<DealSyncSchedule> = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedules")); schedules = page.items; await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func load() async {
        guard account.isAdmin else { return }; loading = true; defer { loading = false }
        if snapshot == nil, let snapshotStore, let cached = try? await snapshotStore.load(JSONValue.self, accountID: account.id, resource: "kpi-\(monthString)") { snapshot = cached.value; cachedAt = cached.savedAt }
        do { let fresh: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/kpi?month=\(monthString)")); snapshot = fresh; cachedAt = nil; if let snapshotStore { try? await snapshotStore.save(fresh, accountID: account.id, resource: "kpi-\(monthString)") }; error = nil }
        catch { self.error = snapshot == nil ? error.localizedDescription : "Không thể làm mới; đang hiển thị bản KPI đã lưu." }
    }
    @MainActor private func bdCheck() async { struct Body: Encodable { let scheduleId: String; let statusColumn: String }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/kpi/bd-check", method: "POST"), body: Body(scheduleId: scheduleID, statusColumn: statusColumn)) } catch { self.error = error.localizedDescription } }
    @MainActor private func clearCache() async { struct Body: Encodable { let month: String }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/kpi/cache", method: "POST"), body: Body(month: monthString)); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func export() async { struct Body: Encodable { let month: String }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/kpi/export", method: "POST"), body: Body(month: monthString)) } catch { self.error = error.localizedDescription } }
}
