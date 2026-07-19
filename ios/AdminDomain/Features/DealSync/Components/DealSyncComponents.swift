import SwiftUI

struct DealSyncOfflineBanner: View {
    let isOnline: Bool
    var body: some View {
        if !isOnline {
            Label("Đang ngoại tuyến · thao tác ghi đã tạm khóa", systemImage: "wifi.slash")
                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.orange)
                .accessibilityLabel("Đang ngoại tuyến. Các thao tác thay đổi dữ liệu đã tạm khóa.")
        }
    }
}

struct DealSyncErrorView: View {
    let message: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Không tải được dữ liệu").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry { Button("Thử lại", action: retry) }
        }.padding()
    }
}

struct DealSyncEmptyView: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View { VStack(spacing: 12) { Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary); Text(title).font(.headline); Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding() }
}

struct DealSyncMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DealSyncOperationView: View {
    let client: DealSyncClient
    let initial: DealSyncOperation
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var ledger: DealSyncOperationLedger
    @State private var operation: DealSyncOperation
    @State private var error: String?
    @State private var polling = false

    init(client: DealSyncClient, operation: DealSyncOperation) {
        self.client = client; self.initial = operation; _operation = State(initialValue: operation)
    }
    var body: some View {
        List {
            Section("Tiến trình") {
                ProgressView(value: Double(operation.progress), total: 100) { Text(operation.kind) } currentValueLabel: { Text("\(operation.progress)%") }
                    .accessibilityValue("\(operation.progress) phần trăm")
                LabeledContent("Trạng thái", value: operation.state)
                if let currentItem = operation.currentItem { Text(currentItem).font(.footnote).foregroundStyle(.secondary) }
            }
            if let result = operation.result { Section("Kết quả") { JSONValueView(value: result) } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Tiến trình")
        .onAppear { ledger.register(operation.id) }
        .task(id: scenePhase) { if scenePhase == .active { await poll() } }
    }
    @MainActor private func poll() async {
        guard !polling else { return }; polling = true; defer { polling = false }
        var delay: UInt64 = 1
        while !operation.isTerminal && scenePhase == .active {
            do {
                operation = try await client.send(DealSyncEndpoint("/api/mobile/v2/operations/\(operation.id)"))
                error = nil
            } catch { self.error = error.localizedDescription }
            if operation.isTerminal { ledger.complete(operation.id); break }
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 8)
        }
    }
}

struct JSONValueView: View {
    let value: JSONValue
    var body: some View {
        switch value {
        case .object(let object): ForEach(object.keys.sorted(), id: \.self) { key in LabeledContent(key, value: object[key]?.displayText ?? "—") }
        case .array(let values): ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text(value.displayText) }
        default: Text(value.displayText)
        }
    }
}

extension View {
    func dealSyncMutationDisabled(_ isOnline: Bool, busy: Bool = false) -> some View { disabled(!isOnline || busy) }
}
