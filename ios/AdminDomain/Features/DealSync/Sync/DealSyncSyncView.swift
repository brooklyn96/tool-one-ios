import SwiftUI

private enum NativeSyncMode: String, CaseIterable, Identifiable {
    case standard = "STANDARD", shopee = "SHOPEE", liveItemID = "LIVE_ITEM_ID"
    var id: String { rawValue }
    var title: String { switch self { case .standard: return "Pick Brand"; case .shopee: return "Shopee"; case .liveItemID: return "Live Item ID" } }
}

private struct SyncRequestBody: Encodable {
    let mode: String
    let subMode: String?
    let scheduleId: String
    let destinationIds: [String]
    let shopeeSheetName: String?
}

struct DealSyncSyncView: View {
    let client: DealSyncClient
    let account: DealSyncAccount
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var schedules: [DealSyncSchedule] = []
    @State private var destinations: [DealSyncDestination] = []
    @State private var mode = NativeSyncMode.standard
    @State private var subMode = "PICK_DEAL"
    @State private var scheduleID = ""
    @State private var selectedDestinations: Set<String> = []
    @State private var shopeeSheetName = ""
    @State private var search = ""
    @State private var preflight: JSONValue?
    @State private var operation: DealSyncOperation?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var showConfirmation = false

    private var availableModes: [NativeSyncMode] { account.isAdmin ? NativeSyncMode.allCases : [.standard, .shopee] }
    private var filteredDestinations: [DealSyncDestination] {
        destinations.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.spreadsheetId.localizedCaseInsensitiveContains(search) }
    }
    private var canContinue: Bool { !scheduleID.isEmpty && !selectedDestinations.isEmpty && account.capabilities.canSync }

    var body: some View {
        Form {
            if loading { Section { HStack { Spacer(); ProgressView("Đang tải cấu hình…"); Spacer() } } }
            Section("Chế độ") {
                Picker("Nguồn", selection: $mode) { ForEach(availableModes) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                if mode == .shopee {
                    Picker("Nội dung", selection: $subMode) { Text("Pick Deal").tag("PICK_DEAL"); Text("Pick Brand").tag("PICK_BRAND") }
                    TextField("Tên tab Shopee (nếu cần)", text: $shopeeSheetName).textInputAutocapitalization(.never)
                }
                if mode == .liveItemID { Label("Chỉ Admin · dùng nguồn Live Item ID của lịch", systemImage: "lock.shield").font(.footnote).foregroundStyle(.orange) }
            }
            Section("Lịch livestream") {
                Picker("Lịch", selection: $scheduleID) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title.isEmpty ? $0.id : $0.title).tag($0.id) } }
            }
            Section {
                TextField("Tìm destination", text: $search).textInputAutocapitalization(.never)
                HStack {
                    Button("Chọn tất cả") { selectedDestinations.formUnion(filteredDestinations.map(\.id)) }
                    Spacer()
                    Button("Bỏ chọn") { selectedDestinations.removeAll() }
                }.font(.footnote)
                ForEach(filteredDestinations) { destination in
                    Button { toggle(destination.id) } label: {
                        HStack {
                            Image(systemName: selectedDestinations.contains(destination.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) { Text(destination.name); Text(destination.spreadsheetId).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if destination.fromLinkedUser == true { Image(systemName: "link").accessibilityLabel("Từ tài khoản liên kết") }
                        }
                    }.buttonStyle(.plain)
                }
            } header: { Text("Destination · \(selectedDestinations.count) đã chọn") }
            if let preflight { Section("Kiểm tra trước") { JSONValueView(value: preflight) } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button("Kiểm tra trước khi chạy") { Task { await validate() } }
                    .dealSyncMutationDisabled(connectivity.isOnline, busy: working).disabled(!canContinue || working || !connectivity.isOnline)
                Button("Bắt đầu trả kết quả") { showConfirmation = true }.buttonStyle(.borderedProminent)
                    .disabled(!canContinue || working || !connectivity.isOnline || preflight == nil)
            }
        }
        .navigationTitle("Trả kết quả")
        .task { await load() }
        .refreshable { await load() }
        .alert("Bắt đầu đồng bộ?", isPresented: $showConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Bắt đầu") { Task { await start() } }
        } message: { Text("Deal Sync sẽ xử lý \(selectedDestinations.count) destination. Có thể theo dõi tiến trình và quay lại sau.") }
        .sheet(item: $operation) { operation in NavigationStack { DealSyncOperationView(client: client, operation: operation).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { self.operation = nil } } } } }
    }

    private func toggle(_ id: String) { if selectedDestinations.contains(id) { selectedDestinations.remove(id) } else { selectedDestinations.insert(id) } }
    private var requestPayload: SyncRequestBody { SyncRequestBody(mode: mode.rawValue, subMode: mode == .shopee ? subMode : nil, scheduleId: scheduleID, destinationIds: Array(selectedDestinations), shopeeSheetName: shopeeSheetName.isEmpty ? nil : shopeeSheetName) }
    @MainActor private func load() async {
        loading = schedules.isEmpty || destinations.isEmpty; defer { loading = false }
        do {
            async let schedulePage: DealSyncCollection<DealSyncSchedule> = client.send(DealSyncEndpoint("/api/mobile/v2/schedules"))
            async let destinationPage: DealSyncCollection<DealSyncDestination> = client.send(DealSyncEndpoint("/api/mobile/v2/destinations"))
            let pages = try await (schedulePage, destinationPage)
            schedules = pages.0.items
            destinations = pages.1.items
            if scheduleID.isEmpty { scheduleID = schedules.first?.id ?? "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func validate() async {
        working = true; defer { working = false }
        do { preflight = try await client.send(DealSyncEndpoint("/api/mobile/v2/sync/preflight", method: "POST"), body: requestPayload); error = nil }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func start() async {
        working = true; defer { working = false }
        do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/sync/operations", method: "POST"), body: requestPayload); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
