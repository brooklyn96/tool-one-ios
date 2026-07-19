import SwiftUI

struct DealSyncBulkDestinationView: View {
    let client: DealSyncClient
    let completed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var rows = ""
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Thêm nhiều destination") {
                Text("Mỗi dòng: Tên | Spreadsheet ID hoặc URL | Sheet keyword | Shop IDs")
                    .font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $rows).frame(minHeight: 180).textInputAutocapitalization(.never)
            }
            if !progress.isEmpty { Section("Kết quả") { Text(progress).font(.footnote) } }
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Đang thêm…" : "Thêm destinations") { Task { await submit() } }
                .disabled(parsedRows.isEmpty || busy || !connectivity.isOnline)
        }
        .navigationTitle("Thêm hàng loạt")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
    }

    private var parsedRows: [[String]] {
        rows.split(whereSeparator: \.isNewline).map { $0.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }.filter { $0.count >= 2 && !$0[0].isEmpty && !$0[1].isEmpty }
    }

    @MainActor private func submit() async {
        struct Payload: Encodable { let name: String; let spreadsheetId: String; let sheetKeyword: String?; let skipBkAms: Bool; let shopIds: [String] }
        busy = true; defer { busy = false }
        var succeeded = 0; var failures: [String] = []
        for row in parsedRows {
            let shops = row.count > 3 ? row[3].split(whereSeparator: { ",; ".contains($0) }).map(String.init) : []
            let payload = Payload(name: row[0], spreadsheetId: row[1], sheetKeyword: row.count > 2 && !row[2].isEmpty ? row[2] : nil, skipBkAms: false, shopIds: shops)
            do { let _: DealSyncDestination = try await client.send(DealSyncEndpoint("/api/mobile/v2/destinations", method: "POST"), body: payload); succeeded += 1 }
            catch { failures.append("\(row[0]): \(error.localizedDescription)") }
            progress = "Đã thêm \(succeeded)/\(parsedRows.count)"
        }
        await completed()
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        if failures.isEmpty { dismiss() }
    }
}

