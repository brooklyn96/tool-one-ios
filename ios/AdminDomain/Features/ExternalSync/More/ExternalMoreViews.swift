import SwiftUI

struct ExternalLogsView: View {
    let client: ExternalSyncClient; let isAdmin: Bool; let cache: SnapshotCache?; let cacheNamespace: String
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var items: [ProcessLogDTO] = []; @State private var status = ""; @State private var cursor: String?
    @State private var dealListID = ""; @State private var actor = ""; @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(); @State private var to = Date()
    @State private var error: String?; @State private var showClear = false
    @State private var isStale = false
    var body: some View {
        List {
            if isStale { Label("Đang hiển thị dữ liệu đã lưu", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
            Section {
                Picker("Trạng thái", selection: $status) { Text("Tất cả").tag(""); Text("INFO").tag("INFO"); Text("success").tag("success"); Text("error").tag("error") }
                TextField("Deal List ID (tùy chọn)", text: $dealListID).textInputAutocapitalization(.never)
                TextField("Người thao tác / nội dung", text: $actor)
                Toggle("Lọc theo thời gian", isOn: $useDates)
                if useDates { DatePicker("Từ", selection: $from); DatePicker("Đến", selection: $to) }
                Button("Áp dụng bộ lọc") { Task { await load(true) } }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { log in NavigationLink { ExternalLogDetailView(client: client, summary: log) } label: {
                VStack(alignment: .leading) { HStack { Text(log.action).font(.headline); Spacer(); Text(log.status).font(.caption).foregroundStyle(log.status.lowercased().contains("error") ? .red : .secondary) }; Text(log.message).lineLimit(2); Text(log.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary) }
            } }
            if cursor != nil { Button("Tải thêm") { Task { await load(false) } } }
        }.navigationTitle("Nhật ký").refreshable { await load(true) }.task { await load(true) }
        .toolbar { if isAdmin { ToolbarItem(placement: .primaryAction) { Button("Dọn log") { showClear = true }.disabled(!connectivity.isOnline) } } }
        .sheet(isPresented: $showClear) { ClearLogsView(client: client) { Task { await load(true) } } }
    }
    @MainActor private func load(_ reset: Bool) async {
        var components = URLComponents(); components.path = "/api/mobile/v2/logs"
        var query = [URLQueryItem(name: "limit", value: "30")]
        if !status.isEmpty { query.append(URLQueryItem(name: "status", value: status)) }
        if !dealListID.isEmpty { query.append(URLQueryItem(name: "dealListId", value: dealListID)) }
        if !actor.isEmpty { query.append(URLQueryItem(name: "actor", value: actor)) }
        if useDates { query.append(URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from))); query.append(URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: to))) }
        if !reset, let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = query
        let path = components.string ?? "/api/mobile/v2/logs"
        do {
            let page: ExternalPage<ProcessLogDTO> = try await client.send(path); items = reset ? page.items : items + page.items; cursor = page.nextCursor; error = nil; isStale = false
            if reset { try? await cache?.save(items, key: "external-\(cacheNamespace)-logs") }
        } catch {
            if reset, let cached = try? await cache?.load([ProcessLogDTO].self, key: "external-\(cacheNamespace)-logs") { items = cached; cursor = nil; isStale = true; self.error = nil }
            else { self.error = error.localizedDescription }
        }
    }
}
private struct ExternalLogDetailView: View {
    let client: ExternalSyncClient; let summary: ProcessLogDTO
    @State private var detail: LogDetailDTO?; @State private var error: String?
    var body: some View {
        let logStatus = detail?.status ?? summary.status; let action = detail?.action ?? summary.action
        let started = detail?.startedAt ?? summary.startedAt; let completed = detail?.completedAt ?? summary.completedAt
        let message = detail?.message ?? summary.message; let errorMessage = detail?.errorMessage ?? summary.errorMessage
        return List {
            Section("Kết quả") { LabeledContent("Trạng thái", value: logStatus); LabeledContent("Hành động", value: action); LabeledContent("Bắt đầu", value: started.formatted()); if let completed { LabeledContent("Hoàn tất", value: completed.formatted()) } }
            Section("Thông điệp") { Text(message); if let errorMessage { Text(errorMessage).foregroundStyle(.red) } }
            Section("Số liệu") { LabeledContent("Đã xử lý", value: "\(detail?.processedRecords ?? summary.processedRecords ?? 0)"); LabeledContent("Đã cập nhật", value: "\(detail?.updatedRecords ?? summary.updatedRecords ?? 0)") }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Chi tiết log").task { await load() }
    }
    @MainActor private func load() async { do { detail = try await client.send("/api/mobile/v2/logs/\(summary.id)") } catch { self.error = error.localizedDescription } }
}
private struct ClearLogsView: View {
    let client: ExternalSyncClient; let completed: () -> Void
    @Environment(\.dismiss) var dismiss; @State private var days = 30; @State private var preview: ClearLogsDTO?; @State private var error: String?
    var body: some View { NavigationStack { Form { Stepper("Cũ hơn \(days) ngày", value: $days, in: 1...3650); if let preview { Text("Sẽ xóa \(preview.count ?? 0) bản ghi"); Button("Xác nhận xóa", role: .destructive) { Task { await submit(true) } } } else { Button("Xem trước") { Task { await submit(false) } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Dọn nhật ký").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } } } }
    @MainActor private func submit(_ confirm: Bool) async { struct Body: Encodable { let olderThanDays: Int; let confirm: Bool }; do { let result: ClearLogsDTO = try await client.send("/api/mobile/v2/logs/clear", method: "POST", body: Body(olderThanDays: days, confirm: confirm), idempotencyKey: UUID().uuidString); if confirm { completed(); dismiss() } else { preview = result } } catch { self.error = error.localizedDescription } }
}

struct ExternalMoreView: View {
    @ObservedObject var auth: ExternalSyncAuthStore; let user: ExternalUser
    var body: some View {
        List {
            Section("Cấu hình") { NavigationLink { ExternalConditionsView(client: auth.client) } label: { Label("Điều kiện xử lý", systemImage: "slider.horizontal.3") } }
            if user.isAdmin { Section("Quản trị External Sync") { NavigationLink { ExternalUsersView(client: auth.client, currentUserID: user.id) } label: { Label("Người dùng", systemImage: "person.2") }; NavigationLink { ExternalSystemView(client: auth.client) } label: { Label("Hệ thống", systemImage: "gauge.with.dots.needle.50percent") } } }
            Section("Tài khoản") { LabeledContent("Tên đăng nhập", value: user.username); LabeledContent("Vai trò", value: user.isAdmin ? "Quản trị viên" : "Người dùng"); NavigationLink("Đổi mật khẩu") { ChangeExternalPasswordView(auth: auth) }; Button("Đăng xuất", role: .destructive) { Task { await auth.logout() } } }
        }.navigationTitle("Thêm")
    }
}

private struct ExternalConditionsView: View {
    let client: ExternalSyncClient
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var data: ConditionsDTO?; @State private var error: String?; @State private var editing: ConditionDTO?; @State private var creating = false
    @State private var pendingDelete: ConditionDTO?; @State private var resetPreview: ResetPreviewDTO?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(data?.items ?? []) { item in
                VStack(alignment: .leading) { HStack { Text(item.name).font(.headline); Spacer(); Toggle("", isOn: Binding(get: { item.isActive }, set: { value in Task { await toggle(item, value) } })).labelsHidden() }; Text(item.columnGroups.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary); if let description = item.description { Text(description).font(.subheadline) }; Button("Chỉnh sửa") { editing = item } }
            }.onDelete { indexes in pendingDelete = indexes.first.map { (data?.items ?? [])[$0] } }
            Section { Button("Khôi phục 16 điều kiện mặc định", role: .destructive) { Task { await previewReset() } }.disabled(!connectivity.isOnline) }
        }.navigationTitle("Điều kiện").toolbar { ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Image(systemName: "plus") }.disabled(!connectivity.isOnline) } }.task { await load() }.refreshable { await load() }
        .sheet(isPresented: $creating) { ConditionEditor(client: client, options: data?.columnGroupOptions ?? [], condition: nil) { Task { await load() } } }
        .sheet(item: $editing) { ConditionEditor(client: client, options: data?.columnGroupOptions ?? [], condition: $0) { Task { await load() } } }
        .confirmationDialog("Xóa điều kiện “\(pendingDelete?.name ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            if let item = pendingDelete { Button("Xóa", role: .destructive) { pendingDelete = nil; Task { await delete(item) } } }
        }
        .alert("Khôi phục điều kiện mặc định?", isPresented: Binding(get: { resetPreview != nil }, set: { if !$0 { resetPreview = nil } })) {
            Button("Hủy", role: .cancel) { resetPreview = nil }
            Button("Khôi phục", role: .destructive) { resetPreview = nil; Task { await reset() } }
        } message: { Text("Sẽ thay thế \(resetPreview?.existingCount ?? 0) điều kiện hiện tại bằng \(resetPreview?.defaultCount ?? 16) điều kiện mặc định.") }
    }
    @MainActor private func load() async { do { data = try await client.send("/api/mobile/v2/conditions"); error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func toggle(_ item: ConditionDTO, _ value: Bool) async { do { let _: ConditionDTO = try await client.send("/api/mobile/v2/conditions/\(item.id)", method: "PATCH", body: ConditionUpdateDTO(name: nil, columnGroups: nil, description: nil, isActive: value), idempotencyKey: UUID().uuidString); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func delete(_ item: ConditionDTO) async { do { let _: DeleteResult = try await client.send("/api/mobile/v2/conditions/\(item.id)", method: "DELETE", body: EmptyMutation(), idempotencyKey: UUID().uuidString); await load() } catch { self.error = error.localizedDescription } }
    @MainActor private func previewReset() async { struct Body: Encodable { let confirm: Bool }; do { resetPreview = try await client.send("/api/mobile/v2/conditions/reset", method: "POST", body: Body(confirm: false), idempotencyKey: UUID().uuidString) } catch { self.error = error.localizedDescription } }
    @MainActor private func reset() async { struct Body: Encodable { let confirm: Bool }; do { let _: ConditionsDTO = try await client.send("/api/mobile/v2/conditions/reset", method: "POST", body: Body(confirm: true), idempotencyKey: UUID().uuidString); await load() } catch { self.error = error.localizedDescription } }
}
private struct ConditionEditor: View {
    let client: ExternalSyncClient; let options: [String]; let condition: ConditionDTO?; let saved: () -> Void
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) var dismiss; @State var name = ""; @State var description = ""; @State var selected: Set<String> = []; @State var error: String?
    init(client: ExternalSyncClient, options: [String], condition: ConditionDTO?, saved: @escaping () -> Void) { self.client = client; self.options = options; self.condition = condition; self.saved = saved; _name = State(initialValue: condition?.name ?? ""); _description = State(initialValue: condition?.description ?? ""); _selected = State(initialValue: Set(condition?.columnGroups ?? [])) }
    var body: some View { NavigationStack { Form { TextField("Tên", text: $name); TextField("Mô tả", text: $description); Section("Nhóm cột") { ForEach(options, id: \.self) { option in Button { if selected.contains(option) { selected.remove(option) } else { selected.insert(option) } } label: { Label(option, systemImage: selected.contains(option) ? "checkmark.circle.fill" : "circle") } } }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle(condition == nil ? "Tạo điều kiện" : "Sửa điều kiện").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Lưu") { Task { await save() } }.disabled(name.isEmpty || selected.isEmpty || !connectivity.isOnline) } } } }
    @MainActor private func save() async { do { if let condition { let _: ConditionDTO = try await client.send("/api/mobile/v2/conditions/\(condition.id)", method: "PATCH", body: ConditionUpdateDTO(name: name, columnGroups: Array(selected), description: description, isActive: nil), idempotencyKey: UUID().uuidString) } else { let _: ConditionDTO = try await client.send("/api/mobile/v2/conditions", method: "POST", body: ConditionInputDTO(name: name, columnGroups: Array(selected), description: description), idempotencyKey: UUID().uuidString) }; saved(); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct ExternalUsersView: View {
    let client: ExternalSyncClient; let currentUserID: String
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var users: [AdminUserDTO] = []; @State private var search = ""; @State private var error: String?
    @State private var editing: AdminUserDTO?; @State private var creating = false
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(users) { user in
                Button { editing = user } label: {
                    VStack(alignment: .leading) { HStack { Text(user.username).font(.headline); Spacer(); Text(user.isAdmin ? "Admin" : "User").font(.caption) }; Text(user.isActive ? "Đang hoạt động" : "Đã khóa").foregroundStyle(user.isActive ? .green : .red); if let email = user.email { Text(email).font(.caption).foregroundStyle(.secondary) } }
                }.buttonStyle(.plain)
                .swipeActions {
                    if user.id != currentUserID {
                        Button(role: .destructive) { Task { await delete(user) } } label: { Label("Xóa", systemImage: "trash") }.disabled(!connectivity.isOnline)
                    }
                }
            }
        }.navigationTitle("Người dùng").searchable(text: $search).onSubmit(of: .search) { Task { await load() } }.task { await load() }.refreshable { await load() }
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Image(systemName: "person.badge.plus") }.disabled(!connectivity.isOnline) } }
        .sheet(isPresented: $creating) { UserEditor(client: client, user: nil) { Task { await load() } } }
        .sheet(item: $editing) { UserEditor(client: client, user: $0) { Task { await load() } } }
    }
    @MainActor private func load() async { do { let page: ExternalPage<AdminUserDTO> = try await client.send("/api/mobile/v2/users?search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"); users = page.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func delete(_ user: AdminUserDTO) async { do { let _: DeleteResult = try await client.send("/api/mobile/v2/users/\(user.id)", method: "DELETE", body: EmptyMutation(), idempotencyKey: UUID().uuidString); await load() } catch { self.error = error.localizedDescription } }
}

private struct UserEditor: View {
    let client: ExternalSyncClient; let user: AdminUserDTO?; let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @State private var username: String; @State private var email: String; @State private var password = ""
    @State private var isAdmin: Bool; @State private var isActive: Bool; @State private var error: String?
    init(client: ExternalSyncClient, user: AdminUserDTO?, saved: @escaping () -> Void) {
        self.client = client; self.user = user; self.saved = saved
        _username = State(initialValue: user?.username ?? ""); _email = State(initialValue: user?.email ?? "")
        _isAdmin = State(initialValue: user?.isAdmin ?? false); _isActive = State(initialValue: user?.isActive ?? true)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên đăng nhập", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    SecureField(user == nil ? "Mật khẩu" : "Mật khẩu mới (để trống nếu không đổi)", text: $password)
                }
                Section("Quyền") { Toggle("Quản trị viên", isOn: $isAdmin); if user != nil { Toggle("Đang hoạt động", isOn: $isActive) } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(user == nil ? "Tạo người dùng" : "Sửa người dùng")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { Task { await save() } }.disabled(username.isEmpty || (user == nil && password.count < 6) || !connectivity.isOnline) }
            }
        }
    }
    @MainActor private func save() async {
        do {
            if let user {
                let _: AdminUserDTO = try await client.send("/api/mobile/v2/users/\(user.id)", method: "PATCH", body: UserUpdateDTO(username: username, email: email.isEmpty ? nil : email, password: password.isEmpty ? nil : password, isAdmin: isAdmin, isActive: isActive), idempotencyKey: UUID().uuidString)
            } else {
                let _: AdminUserDTO = try await client.send("/api/mobile/v2/users", method: "POST", body: UserInputDTO(username: username, password: password, email: email.isEmpty ? nil : email, isAdmin: isAdmin), idempotencyKey: UUID().uuidString)
            }
            saved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ExternalSystemView: View {
    let client: ExternalSyncClient
    @State private var system: SystemDTO?; @State private var error: String?
    var body: some View {
        List {
            if let system {
                Section("Runtime") { LabeledContent("Uptime", value: Duration.seconds(system.uptimeSeconds).formatted()); LabeledContent("Scheduler", value: system.scheduler.isRunning ? "Đang chạy" : "Đã dừng"); LabeledContent("Deal Lists hoạt động", value: "\(system.scheduler.activeDealLists)") }
                Section("Bộ nhớ") { ProgressView(value: Double(system.memory.percentUsed), total: 100); LabeledContent("Đã dùng", value: "\(system.memory.percentUsed)%"); LabeledContent("Khả dụng", value: ByteCountFormatter.string(fromByteCount: system.memory.availableBytes, countStyle: .memory)) }
                Section("Sync leases") { if system.leases.isEmpty { Text("Không có lease đang hoạt động") }; ForEach(system.leases) { lease in VStack(alignment: .leading) { Text(lease.name); Text("Hết hạn \(lease.expiresAt.formatted())").font(.caption).foregroundStyle(.secondary) } } }
            } else if let error { Text(error).foregroundStyle(.red) } else { ProgressView() }
        }.navigationTitle("Hệ thống External Sync").task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async { do { system = try await client.send("/api/mobile/v2/system"); error = nil } catch { self.error = error.localizedDescription } }
}

private struct ChangeExternalPasswordView: View {
    @ObservedObject var auth: ExternalSyncAuthStore
    @State private var old = ""; @State private var new = ""; @State private var confirm = ""; @State private var message: String?; @State private var error: String?
    var body: some View {
        Form { SecureField("Mật khẩu hiện tại", text: $old); SecureField("Mật khẩu mới", text: $new); SecureField("Nhập lại mật khẩu", text: $confirm); if let message { Text(message).foregroundStyle(.green) }; if let error { Text(error).foregroundStyle(.red) }; Button("Đổi mật khẩu") { Task { await submit() } }.disabled(new.count < 6 || new != confirm) }.navigationTitle("Đổi mật khẩu")
    }
    @MainActor private func submit() async { struct Body: Encodable { let oldPassword: String; let newPassword: String }; do { let _: ChangeResult = try await auth.client.send("/api/mobile/v2/auth/change-password", method: "POST", body: Body(oldPassword: old, newPassword: new)); message = "Đã đổi mật khẩu. Vui lòng đăng nhập lại."; await auth.logout() } catch { self.error = error.localizedDescription } }
}
