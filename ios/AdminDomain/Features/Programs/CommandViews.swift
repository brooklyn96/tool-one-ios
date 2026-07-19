import SwiftUI

struct CommandCatalogView: View {
    let programID: NativeProgramID
    let api: APIClient
    @State private var commands: [ProgramCommand] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red); Button("Thử lại") { Task { await load() } } } }
            ForEach(commands) { command in
                NavigationLink { CommandFormView(programID: programID, command: command, api: api) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(command.title)
                            if command.destructive { Text("Cần xác nhận").font(.caption).foregroundStyle(.orange) }
                        }
                    } icon: { Image(systemName: command.symbolName).foregroundColor(command.destructive ? .orange : .accentColor) }
                }.frame(minHeight: 44)
            }
        }
        .navigationTitle("Thao tác")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } else if commands.isEmpty && error == nil { VStack(spacing: 12) { Image(systemName: "wrench.and.screwdriver").font(.largeTitle).foregroundStyle(.secondary); Text("Chưa có thao tác").foregroundStyle(.secondary) } } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { let response: CommandCatalogEnvelope = try await api.send("/v1/programs/\(programID.rawValue)/commands"); commands = response.commands }
        catch { self.error = error.localizedDescription }
    }
}

struct CommandFormView: View {
    let programID: NativeProgramID
    let command: ProgramCommand
    let api: APIClient
    @Environment(\.openURL) private var openURL
    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var isRunning = false
    @State private var result: CommandResult?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var retryKey: String?
    @State private var retrySignature: String?

    var body: some View {
        Form {
            Section("Thông tin") { ForEach(command.fields) { fieldView($0) } }
            if let result {
                Section("Kết quả") {
                    Label(result.message, systemImage: result.status == .succeeded ? "checkmark.circle.fill" : "clock.fill").foregroundStyle(.green)
                    LabeledContent("Thay đổi", value: "\(result.changed)")
                    if let url = result.oauthURL { Button("Mở trình duyệt để tiếp tục") { openURL(url) }.frame(minHeight: 44) }
                }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red); Button("Thử lại với cùng mã yêu cầu") { begin() }.disabled(isRunning) } }
            Section {
                Button(role: command.destructive ? .destructive : nil) { begin() } label: {
                    HStack { Spacer(); if isRunning { ProgressView() } else { Text(command.title).bold() }; Spacer() }
                }.disabled(isRunning || !isValid).frame(minHeight: 44)
            }
        }
        .navigationTitle(command.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Xác nhận thao tác", isPresented: $showConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("Tiếp tục", role: .destructive) { Task { await execute() } }
        } message: { Text(command.confirmation ?? "Bạn có chắc muốn tiếp tục?") }
    }

    @ViewBuilder private func fieldView(_ field: CommandField) -> some View {
        switch field.kind {
        case .boolean: Toggle(field.label, isOn: binding(for: field.key))
        case .secure: SecureField(field.label, text: textBinding(for: field.key)).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .number: TextField(field.label, text: textBinding(for: field.key)).keyboardType(.decimalPad)
        case .select:
            Picker(field.label, selection: textBinding(for: field.key)) { Text("Chọn").tag(""); ForEach(field.options ?? []) { Text($0.label).tag($0.value) } }
        case .text, .date: TextField(field.label, text: textBinding(for: field.key)).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private var isValid: Bool { command.fields.allSatisfy { !$0.required || $0.kind == .boolean || !(textValues[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private func textBinding(for key: String) -> Binding<String> { Binding(get: { textValues[key] ?? "" }, set: { textValues[key] = $0 }) }
    private func binding(for key: String) -> Binding<Bool> { Binding(get: { boolValues[key] ?? false }, set: { boolValues[key] = $0 }) }
    private func begin() { if command.destructive { showConfirmation = true } else { Task { await execute() } } }

    @MainActor private func execute() async {
        guard isValid, !isRunning else { return }
        let signature = command.fields.map { "\($0.key)=\(textValues[$0.key] ?? ""):\(boolValues[$0.key] ?? false)" }.joined(separator: "|")
        if retrySignature != signature { retryKey = UUID().uuidString; retrySignature = signature }
        var input: [String: CommandValue] = [:]
        for field in command.fields {
            if field.kind == .boolean { input[field.key] = .boolean(boolValues[field.key] ?? false) }
            else if field.kind == .number, let number = Double(textValues[field.key] ?? "") { input[field.key] = .number(number) }
            else { let value = (textValues[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { input[field.key] = .string(value) } }
        }
        isRunning = true; error = nil; result = nil; defer { isRunning = false }
        do {
            let response: CommandResult = try await api.send("/v1/programs/\(programID.rawValue)/commands/\(command.id)", method: "POST", body: CommandEnvelope(input: input), idempotencyKey: retryKey)
            result = response
        } catch { self.error = error.localizedDescription }
    }
}
