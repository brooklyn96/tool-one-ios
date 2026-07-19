import SwiftUI

struct DealListDraft {
    var input = DealListInputDTO()
    var sourceMappingText = ""
    var targetMappingText = ""

    init(detail: DealListDetailDTO? = nil) {
        guard let detail else { return }
        input.name = detail.name
        input.sourceSpreadsheetId = detail.sourceSpreadsheetId
        input.sourceSheetName = detail.sourceSheetName
        input.sourceColumnMapping = detail.sourceColumnMapping
        input.targetSpreadsheetId = detail.targetSpreadsheetId
        input.targetSheetName = detail.targetSheetName
        input.targetColumnMapping = detail.targetColumnMapping
        input.livestreamOn = detail.livestreamOn
        input.livestreamDate = detail.livestreamDate
        input.reviewAtcStopAt = detail.reviewAtcStopAt
        input.stopProcessingAt = detail.stopProcessingAt
        sourceMappingText = Self.mappingText(detail.sourceColumnMapping)
        targetMappingText = Self.mappingText(detail.targetColumnMapping)
    }

    var isReadyToSave: Bool {
        !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !input.sourceSpreadsheetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !input.sourceSheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !input.targetSpreadsheetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !input.targetSheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func applyAdvancedMappings() {
        input.sourceColumnMapping = Self.parseMapping(sourceMappingText)
        input.targetColumnMapping = Self.parseMapping(targetMappingText)
    }

    private static func mappingText(_ value: [String: String]?) -> String {
        (value ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private static func parseMapping(_ text: String) -> [String: String]? {
        let pairs = text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return key.isEmpty || value.isEmpty ? nil : (key, value)
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }
}

struct DealListEditorView: View {
    let client: ExternalSyncClient
    let detail: DealListDetailDTO?
    let saved: () -> Void

    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DealListDraft
    @State private var sourceSheets: [String] = []
    @State private var targetSheets: [String] = []
    @State private var discovering: Endpoint?
    @State private var isSaving = false
    @State private var error: String?
    @State private var showAdvanced = false

    private enum Endpoint: Equatable { case source, target }

    init(client: ExternalSyncClient, detail: DealListDetailDTO? = nil, saved: @escaping () -> Void) {
        self.client = client
        self.detail = detail
        self.saved = saved
        _draft = State(initialValue: DealListDraft(detail: detail))
    }

    var body: some View {
        Form {
            Section {
                TextField("Tên Deal List", text: $draft.input.name)
                    .textContentType(.name)
                optionalDay("Ngày livestream", value: $draft.input.livestreamOn)
                optionalDate("Dừng Review/ATC", value: $draft.input.reviewAtcStopAt)
            } header: {
                Text("1 · Thông tin")
            }

            spreadsheetSection(
                title: "2 · Nguồn dữ liệu",
                id: $draft.input.sourceSpreadsheetId,
                sheet: $draft.input.sourceSheetName,
                sheets: sourceSheets,
                endpoint: .source
            )

            spreadsheetSection(
                title: "3 · Sheet đích",
                id: $draft.input.targetSpreadsheetId,
                sheet: $draft.input.targetSheetName,
                sheets: targetSheets,
                endpoint: .target
            )

            Section {
                DisclosureGroup("Tùy chọn nâng cao", isExpanded: $showAdvanced) {
                    TextField("Ngày legacy DD.MM", text: optionalText($draft.input.livestreamDate))
                    optionalDate("Dừng xử lý", value: $draft.input.stopProcessingAt)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mapping nguồn").font(.subheadline)
                        TextEditor(text: $draft.sourceMappingText).frame(minHeight: 80)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mapping đích").font(.subheadline)
                        TextEditor(text: $draft.targetMappingText).frame(minHeight: 80)
                    }
                }
            }

            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
        .navigationTitle(detail == nil ? "Thêm Deal List" : "Chỉnh sửa Deal List")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() }.disabled(isSaving) }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Đang lưu…" : "Lưu") { Task { await save() } }
                    .disabled(!draft.isReadyToSave || !connectivity.isOnline || isSaving)
            }
        }
    }

    private func spreadsheetSection(
        title: String,
        id: Binding<String>,
        sheet: Binding<String>,
        sheets: [String],
        endpoint: Endpoint
    ) -> some View {
        Section(title) {
            TextField("Dán URL hoặc Spreadsheet ID", text: id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await discover(id.wrappedValue, endpoint: endpoint) }
            } label: {
                HStack {
                    if discovering == endpoint { ProgressView() }
                    Text(discovering == endpoint ? "Đang kiểm tra…" : "Kiểm tra và chọn worksheet")
                }
            }
            .disabled(id.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || discovering != nil)
            if sheets.isEmpty {
                TextField("Tên worksheet", text: sheet)
            } else {
                Picker("Worksheet", selection: sheet) {
                    ForEach(sheets, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private func optionalText(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    @ViewBuilder private func optionalDay(_ title: String, value: Binding<String?>) -> some View {
        TextField("\(title) YYYY-MM-DD", text: optionalText(value))
            .textInputAutocapitalization(.never)
    }

    @ViewBuilder private func optionalDate(_ title: String, value: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? Date() : nil }
        ))
        if value.wrappedValue != nil {
            DatePicker(title, selection: Binding(
                get: { value.wrappedValue ?? Date() },
                set: { value.wrappedValue = $0 }
            ))
        }
    }

    @MainActor private func discover(_ value: String, endpoint: Endpoint) async {
        struct Body: Encodable { let spreadsheet: String }
        discovering = endpoint
        error = nil
        defer { discovering = nil }
        do {
            let result: SheetDiscoveryDTO = try await client.send(
                "/api/mobile/v2/sheets/discover",
                method: "POST",
                body: Body(spreadsheet: value)
            )
            switch endpoint {
            case .source:
                sourceSheets = result.sheets
                draft.input.sourceSpreadsheetId = result.spreadsheetId
                if draft.input.sourceSheetName.isEmpty { draft.input.sourceSheetName = result.sheets.first ?? "" }
            case .target:
                targetSheets = result.sheets
                draft.input.targetSpreadsheetId = result.spreadsheetId
                if draft.input.targetSheetName.isEmpty { draft.input.targetSheetName = result.sheets.first ?? "" }
            }
        } catch {
            self.error = ToolOneFriendlyError.message(for: error)
        }
    }

    @MainActor private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        draft.applyAdvancedMappings()
        do {
            if let detail {
                let _: DealListDTO = try await client.send(
                    "/api/mobile/v2/deal-lists/\(detail.id)",
                    method: "PATCH",
                    body: draft.input,
                    idempotencyKey: UUID().uuidString
                )
            } else {
                let _: DealListDTO = try await client.send(
                    "/api/mobile/v2/deal-lists",
                    method: "POST",
                    body: draft.input,
                    idempotencyKey: UUID().uuidString
                )
            }
            saved()
            dismiss()
        } catch {
            self.error = ToolOneFriendlyError.message(for: error)
        }
    }
}
