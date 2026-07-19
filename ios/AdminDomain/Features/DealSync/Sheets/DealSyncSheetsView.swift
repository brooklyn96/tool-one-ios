import SwiftUI

struct DealSyncSheetsView: View {
    let client: DealSyncClient; let account: DealSyncAccount
    @State private var destinations: [DealSyncDestination] = []; @State private var search = ""; @State private var loading = true; @State private var error: String?; @State private var showAdd = false; @State private var showBulkAdd = false
    private var filtered: [DealSyncDestination] { destinations.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.spreadsheetId.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section("Cấu hình") {
                NavigationLink("Master Sheet") { MasterSheetEditor(client: client) }
                NavigationLink("Tạo Deal List sheets") { SheetCreationView(client: client, account: account, destinations: destinations) }
                NavigationLink("Retry tạo sheet lỗi") { DealSyncSheetRetryView(client: client) }
                NavigationLink("Tier 2 sheets") { Tier2SheetsView(client: client, account: account, destinations: destinations) }
                NavigationLink("Chuyển giao sheets") { TransferListView(client: client, account: account, destinations: destinations) }
            }
            Section("Destinations") {
                TextField("Tìm theo tên hoặc Spreadsheet ID", text: $search)
                if loading { ProgressView() }
                ForEach(filtered) { item in NavigationLink { DestinationEditor(client: client, destination: item) { await load() } } label: {
                    VStack(alignment: .leading) { HStack { Text(item.name).font(.headline); if item.fromLinkedUser == true { Image(systemName: "link") } }; Text(item.spreadsheetId).font(.caption).foregroundStyle(.secondary); if let ids = item.shopIds, !ids.isEmpty { Text("Shop IDs: \(ids.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary) } }
                } }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("Sheets").searchable(text: $search).toolbar { Menu { Button("Thêm destination") { showAdd = true }; Button("Thêm nhiều destination") { showBulkAdd = true } } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm destination") }
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showAdd) { NavigationStack { DestinationEditor(client: client, destination: nil) { await load(); showAdd = false } } }
        .sheet(isPresented: $showBulkAdd) { NavigationStack { DealSyncBulkDestinationView(client: client) { await load(); showBulkAdd = false } } }
    }
    @MainActor private func load() async { loading = destinations.isEmpty; defer { loading = false }; do { let page: DealSyncCollection<DealSyncDestination> = try await client.send(DealSyncEndpoint("/api/mobile/v2/destinations")); destinations = page.items; error = nil } catch { self.error = error.localizedDescription } }
}

private struct DestinationEditor: View {
    let client: DealSyncClient; let destination: DealSyncDestination?; let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var name = ""; @State private var spreadsheetId = ""; @State private var keyword = ""; @State private var skipBkAms = false; @State private var shopIDs = ""; @State private var error: String?; @State private var confirmDelete = false
    var body: some View {
        Form {
            Section("Destination") { TextField("Tên", text: $name); TextField("Spreadsheet ID hoặc URL", text: $spreadsheetId).textInputAutocapitalization(.never); TextField("Sheet keyword", text: $keyword); Toggle("Bỏ qua BK AMS", isOn: $skipBkAms); TextField("Shop IDs, phân cách dấu phẩy", text: $shopIDs, axis: .vertical) }
            Section { Button("Lưu") { Task { await save() } }.disabled(name.isEmpty || spreadsheetId.isEmpty || !connectivity.isOnline); if destination != nil { Button("Xóa destination", role: .destructive) { confirmDelete = true }.disabled(!connectivity.isOnline) } }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(destination == nil ? "Thêm destination" : "Sửa destination").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        .onAppear { if let d = destination { name = d.name; spreadsheetId = d.spreadsheetId; keyword = d.sheetKeyword ?? ""; skipBkAms = d.skipBkAms ?? false; shopIDs = d.shopIds?.joined(separator: ",") ?? "" } }
        .alert("Xóa destination?", isPresented: $confirmDelete) { Button("Hủy", role: .cancel) {}; Button("Xóa", role: .destructive) { Task { await remove() } } } message: { Text("Chỉ cấu hình trong app bị xóa; Google Sheet không bị xóa.") }
    }
    private struct DestinationPayload: Encodable { let name: String; let spreadsheetId: String; let sheetKeyword: String?; let skipBkAms: Bool; let shopIds: [String] }
    private var payload: DestinationPayload { DestinationPayload(name: name, spreadsheetId: spreadsheetId, sheetKeyword: keyword.isEmpty ? nil : keyword, skipBkAms: skipBkAms, shopIds: shopIDs.split(whereSeparator: { ",; \n".contains($0) }).map(String.init)) }
    @MainActor private func save() async { do { if let destination { let _: DealSyncDestination = try await client.send(DealSyncEndpoint("/api/mobile/v2/destinations/\(destination.id)", method: "PATCH"), body: payload) } else { let _: DealSyncDestination = try await client.send(DealSyncEndpoint("/api/mobile/v2/destinations", method: "POST"), body: payload) }; await saved(); dismiss() } catch { self.error = error.localizedDescription } }
    @MainActor private func remove() async { guard let destination else { return }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/destinations/\(destination.id)", method: "DELETE"), body: DealSyncEmptyBody()); await saved(); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct MasterSheetEditor: View {
    let client: DealSyncClient; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var spreadsheetId = ""; @State private var sheetName = ""; @State private var tabs: [String] = []; @State private var error: String?
    var body: some View { Form { Section("Master spreadsheet") { TextField("Spreadsheet ID", text: $spreadsheetId); Button("Tải danh sách tabs") { Task { await discover() } }.disabled(spreadsheetId.isEmpty); if !tabs.isEmpty { Picker("Tab", selection: $sheetName) { ForEach(tabs, id: \.self) { Text($0).tag($0) } } } else { TextField("Tên tab", text: $sheetName) } }; Button("Lưu Master Sheet") { Task { await save() } }.disabled(spreadsheetId.isEmpty || sheetName.isEmpty || !connectivity.isOnline); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Master Sheet").task { await load() } }
    private struct MasterPayload: Encodable { let spreadsheetId: String; let sheetName: String }
    @MainActor private func load() async { do { let value: DealSyncMasterSheet? = try await client.send(DealSyncEndpoint("/api/mobile/v2/sheets/master")); spreadsheetId = value?.spreadsheetId ?? ""; sheetName = value?.sheetName ?? "" } catch { self.error = error.localizedDescription } }
    @MainActor private func discover() async { let id = spreadsheetId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? spreadsheetId; do { let value: DealSyncTabs = try await client.send(DealSyncEndpoint("/api/mobile/v2/sheets/tabs?spreadsheetId=\(id)")); tabs = value.sheets; if !tabs.contains(sheetName) { sheetName = tabs.first ?? "" } } catch { self.error = error.localizedDescription } }
    @MainActor private func save() async { do { let _: DealSyncMasterSheet = try await client.send(DealSyncEndpoint("/api/mobile/v2/sheets/master", method: "PUT"), body: MasterPayload(spreadsheetId: spreadsheetId, sheetName: sheetName)) } catch { self.error = error.localizedDescription } }
}

private struct SheetCreationView: View {
    let client: DealSyncClient; let account: DealSyncAccount; let destinations: [DealSyncDestination]
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var schedules: [DealSyncSchedule] = []; @State private var schedule = ""; @State private var selected: Set<String> = []; @State private var shopIDs = ""; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View { Form { Picker("Lịch", selection: $schedule) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title).tag($0.id) } }; TextField("Shop IDs", text: $shopIDs); Section("Destinations") { ForEach(destinations) { d in Button { selected.formSymmetricDifference([d.id]) } label: { Label(d.name, systemImage: selected.contains(d.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain) } }; Button("Tạo Deal List sheets") { Task { await create() } }.disabled(schedule.isEmpty || selected.isEmpty || !connectivity.isOnline || !account.capabilities.canCreateSheet); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Tạo Sheets").task { do { let page: DealSyncCollection<DealSyncSchedule> = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedules")); schedules = page.items } catch { self.error = error.localizedDescription } }.sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } } }
    @MainActor private func create() async { struct Body: Encodable { let scheduleId: String; let shopIds: [String]; let destinationIds: [String] }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/sheets/operations", method: "POST"), body: Body(scheduleId: schedule, shopIds: shopIDs.split(separator: ",").map(String.init), destinationIds: Array(selected))) } catch { self.error = error.localizedDescription } }
}

private struct Tier2SheetsView: View {
    let client: DealSyncClient; let account: DealSyncAccount; let destinations: [DealSyncDestination]
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var month = Date(); @State private var selected: Set<String> = []; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View { Form { DatePicker("Tháng", selection: $month, displayedComponents: .date); Section("Destinations") { ForEach(destinations) { d in Button { selected.formSymmetricDifference([d.id]) } label: { Label(d.name, systemImage: selected.contains(d.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain) } }; Button("Tạo Tier 2") { Task { await run("CREATE") } }; Button("Xóa Tier 2", role: .destructive) { Task { await run("DELETE") } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Tier 2 Sheets").disabled(!connectivity.isOnline || !account.capabilities.canCreateSheet).sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } } }
    @MainActor private func run(_ action: String) async { struct Body: Encodable { let action: String; let month: String; let destinationIds: [String] }; let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/tier2/operations", method: "POST"), body: Body(action: action, month: formatter.string(from: month), destinationIds: Array(selected))) } catch { self.error = error.localizedDescription } }
}

private struct TransferListView: View {
    let client: DealSyncClient; let account: DealSyncAccount; let destinations: [DealSyncDestination]
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var transfers = DealSyncTransfers(sent: [], pendingReview: []); @State private var targets: [DealSyncTransferTarget] = []; @State private var target = ""; @State private var selected: Set<String> = []; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View { List { Section("Tạo yêu cầu") { Picker("Người nhận", selection: $target) { Text("Chọn người nhận").tag(""); ForEach(targets) { Text($0.title).tag($0.id) } }; ForEach(destinations) { d in Button { selected.formSymmetricDifference([d.id]) } label: { Label(d.name, systemImage: selected.contains(d.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain) }; Button("Gửi yêu cầu chuyển") { Task { await create() } }.disabled(target.isEmpty || selected.isEmpty || !connectivity.isOnline) }; Section("Đã gửi") { ForEach(transfers.sent) { transferRow($0, adminReview: false) } }; if account.isAdmin { Section("Chờ duyệt") { ForEach(transfers.pendingReview ?? []) { transferRow($0, adminReview: true) } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Chuyển giao").task { await load() }.refreshable { await load() }.sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } } }
    @ViewBuilder private func transferRow(_ item: DealSyncTransfer, adminReview: Bool) -> some View { VStack(alignment: .leading) { Text(item.sheets?.map(\.name).joined(separator: ", ") ?? item.id).font(.headline); Text(item.status).font(.caption).foregroundStyle(.secondary); HStack { if adminReview { Button("Duyệt") { Task { await action(item.id, "approve") } }; Button("Từ chối", role: .destructive) { Task { await action(item.id, "reject") } } } else if item.status == "APPROVED" { Button("Thực hiện") { Task { await action(item.id, "execute") } } } else if item.status == "PENDING" { Button("Hủy", role: .destructive) { Task { await cancel(item.id) } } } } } }
    @MainActor private func load() async { do { async let a: DealSyncTransfers = client.send(DealSyncEndpoint("/api/mobile/v2/transfers")); async let b: DealSyncCollection<DealSyncTransferTarget> = client.send(DealSyncEndpoint("/api/mobile/v2/transfers/targets")); let values = try await (a, b); transfers = values.0; targets = values.1.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func create() async { struct Body: Encodable { let toUserId: String; let sheetIds: [String] }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/transfers", method: "POST"), body: Body(toUserId: target, sheetIds: Array(selected))); selected.removeAll(); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func action(_ id: String, _ action: String) async { struct Body: Encodable { let action: String }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/transfers/\(id)", method: "PATCH"), body: Body(action: action)); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func cancel(_ id: String) async { do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/transfers/\(id)", method: "DELETE"), body: DealSyncEmptyBody()); await load() } catch { self.error = error.localizedDescription } }
}

private extension Set where Element == String { mutating func formSymmetricDifference(_ values: [String]) { for value in values { if contains(value) { remove(value) } else { insert(value) } } } }
