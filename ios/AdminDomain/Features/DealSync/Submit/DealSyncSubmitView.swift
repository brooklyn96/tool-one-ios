import SwiftUI

private struct SubmitExecutionBody: Encodable {
    let scheduleId: String
    let mode: String
    let confirmedWarningIds: [String]
    let specificSubmissionIds: [String]
    let resumeSessionId: String?
}

struct DealSyncSubmitView: View {
    let client: DealSyncClient
    let account: DealSyncAccount
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var schedules: [DealSyncSchedule] = []
    @State private var submissions: [DealSyncSubmission] = []
    @State private var scheduleID = ""
    @State private var mode = "new"
    @State private var selected: Set<String> = []
    @State private var includeIgnored = true
    @State private var operation: DealSyncOperation?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var showExecute = false

    var body: some View {
        Form {
            Section("Mục tiêu") {
                Picker("Lịch", selection: $scheduleID) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title.isEmpty ? $0.id : $0.title).tag($0.id) } }
                    .onChange(of: scheduleID) { _ in Task { await loadSubmissions() } }
                Picker("Cách submit", selection: $mode) {
                    Text("Tạo mới").tag("new"); Text("Cập nhật mới").tag("update_new"); Text("Cập nhật cũ").tag("update_old")
                }
                Toggle("Hiện mục đã bỏ qua", isOn: $includeIgnored).onChange(of: includeIgnored) { _ in Task { await loadSubmissions() } }
            }
            Section {
                HStack { Button("Chọn tất cả") { selected = Set(submissions.map(\.id)) }; Spacer(); Button("Bỏ chọn") { selected.removeAll() } }.font(.footnote)
                if loading { ProgressView("Đang tải submissions…") }
                ForEach(submissions) { item in
                    HStack(alignment: .top) {
                        Button { toggle(item.id) } label: { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.sheetName ?? item.spreadsheetId ?? item.id).font(.headline)
                            HStack {
                                if item.isIgnored == true { Label("Đã bỏ qua", systemImage: "eye.slash") }
                                if item.isSkipped == true { Label("Đã skip", systemImage: "forward.end") }
                            }.font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(item.isIgnored == true ? "Khôi phục" : "Bỏ qua") { Task { await setIgnored(item, !(item.isIgnored ?? false)) } }
                                Button(item.isSkipped == true ? "Bỏ skip" : "Skip") { Task { await setSkipped(item, !(item.isSkipped ?? false)) } }
                            }.font(.caption)
                        }
                    }
                }
            } header: { Text("Submissions · \(selected.count) đã chọn") }
            Section("Thao tác") {
                Button("Validate lựa chọn") { Task { await start(path: "/api/mobile/v2/submit/validate") } }
                Button("Submit Deal") { showExecute = true }.buttonStyle(.borderedProminent)
                Button("Quét submissions còn thiếu") { Task { await scanMissing() } }
                Menu("Bảo vệ output sheets") {
                    Button("Khóa sheets") { Task { await protect(true) } }
                    Button("Mở khóa sheets") { Task { await protect(false) } }
                }
            }.disabled(scheduleID.isEmpty || working || !connectivity.isOnline || !account.capabilities.canSubmitDeal)
            Section("Công cụ nâng cao") {
                NavigationLink("Phiên bị gián đoạn") { DealSyncRecoveryView(client: client) }
                NavigationLink("Tier 2") { DealSyncTier2SubmitView(client: client, account: account) }
                if account.isAdmin { NavigationLink("Merge Pool") { DealSyncMergePoolView(client: client, schedules: schedules) } }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Submit Deal")
        .task { await load() }
        .refreshable { await load() }
        .alert("Xác nhận Submit Deal?", isPresented: $showExecute) {
            Button("Hủy", role: .cancel) {}; Button("Thực hiện") { Task { await start(path: "/api/mobile/v2/submit/operations") } }
        } message: { Text(selected.isEmpty ? "Hệ thống sẽ xử lý toàn bộ submission hợp lệ." : "Hệ thống sẽ xử lý \(selected.count) submission đã chọn.") }
        .sheet(item: $operation) { operation in NavigationStack { DealSyncOperationView(client: client, operation: operation).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { self.operation = nil } } } } }
    }

    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
    @MainActor private func load() async {
        loading = true; defer { loading = false }
        do {
            let page: DealSyncCollection<DealSyncSchedule> = try await client.send(DealSyncEndpoint("/api/mobile/v2/schedules"))
            schedules = page.items; if scheduleID.isEmpty { scheduleID = schedules.first?.id ?? "" }
            await loadSubmissions(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func loadSubmissions() async {
        guard !scheduleID.isEmpty else { submissions = []; return }
        let encoded = scheduleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scheduleID
        do {
            let page: DealSyncCollection<DealSyncSubmission> = try await client.send(DealSyncEndpoint("/api/mobile/v2/submissions?scheduleId=\(encoded)&includeIgnored=\(includeIgnored)"))
            submissions = page.items; selected.formIntersection(Set(page.items.map(\.id))); error = nil
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func start(path: String) async {
        working = true; defer { working = false }
        let body = SubmitExecutionBody(scheduleId: scheduleID, mode: mode, confirmedWarningIds: [], specificSubmissionIds: Array(selected), resumeSessionId: nil)
        do { operation = try await client.send(DealSyncEndpoint(path, method: "POST"), body: body); error = nil }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func scanMissing() async {
        working = true; defer { working = false }
        struct Body: Encodable { let scheduleId: String }
        do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/submissions/missing", method: "POST"), body: Body(scheduleId: scheduleID)) }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func protect(_ locked: Bool) async {
        working = true; defer { working = false }
        struct Body: Encodable { let scheduleId: String; let locked: Bool }
        do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/submit/protection", method: "PUT"), body: Body(scheduleId: scheduleID, locked: locked)) }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func setIgnored(_ item: DealSyncSubmission, _ value: Bool) async {
        struct Body: Encodable { let isIgnored: Bool }
        do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/submissions/\(item.id)", method: "PATCH"), body: Body(isIgnored: value)); await loadSubmissions() }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func setSkipped(_ item: DealSyncSubmission, _ value: Bool) async {
        struct Body: Encodable { let isSkipped: Bool }
        do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/submissions/\(item.id)/skip", method: "PATCH"), body: Body(isSkipped: value)); await loadSubmissions() }
        catch { self.error = error.localizedDescription }
    }
}

private struct DealSyncRecoveryView: View {
    let client: DealSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var recovery: DealSyncProcessRecovery?
    @State private var error: String?
    var body: some View {
        List {
            if recovery?.sessions.isEmpty != false { Text("Không có phiên bị gián đoạn").foregroundStyle(.secondary) }
            ForEach(recovery?.sessions ?? []) { session in
                Section(session.scheduleId ?? session.id) {
                    LabeledContent("Trạng thái", value: session.status)
                    if let progress = session.rowProgress { ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))) }
                    HStack {
                        Button("Tiếp tục") { Task { await action(session.id, method: "PATCH") } }.disabled(!connectivity.isOnline)
                        Button("Bỏ phiên", role: .destructive) { Task { await action(session.id, method: "DELETE") } }.disabled(!connectivity.isOnline)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Khôi phục phiên").task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async { do { recovery = try await client.send(DealSyncEndpoint("/api/mobile/v2/process-sessions")); error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func action(_ id: String, method: String) async { do { let _: JSONValue = try await client.send(DealSyncEndpoint("/api/mobile/v2/process-sessions/\(id)", method: method), body: DealSyncEmptyBody()); await load() } catch { self.error = error.localizedDescription } }
}

private struct DealSyncTier2SubmitView: View {
    let client: DealSyncClient; let account: DealSyncAccount
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var sessions: [DealSyncTier2Session] = []; @State private var selected = ""; @State private var mode = "new"; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View {
        Form {
            Picker("Phiên Tier 2", selection: $selected) { Text("Chọn phiên").tag(""); ForEach(sessions) { Text($0.label ?? "\($0.month)/\($0.year)").tag($0.id) } }
            Picker("Cách xử lý", selection: $mode) { Text("Tạo mới").tag("new"); Text("Cập nhật").tag("update") }
            Button("Thực hiện Tier 2") { Task { await execute() } }.disabled(selected.isEmpty || !connectivity.isOnline || !account.capabilities.canSubmitDeal)
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Tier 2").task { await load() }.sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } }
    }
    @MainActor private func load() async { do { let page: DealSyncCollection<DealSyncTier2Session> = try await client.send(DealSyncEndpoint("/api/mobile/v2/tier2/sessions")); sessions = page.items } catch { self.error = error.localizedDescription } }
    @MainActor private func execute() async { struct Body: Encodable { let sessionId: String; let mode: String; let resumeSessionId: String? }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/tier2/execute/operations", method: "POST"), body: Body(sessionId: selected, mode: mode, resumeSessionId: nil)) } catch { self.error = error.localizedDescription } }
}

private struct DealSyncMergePoolView: View {
    let client: DealSyncClient; let schedules: [DealSyncSchedule]
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var scheduleID = ""; @State private var sheetNames = ""; @State private var operation: DealSyncOperation?; @State private var error: String?
    var body: some View {
        Form {
            Picker("Lịch", selection: $scheduleID) { Text("Chọn lịch").tag(""); ForEach(schedules) { Text($0.title).tag($0.id) } }
            TextField("Tên sheets, phân cách dấu phẩy", text: $sheetNames, axis: .vertical)
            Button("Merge Pool") { Task { await execute() } }.disabled(scheduleID.isEmpty || sheetNames.isEmpty || !connectivity.isOnline)
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Merge Pool").sheet(item: $operation) { op in NavigationStack { DealSyncOperationView(client: client, operation: op) } }
    }
    @MainActor private func execute() async { struct Body: Encodable { let scheduleId: String; let sheetNames: [String] }; let names = sheetNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; do { operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/merge/operations", method: "POST"), body: Body(scheduleId: scheduleID, sheetNames: names)) } catch { self.error = error.localizedDescription } }
}