struct DealSyncSheetRetryView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var operationID = ""
    @State private var scheduleID = ""
    @State private var spreadsheetID = ""
    @State private var destinationName = ""
    @State private var operation: DealSyncOperation?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Sheet bị lỗi") {
                TextField("Operation ID trước đó", text: $operationID).textInputAutocapitalization(.never)
                TextField("Schedule ID", text: $scheduleID).textInputAutocapitalization(.never)
                TextField("Spreadsheet ID", text: $spreadsheetID).textInputAutocapitalization(.never)
                TextField("Tên destination", text: $destinationName)
            }
            Button("Thử tạo lại sheet") { Task { await retry() } }
                .disabled([operationID, scheduleID, spreadsheetID, destinationName].contains(where: \.isEmpty) || !connectivity.isOnline)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Retry tạo sheet")
        .sheet(item: $operation) { item in NavigationStack { DealSyncOperationView(client: client, operation: item) } }
    }

    @MainActor private func retry() async {
        struct Payload: Encodable { let scheduleId: String; let spreadsheetId: String; let destinationName: String }
        do {
            operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/sheets/operations/\(operationID)/retry", method: "POST"), body: Payload(scheduleId: scheduleID, spreadsheetId: spreadsheetID, destinationName: destinationName))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct DealSyncDuplicateReviewView: View {
    let client: DealSyncClient
    let initialOperation: DealSyncOperation
    let scheduleID: String
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @EnvironmentObject private var ledger: DealSyncOperationLedger
    @State private var operation: DealSyncOperation
    @State private var result: DealSyncDuplicateScanResult?
    @State private var selected: Set<String> = []
    @State private var overrides: [String: String] = [:]
    @State private var execution: DealSyncOperation?
    @State private var error: String?

    init(client: DealSyncClient, operation: DealSyncOperation, scheduleID: String) {
        self.client = client; self.initialOperation = operation; self.scheduleID = scheduleID
        _operation = State(initialValue: operation)
    }

    var body: some View {
        List {
            if result == nil {
                Section("Đang quét") { ProgressView(value: Double(operation.progress), total: 100); LabeledContent("Trạng thái", value: operation.state) }
            }
            if let result {
                Section { Text(result.message ?? "Tìm thấy \(result.labels.reduce(0) { $0 + $1.matchedRows.count }) dòng cần duyệt.").font(.footnote) }
                ForEach(result.labels) { label in
                    Section(label.label) {
                        Picker("Biến thể +", selection: Binding(get: { overrides[label.id] ?? label.plusVariants.first ?? "" }, set: { overrides[label.id] = $0 })) {
                            ForEach(label.plusVariants, id: \.self) { Text($0).tag($0) }
                        }
                        ForEach(label.matchedRows) { row in
                            let key = "\(label.id)|\(row.sheetRowIndex)"
                            Button { toggle(key) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(row.title, systemImage: selected.contains(key) ? "checkmark.circle.fill" : "circle")
                                    Text("Dòng \(row.sheetRowIndex) · \(row.review ?? "Chưa review")").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section { Button("Thực thi \(selected.count) dòng đã chọn") { Task { await execute(result) } }.disabled(selected.isEmpty || !connectivity.isOnline) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Duyệt Deal trùng")
        .task { await poll() }
        .sheet(item: $execution) { item in NavigationStack { DealSyncOperationView(client: client, operation: item) } }
    }

    private func toggle(_ key: String) { if selected.contains(key) { selected.remove(key) } else { selected.insert(key) } }
    @MainActor private func poll() async {
        ledger.register(operation.id)
        while !operation.isTerminal {
            do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/operations/\(operation.id)")) }
            catch { self.error = error.localizedDescription; return }
            if !operation.isTerminal { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        ledger.complete(operation.id)
        guard operation.state == "SUCCEEDED", let value = operation.result else { error = operation.errorCode ?? "Quét Deal trùng thất bại."; return }
        do { result = try JSONDecoder.api.decode(DealSyncDuplicateScanResult.self, from: JSONEncoder.api.encode(value)) }
        catch { self.error = "Kết quả quét không đúng định dạng: \(error.localizedDescription)" }
    }
    @MainActor private func execute(_ result: DealSyncDuplicateScanResult) async {
        struct Payload: Encodable { let scheduleId: String; let dealListSheetName: String?; let selections: [DealSyncDuplicateSelection] }
        var values: [DealSyncDuplicateSelection] = []
        for label in result.labels { for row in label.matchedRows {
            let key = "\(label.id)|\(row.sheetRowIndex)"; guard selected.contains(key) else { continue }
            values.append(DealSyncDuplicateSelection(labelKey: label.label, brandCodeWithPlus: overrides[label.id] ?? label.plusVariants.first ?? label.baseBrandCode, rowIndex: row.rowIndex, sheetRowIndex: row.sheetRowIndex, reviewColIndex: result.colMap?.review, reviewOverride: nil))
        } }
        do { execution = try await client.send(DealSyncEndpoint("/api/mobile/v2/duplicates/operations", method: "POST"), body: Payload(scheduleId: scheduleID, dealListSheetName: result.dealListSheetName ?? result.sheetName, selections: values)); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct DealSyncUserPermissionsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var users: [DealSyncAdminUser] = []
    @State private var error: String?
    var body: some View {
        List { ForEach(users) { user in NavigationLink { DealSyncUserPermissionEditor(client: client, user: user) { await load() } } label: { VStack(alignment: .leading) { Text(user.title).font(.headline); Text(user.isBanned == true ? "Đã khóa" : "Đang hoạt động").font(.caption).foregroundStyle(user.isBanned == true ? Color.red : Color.secondary) } } }; if let error { Text(error).foregroundStyle(.red) } }
            .navigationTitle("Quyền người dùng").task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncAdminUser> = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/users")); users = page.items; error = nil } catch { self.error = error.localizedDescription } }
}

private struct DealSyncUserPermissionEditor: View {
    let client: DealSyncClient; let user: DealSyncAdminUser; let saved: () async -> Void
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var canSync: Bool; @State private var canSubmit: Bool; @State private var canCreate: Bool; @State private var banned: Bool; @State private var targetSheet: String; @State private var error: String?
    init(client: DealSyncClient, user: DealSyncAdminUser, saved: @escaping () async -> Void) { self.client = client; self.user = user; self.saved = saved; _canSync = State(initialValue: user.canSync ?? false); _canSubmit = State(initialValue: user.canSubmitDeal ?? false); _canCreate = State(initialValue: user.canCreateSheet ?? false); _banned = State(initialValue: user.isBanned ?? false); _targetSheet = State(initialValue: user.targetSheetName ?? "") }
    var body: some View { Form { Section(user.title) { Toggle("Sync", isOn: $canSync); Toggle("Submit Deal", isOn: $canSubmit); Toggle("Tạo Sheet", isOn: $canCreate); Toggle("Khóa tài khoản", isOn: $banned); TextField("Target sheet", text: $targetSheet) }; Button("Lưu quyền") { Task { await save() } }.disabled(!connectivity.isOnline); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Phân quyền") }
    @MainActor private func save() async { struct Payload: Encodable { let canSubmitDeal: Bool; let canCreateSheet: Bool; let canSync: Bool; let isBanned: Bool; let targetSheetName: String? }; do { let _: DealSyncAdminUser = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/users/\(user.id)", method: "PATCH"), body: Payload(canSubmitDeal: canSubmit, canCreateSheet: canCreate, canSync: canSync, isBanned: banned, targetSheetName: targetSheet.isEmpty ? nil : targetSheet)); await saved(); error = nil } catch { self.error = error.localizedDescription } }
}

struct DealSyncMaintenanceView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var enabled = false; @State private var message = ""; @State private var delay = 0; @State private var current: JSONValue?; @State private var error: String?
    var body: some View { Form { if let current { Section("Hiện tại") { JSONValueView(value: current) } }; Section("Cấu hình") { Toggle("Bật bảo trì", isOn: $enabled); TextField("Thông báo", text: $message, axis: .vertical); Stepper("Trì hoãn: \(delay) phút", value: $delay, in: 0...1440) }; Button("Áp dụng") { Task { await save() } }.disabled(!connectivity.isOnline); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Maintenance").task { await load() } }
    @MainActor private func load() async { do { current = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/maintenance")); error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func save() async { struct Payload: Encodable { let enabled: Bool; let message: String; let delayMinutes: Int }; do { current = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/maintenance", method: "PUT"), body: Payload(enabled: enabled, message: message, delayMinutes: delay)); error = nil } catch { self.error = error.localizedDescription } }
}

struct DealSyncQuotaSettingsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var projectQuota = ""; @State private var userQuota = ""; @State private var safetyBuffer = ""; @State private var current: JSONValue?; @State private var error: String?
    var body: some View { Form { if let current { Section("Cấu hình hiện tại") { JSONValueView(value: current) } }; Section("Quota") { TextField("Project quota", text: $projectQuota).keyboardType(.numberPad); TextField("User quota", text: $userQuota).keyboardType(.numberPad); TextField("Safety buffer", text: $safetyBuffer).keyboardType(.numberPad) }; Button("Lưu quota") { Task { await save() } }.disabled([projectQuota, userQuota, safetyBuffer].contains(where: \.isEmpty) || !connectivity.isOnline); if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Quota & Settings").task { await load() } }
    @MainActor private func load() async { do { current = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/settings")); error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func save() async { struct Payload: Encodable { let projectQuota: Int; let userQuota: Int; let safetyBuffer: Int }; guard let p = Int(projectQuota), let u = Int(userQuota), let s = Int(safetyBuffer) else { error = "Quota phải là số nguyên."; return }; do { current = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/settings", method: "PUT"), body: Payload(projectQuota: p, userQuota: u, safetyBuffer: s)); error = nil } catch { self.error = error.localizedDescription } }
}

struct DealSyncClusterToolsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var spreadsheetID = ""; @State private var sheetName = ""; @State private var clusters: JSONValue?; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View { Form { Section("Cluster mapping") { TextField("Spreadsheet ID", text: $spreadsheetID).textInputAutocapitalization(.never); TextField("Sheet name (tùy chọn)", text: $sheetName); Button("Làm mới mapping") { Task { await run("POST") } }; Button("Áp dụng mapping") { Task { await run("PUT") } }.disabled(spreadsheetID.isEmpty) }.disabled(!connectivity.isOnline); if let clusters { Section("Danh sách") { JSONValueView(value: clusters) } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Clusters").task { await load() }.sheet(item: $operation) { item in NavigationStack { DealSyncOperationView(client: client, operation: item) } } }
    @MainActor private func load() async { do { clusters = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/clusters")); error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func run(_ method: String) async { struct Payload: Encodable { let spreadsheetId: String?; let sheetName: String? }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/clusters", method: method), body: Payload(spreadsheetId: spreadsheetID.isEmpty ? nil : spreadsheetID, sheetName: sheetName.isEmpty ? nil : sheetName)); error = nil } catch { self.error = error.localizedDescription } }
}

struct DealSyncThemeSettingsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var themes: [DealSyncTheme] = []; @State private var error: String?
    var body: some View { List { ForEach(themes) { theme in Toggle(theme.title, isOn: Binding(get: { theme.enabled }, set: { enabled in Task { await update(theme, enabled) } })).disabled(!connectivity.isOnline) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Themes").task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncTheme> = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/themes")); themes = page.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func update(_ theme: DealSyncTheme, _ enabled: Bool) async { struct Payload: Encodable { let id: String; let enabled: Bool }; do { let _: DealSyncTheme = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/themes", method: "PUT"), body: Payload(id: theme.id, enabled: enabled)); await load() } catch { self.error = error.localizedDescription } }
}

struct DealSyncScheduleAdminView: View {
    let client: DealSyncClient
    @State private var schedules: [DealSyncSchedule] = []; @State private var showCreate = false; @State private var error: String?
    var body: some View {
        List { ForEach(schedules) { item in NavigationLink { DealSyncScheduleEditor(client: client, schedule: item) { await load() } } label: { VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.spreadsheetId ?? "Chưa có Deal List").font(.caption).foregroundStyle(.secondary) } } }; if let error { Text(error).foregroundStyle(.red) } }
            .navigationTitle("Lịch livestream").toolbar { Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm lịch") }
            .task { await load() }.refreshable { await load() }.sheet(isPresented: $showCreate) { NavigationStack { DealSyncScheduleEditor(client: client, schedule: nil) { await load(); showCreate = false } } }
    }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncSchedule> = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/schedules")); schedules = page.items; error = nil } catch { self.error = error.localizedDescription } }
}

private struct DealSyncScheduleEditor: View {
    let client: DealSyncClient; let schedule: DealSyncSchedule?; let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var date = Date(); @State private var kolName = ""; @State private var spreadsheetID = ""; @State private var poolID = ""; @State private var externalID = ""; @State private var liveItemID = ""; @State private var brandPoolURL = ""; @State private var bdColumn = ""; @State private var error: String?; @State private var confirmDelete = false
    var body: some View { Form { DatePicker("Ngày", selection: $date, displayedComponents: .date); TextField("Tên KOL", text: $kolName); TextField("Deal List Spreadsheet ID", text: $spreadsheetID); TextField("Pool Spreadsheet ID", text: $poolID); TextField("External Spreadsheet ID", text: $externalID); TextField("Live Item Spreadsheet ID", text: $liveItemID); TextField("Brand Pool URL", text: $brandPoolURL); TextField("BD check column", text: $bdColumn); Button("Lưu lịch") { Task { await save() } }.disabled(kolName.isEmpty || !connectivity.isOnline); if schedule != nil { Button("Xóa lịch", role: .destructive) { confirmDelete = true }.disabled(!connectivity.isOnline) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle(schedule == nil ? "Thêm lịch" : "Sửa lịch").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }.onAppear { hydrate() }.alert("Xóa lịch livestream?", isPresented: $confirmDelete) { Button("Hủy", role: .cancel) {}; Button("Xóa", role: .destructive) { Task { await remove() } } } }
    private struct Payload: Encodable { let date: String; let spreadsheetId: String; let poolSpreadsheetId: String?; let brandPoolSheetUrl: String?; let externalSpreadsheetId: String?; let liveItemIdSpreadsheetId: String?; let kolName: String; let bdCheckColumn: String? }
    private var payload: Payload { let formatter = ISO8601DateFormatter(); return Payload(date: formatter.string(from: date), spreadsheetId: spreadsheetID, poolSpreadsheetId: poolID.nilIfEmpty, brandPoolSheetUrl: brandPoolURL.nilIfEmpty, externalSpreadsheetId: externalID.nilIfEmpty, liveItemIdSpreadsheetId: liveItemID.nilIfEmpty, kolName: kolName, bdCheckColumn: bdColumn.nilIfEmpty) }
    private func hydrate() { guard let item = schedule else { return }; kolName = item.kolName ?? ""; spreadsheetID = item.spreadsheetId ?? ""; poolID = item.poolSpreadsheetId ?? ""; externalID = item.externalSpreadsheetId ?? ""; liveItemID = item.liveItemIdSpreadsheetId ?? ""; brandPoolURL = item.brandPoolSheetUrl ?? ""; bdColumn = item.bdCheckColumn ?? ""; if let raw = item.date { date = ISO8601DateFormatter().date(from: raw) ?? date } }
    @MainActor private func save() async { do { if let item = schedule { let _: DealSyncSchedule = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/schedules/\(item.id)", method: "PATCH"), body: payload) } else { let _: DealSyncSchedule = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/schedules", method: "POST"), body: payload) }; await saved(); dismiss() } catch { self.error = error.localizedDescription } }
    @MainActor private func remove() async { guard let item = schedule else { return }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/schedules/\(item.id)", method: "DELETE"), body: DealSyncEmptyBody()); await saved(); dismiss() } catch { self.error = error.localizedDescription } }
}

struct DealSyncArchiveAdminView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var items: [DealSyncSchedule] = []; @State private var date = Date(); @State private var kol = ""; @State private var spreadsheetID = ""; @State private var poolID = ""; @State private var error: String?
    var body: some View { List { Section("Import archive") { DatePicker("Ngày", selection: $date, displayedComponents: .date); TextField("KOL", text: $kol); TextField("Spreadsheet ID", text: $spreadsheetID); TextField("Pool Spreadsheet ID", text: $poolID); Button("Import") { Task { await create() } }.disabled([kol, spreadsheetID, poolID].contains(where: \.isEmpty) || !connectivity.isOnline) }; Section("Đã lưu trữ") { ForEach(items) { item in HStack { VStack(alignment: .leading) { Text(item.title); Text(item.spreadsheetId ?? "—").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { Task { await remove(item.id) } } label: { Image(systemName: "trash") }.disabled(!connectivity.isOnline) } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Lưu trữ lịch").task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncSchedule> = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedule-archives")); items = page.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func create() async { struct Payload: Encodable { let date: String; let kolName: String; let spreadsheetId: String; let poolSpreadsheetId: String }; do { let _: DealSyncSchedule = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedule-archives", method: "POST"), body: Payload(date: ISO8601DateFormatter().string(from: date), kolName: kol, spreadsheetId: spreadsheetID, poolSpreadsheetId: poolID)); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func remove(_ id: String) async { do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedule-archives/\(id)", method: "DELETE"), body: DealSyncEmptyBody()); await load() } catch { self.error = error.localizedDescription } }
}

struct DealSyncProjectAdminView: View {
    let client: DealSyncClient
    @State private var projects: [DealSyncAdminProject] = []; @State private var showCreate = false; @State private var error: String?
    var body: some View { List { ForEach(projects) { item in NavigationLink { DealSyncProjectEditor(client: client, project: item) { await load() } } label: { VStack(alignment: .leading) { HStack { Text(item.name).font(.headline); if !item.isActive { Text("Tắt").font(.caption).foregroundStyle(.red) } }; Text("\(item.code) · Priority \(item.priority)").font(.caption).foregroundStyle(.secondary) } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("GCP Projects").toolbar { Button { showCreate = true } label: { Image(systemName: "plus") } }.task { await load() }.refreshable { await load() }.sheet(isPresented: $showCreate) { NavigationStack { DealSyncProjectEditor(client: client, project: nil) { await load(); showCreate = false } } } }
    @MainActor private func load() async { do { let value: DealSyncAdminProjects = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/projects")); projects = value.projects; error = nil } catch { self.error = error.localizedDescription } }
}

private struct DealSyncProjectEditor: View {
    let client: DealSyncClient; let project: DealSyncAdminProject?; let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss; @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var code = ""; @State private var name = ""; @State private var clientID = ""; @State private var clientSecret = ""; @State private var priority = 0; @State private var active = true; @State private var error: String?; @State private var confirmDelete = false
    var body: some View { Form { TextField("Project code", text: $code).disabled(project != nil); TextField("Tên", text: $name); if project == nil { TextField("Google Client ID", text: $clientID).textInputAutocapitalization(.never); SecureField("Google Client Secret", text: $clientSecret) }; Stepper("Priority: \(priority)", value: $priority, in: -100...100); Toggle("Đang hoạt động", isOn: $active); Button("Lưu project") { Task { await save() } }.disabled(name.isEmpty || !connectivity.isOnline || (project == nil && [code, clientID, clientSecret].contains(where: \.isEmpty))); if project != nil { Button("Xóa hoặc vô hiệu hóa", role: .destructive) { confirmDelete = true }.disabled(!connectivity.isOnline) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle(project == nil ? "Thêm Project" : "Sửa Project").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }.onAppear { if let p = project { code = p.code; name = p.name; priority = p.priority; active = p.isActive } }.alert("Xóa project?", isPresented: $confirmDelete) { Button("Hủy", role: .cancel) {}; Button("Xóa", role: .destructive) { Task { await remove() } } } }
    @MainActor private func save() async { do { if let p = project { struct Update: Encodable { let name: String; let isActive: Bool; let priority: Int }; let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/projects/\(p.id)", method: "PATCH"), body: Update(name: name, isActive: active, priority: priority)) } else { struct Create: Encodable { let code: String; let name: String; let clientId: String; let clientSecret: String; let priority: Int }; let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/projects", method: "POST"), body: Create(code: code, name: name, clientId: clientID, clientSecret: clientSecret, priority: priority)) }; await saved(); dismiss() } catch { self.error = error.localizedDescription } }
    @MainActor private func remove() async { guard let p = project else { return }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/projects/\(p.id)", method: "DELETE"), body: DealSyncEmptyBody()); await saved(); dismiss() } catch { self.error = error.localizedDescription } }
}

struct DealSyncAdminSubmissionsView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var items: [DealSyncSubmission] = []; @State private var error: String?
    var body: some View { List { ForEach(items) { item in VStack(alignment: .leading, spacing: 6) { Text(item.sheetName ?? item.id).font(.headline); Text([item.userEmail, item.scheduleKol].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary); Button("Xóa submission", role: .destructive) { Task { await remove(item.id) } }.disabled(!connectivity.isOnline) } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Submissions").task { await load() }.refreshable { await load() } }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncSubmission> = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/submissions")); items = page.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func remove(_ id: String) async { struct Payload: Encodable { let submissionId: String }; do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/admin/submissions", method: "DELETE"), body: Payload(submissionId: id)); await load() } catch { self.error = error.localizedDescription } }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
