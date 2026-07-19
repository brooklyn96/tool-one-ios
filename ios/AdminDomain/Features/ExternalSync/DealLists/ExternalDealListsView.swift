import SwiftUI

struct EmptyMutation: Encodable {}

struct ExternalDealListsView: View {
    let client: ExternalSyncClient; let cache: SnapshotCache?; let cacheNamespace: String
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var items: [DealListDTO] = []; @State private var cursor: String?
    @State private var search = ""; @State private var activeFilter: Bool?; @State private var loading = true
    @State private var error: String?; @State private var showCreate = false
    @State private var isStale = false
    var body: some View {
        List {
            if isStale { Label("Dữ liệu đã lưu — thao tác bị tắt khi offline", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
            Section {
                Picker("Trạng thái", selection: $activeFilter) {
                    Text("Tất cả").tag(Bool?.none); Text("Đang chạy").tag(Bool?.some(true)); Text("Đã dừng").tag(Bool?.some(false))
                }.pickerStyle(.segmented).onChange(of: activeFilter) { _ in Task { await load(reset: true) } }
            }
            if loading && items.isEmpty { HStack { Spacer(); ProgressView(); Spacer() } }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Thử lại") { Task { await load(reset: true) } } } }
            ForEach(items) { item in
                NavigationLink { ExternalDealDetailView(client: client, id: item.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(item.name).font(.headline); Spacer(); status(item.isActive) }
                        Text("\(item.sourceSheetName) → \(item.targetSheetName)").font(.subheadline).foregroundStyle(.secondary)
                        HStack { Text("Đã sync \(item.syncCount) lần"); Spacer(); Text(item.updatedAt, style: .relative) }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            if cursor != nil { Button("Tải thêm") { Task { await load(reset: false) } }.frame(maxWidth: .infinity) }
        }
        .navigationTitle("Deal Lists")
        .searchable(text: $search, prompt: "Tìm theo tên").onSubmit(of: .search) { Task { await load(reset: true) } }
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") }.disabled(!connectivity.isOnline) } }
        .sheet(isPresented: $showCreate) { NavigationStack { DealListEditorView(client: client) { Task { await load(reset: true) } } } }
        .refreshable { await load(reset: true) }.task { await load(reset: true) }
    }
    private func status(_ active: Bool) -> some View {
        Text(active ? "Đang chạy" : "Đã dừng").font(.caption.bold()).foregroundStyle(active ? .green : .secondary)
    }
    @MainActor private func load(reset: Bool) async {
        if reset { loading = true; cursor = nil }; defer { loading = false }
        var components = URLComponents(); components.path = "/api/mobile/v2/deal-lists"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "30"),
            search.isEmpty ? nil : URLQueryItem(name: "search", value: search),
            activeFilter.map { URLQueryItem(name: "active", value: String($0)) },
            reset ? nil : cursor.map { URLQueryItem(name: "cursor", value: $0) },
        ].compactMap { $0 }
        do {
            let page: ExternalPage<DealListDTO> = try await client.send(components.string ?? "/api/mobile/v2/deal-lists")
            items = reset ? page.items : items + page.items.filter { new in !items.contains(where: { $0.id == new.id }) }
            cursor = page.nextCursor; error = nil
            isStale = false
            if reset { try? await cache?.save(items, key: "external-\(cacheNamespace)-deal-lists") }
        } catch {
            if reset, let cached = try? await cache?.load([DealListDTO].self, key: "external-\(cacheNamespace)-deal-lists") {
                items = cached; cursor = nil; isStale = true; self.error = nil
            } else { self.error = error.localizedDescription }
        }
    }
}

struct ExternalDealDetailView: View {
    let client: ExternalSyncClient; let id: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var detail: DealListDetailDTO?; @State private var error: String?; @State private var showEdit = false
    @State private var confirmAction: Action?; @State private var operation: OperationDTO?
    enum Action: String, Identifiable { case start, stop, sync, delete; var id: String { rawValue } }
    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let detail {
                Section("Trạng thái") {
                    LabeledContent("Hoạt động", value: detail.isActive ? "Đang chạy" : "Đã dừng")
                    LabeledContent("Số lần đồng bộ", value: "\(detail.syncCount)")
                    if let date = detail.lastSyncAt { LabeledContent("Lần cuối", value: date.formatted()) }
                }
                Section("Nguồn") {
                    LabeledContent("Spreadsheet", value: detail.sourceSpreadsheetId); LabeledContent("Worksheet", value: detail.sourceSheetName)
                    mapping(detail.sourceColumnMapping)
                }
                Section("Đích") {
                    LabeledContent("Spreadsheet", value: detail.targetSpreadsheetId); LabeledContent("Worksheet", value: detail.targetSheetName)
                    mapping(detail.targetColumnMapping)
                }
                Section("Lịch") {
                    LabeledContent("Ngày livestream", value: detail.livestreamOn ?? detail.livestreamDate ?? "—")
                    LabeledContent("Dừng Review/ATC", value: detail.reviewAtcStopAt?.formatted() ?? "—")
                    LabeledContent("Dừng xử lý", value: detail.stopProcessingAt?.formatted() ?? "—")
                }
                if let operation { Section("Tác vụ") { ExternalOperationView(operation: operation) } }
                Section("Thao tác") {
                    Button("Chỉnh sửa") { showEdit = true }.disabled(!connectivity.isOnline)
                    Button(detail.isActive ? "Dừng" : "Bắt đầu") { confirmAction = detail.isActive ? .stop : .start }.disabled(!connectivity.isOnline)
                    Button("Đồng bộ ngay") { confirmAction = .sync }.disabled(!detail.isActive || !connectivity.isOnline)
                    Button("Xóa Deal List", role: .destructive) { confirmAction = .delete }.disabled(!connectivity.isOnline)
                }
                Section("Lịch sử") {
                    if detail.history.isEmpty { Text("Chưa có lịch sử").foregroundStyle(.secondary) }
                    ForEach(detail.history) { log in VStack(alignment: .leading) { Text(log.message); Text(log.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary) } }
                }
            } else { ProgressView() }
        }.navigationTitle(detail?.name ?? "Deal List").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } } }
        .task { await load(); await restoreOperation() }
        .sheet(isPresented: $showEdit) { if let detail { NavigationStack { DealListEditorView(client: client, detail: detail) { Task { await load() } } } } }
        .confirmationDialog("Xác nhận thao tác", isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } })) {
            if let action = confirmAction { Button(action.rawValue == "delete" ? "Xóa" : "Tiếp tục", role: action == .delete ? .destructive : nil) { Task { await perform(action) } } }
            Button("Hủy", role: .cancel) {}
        }
    }
    @ViewBuilder private func mapping(_ value: [String: String]?) -> some View {
        if let value, !value.isEmpty { ForEach(value.keys.sorted(), id: \.self) { key in LabeledContent(key, value: value[key] ?? "") } }
        else { Text("Chưa cấu hình mapping").foregroundStyle(.secondary) }
    }
    @MainActor private func load() async {
        do { detail = try await client.send("/api/mobile/v2/deal-lists/\(id)"); error = nil } catch { self.error = error.localizedDescription }
    }
    @MainActor private func perform(_ action: Action) async {
        confirmAction = nil
        do {
            switch action {
            case .start, .stop:
                let _: DealListDTO = try await client.send("/api/mobile/v2/deal-lists/\(id)/\(action.rawValue)", method: "POST", body: EmptyMutation(), idempotencyKey: UUID().uuidString)
                await load()
            case .sync:
                struct Body: Encodable { let dealListIds: [String] }
                operation = try await client.send("/api/mobile/v2/operations/sync", method: "POST", body: Body(dealListIds: [id]), idempotencyKey: UUID().uuidString)
                UserDefaults.standard.set(operation?.id, forKey: "external-sync-operation-\(id)")
                await poll()
            case .delete:
                let _: DeleteResult = try await client.send("/api/mobile/v2/deal-lists/\(id)", method: "DELETE", body: EmptyMutation(), idempotencyKey: UUID().uuidString)
                dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func poll() async {
        guard let id = operation?.id else { return }
        for _ in 0..<60 {
            do {
                let current: OperationDTO = try await client.send("/api/mobile/v2/operations/\(id)"); operation = current
                if ["SUCCEEDED", "FAILED", "CANCELLED"].contains(current.status) {
                    UserDefaults.standard.removeObject(forKey: "external-sync-operation-\(self.id)")
                    await load(); return
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch { self.error = error.localizedDescription; return }
        }
    }
    @MainActor private func restoreOperation() async {
        guard operation == nil, let stored = UserDefaults.standard.string(forKey: "external-sync-operation-\(id)") else { return }
        do {
            operation = try await client.send("/api/mobile/v2/operations/\(stored)")
            if let status = operation?.status, ["PENDING", "RUNNING"].contains(status) { await poll() }
            else { UserDefaults.standard.removeObject(forKey: "external-sync-operation-\(id)") }
        } catch {
            UserDefaults.standard.removeObject(forKey: "external-sync-operation-\(id)")
        }
    }
}

private struct ExternalOperationView: View {
    let operation: OperationDTO
    var body: some View {
        VStack(alignment: .leading) { HStack { Text(operation.status).font(.headline); Spacer(); Text("\(operation.progress)%") }; ProgressView(value: Double(operation.progress), total: 100); if let message = operation.errorMessage { Text(message).foregroundStyle(.red) } }
    }
}

struct DealListEditorView: View {
    let client: ExternalSyncClient; let detail: DealListDetailDTO?; let saved: () -> Void
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var input: DealListInputDTO; @State private var sourceMapping = ""; @State private var targetMapping = ""
    @State private var sourceSheets: [String] = []; @State private var targetSheets: [String] = []; @State private var error: String?
    init(client: ExternalSyncClient, detail: DealListDetailDTO? = nil, saved: @escaping () -> Void) {
        self.client = client; self.detail = detail; self.saved = saved
        var value = DealListInputDTO()
        if let d = detail {
            value.name = d.name; value.sourceSpreadsheetId = d.sourceSpreadsheetId; value.sourceSheetName = d.sourceSheetName
            value.sourceColumnMapping = d.sourceColumnMapping; value.targetSpreadsheetId = d.targetSpreadsheetId; value.targetSheetName = d.targetSheetName
            value.targetColumnMapping = d.targetColumnMapping; value.livestreamOn = d.livestreamOn; value.livestreamDate = d.livestreamDate
            value.reviewAtcStopAt = d.reviewAtcStopAt; value.stopProcessingAt = d.stopProcessingAt
        }
        _input = State(initialValue: value)
        _sourceMapping = State(initialValue: Self.mappingText(value.sourceColumnMapping))
        _targetMapping = State(initialValue: Self.mappingText(value.targetColumnMapping))
    }
    var body: some View {
        Form {
            Section("Thông tin") { TextField("Tên", text: $input.name) }
            sheetSection("Nguồn", id: $input.sourceSpreadsheetId, sheet: $input.sourceSheetName, sheets: sourceSheets) { await discover(input.sourceSpreadsheetId, source: true) }
            Section("Mapping nguồn (mỗi dòng key=value)") { TextEditor(text: $sourceMapping).frame(minHeight: 100) }
            sheetSection("Đích", id: $input.targetSpreadsheetId, sheet: $input.targetSheetName, sheets: targetSheets) { await discover(input.targetSpreadsheetId, source: false) }
            Section("Mapping đích (mỗi dòng key=value)") { TextEditor(text: $targetMapping).frame(minHeight: 100) }
            Section("Lịch") {
                TextField("Ngày livestream YYYY-MM-DD", text: Binding(get: { input.livestreamOn ?? "" }, set: { input.livestreamOn = $0.isEmpty ? nil : $0 }))
                TextField("Ngày legacy DD.MM (tùy chọn)", text: Binding(get: { input.livestreamDate ?? "" }, set: { input.livestreamDate = $0.isEmpty ? nil : $0 }))
                optionalDate("Dừng Review/ATC", value: $input.reviewAtcStopAt)
                optionalDate("Dừng xử lý", value: $input.stopProcessingAt)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle(detail == nil ? "Tạo Deal List" : "Chỉnh sửa")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Lưu") { Task { await save() } }.disabled(input.name.isEmpty || input.sourceSpreadsheetId.isEmpty || input.targetSpreadsheetId.isEmpty || !connectivity.isOnline) }
        }
    }
    private func sheetSection(_ title: String, id: Binding<String>, sheet: Binding<String>, sheets: [String], discover: @escaping () async -> Void) -> some View {
        Section(title) {
            TextField("Spreadsheet URL hoặc ID", text: id).textInputAutocapitalization(.never)
            Button("Tải danh sách worksheet") { Task { await discover() } }
            if !sheets.isEmpty { Picker("Worksheet", selection: sheet) { ForEach(sheets, id: \.self) { Text($0).tag($0) } } }
            else { TextField("Tên worksheet", text: sheet) }
        }
    }
    @ViewBuilder private func optionalDate(_ title: String, value: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? Date() : nil }))
        if value.wrappedValue != nil {
            DatePicker(title, selection: Binding(get: { value.wrappedValue ?? Date() }, set: { value.wrappedValue = $0 }))
        }
    }
    @MainActor private func discover(_ value: String, source: Bool) async {
        struct Body: Encodable { let spreadsheet: String }
        do {
            let result: SheetDiscoveryDTO = try await client.send("/api/mobile/v2/sheets/discover", method: "POST", body: Body(spreadsheet: value))
            if source { sourceSheets = result.sheets; input.sourceSpreadsheetId = result.spreadsheetId; if input.sourceSheetName.isEmpty { input.sourceSheetName = result.sheets.first ?? "" } }
            else { targetSheets = result.sheets; input.targetSpreadsheetId = result.spreadsheetId; if input.targetSheetName.isEmpty { input.targetSheetName = result.sheets.first ?? "" } }
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func save() async {
        input.sourceColumnMapping = Self.parseMapping(sourceMapping); input.targetColumnMapping = Self.parseMapping(targetMapping)
        do {
            if let detail {
                let _: DealListDTO = try await client.send("/api/mobile/v2/deal-lists/\(detail.id)", method: "PATCH", body: input, idempotencyKey: UUID().uuidString)
            } else {
                let _: DealListDTO = try await client.send("/api/mobile/v2/deal-lists", method: "POST", body: input, idempotencyKey: UUID().uuidString)
            }
            saved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private static func mappingText(_ value: [String: String]?) -> String { (value ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") }
    private static func parseMapping(_ text: String) -> [String: String]? {
        let pairs = text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init); return parts.count == 2 ? (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces)) : nil
        }; return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }
}
