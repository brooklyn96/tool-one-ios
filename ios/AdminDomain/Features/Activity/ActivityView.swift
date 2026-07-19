import SwiftUI

struct ActivityView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, running, attention
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tất cả"
            case .running: return "Đang chạy"
            case .attention: return "Cần chú ý"
            }
        }
    }

    @ObservedObject var store: ProgramsStore
    let api: APIClient
    @State private var filter = Filter.all
    private let activityCollectionIDs: Set<String> = ["activity", "processes", "transfers", "submissions", "logs"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ToolOneLayout.spacingM) {
                VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
                    Text("Hoạt động")
                        .font(.largeTitle.bold())
                    Picker("Lọc hoạt động", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Lọc theo trạng thái tiến trình")
                    if let latestUpdate {
                        FreshnessLabel(date: latestUpdate.date, stale: latestUpdate.stale)
                    }
                }

                if store.isLoading && items.isEmpty {
                    HStack(spacing: ToolOneLayout.spacingS) {
                        ProgressView()
                        Text("Đang cập nhật hoạt động…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .toolOneCard()
                } else if filteredItems.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            ProgramRecordView(record: item.record)
                        } label: {
                            activityCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(ToolOneLayout.spacingS)
        }
        .background(ToolOneSurface.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var emptyState: some View {
        VStack(spacing: ToolOneLayout.spacingS) {
            Image(systemName: filter == .attention ? "checkmark.shield" : "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(filter == .attention ? .green : ToolOneBrand.electric)
                .accessibilityHidden(true)
            Text(filter == .attention ? "Không có mục cần chú ý" : "Chưa có hoạt động")
                .font(.title3.bold())
            Text(store.errors.isEmpty
                 ? "Các tiến trình từ Deal Sync và External Sync sẽ xuất hiện tại đây."
                 : "Một số chương trình chưa cập nhật được. Thử lại để lấy trạng thái mới nhất.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Thử cập nhật lại") { Task { await store.load() } }
                .buttonStyle(.bordered)
                .frame(minHeight: ToolOneLayout.minimumTouchTarget)
        }
        .frame(maxWidth: .infinity)
        .toolOneCard()
    }

    private func activityCard(_ item: ActivityItem) -> some View {
        HStack(alignment: .top, spacing: ToolOneLayout.spacingS) {
            ZStack {
                Circle().fill(item.tint.opacity(0.12))
                Image(systemName: item.symbol).foregroundStyle(item.tint)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.record.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Spacer()
                    Text(item.statusLabel).font(.caption.bold()).foregroundStyle(item.tint)
                }
                if let subtitle = item.record.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Text(item.programTitle)
                    Spacer()
                    Text(item.record.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .toolOneCard()
        .accessibilityElement(children: .combine)
    }

    private var filteredItems: [ActivityItem] {
        switch filter {
        case .all: return items
        case .running: return items.filter(\.isRunning)
        case .attention: return items.filter(\.needsAttention)
        }
    }

    private var items: [ActivityItem] {
        NativeProgramID.allCases.flatMap { id -> [ActivityItem] in
            guard let snapshot = store.snapshots[id] else { return [] }
            return snapshot.collections
                .filter { activityCollectionIDs.contains($0.id) }
                .flatMap(\.items)
                .map { ActivityItem(programID: id, programTitle: snapshot.title, record: $0) }
        }
        .sorted { $0.record.updatedAt > $1.record.updatedAt }
    }

    private var latestUpdate: (date: Date, stale: Bool)? {
        guard let newest = store.snapshots.values.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        return (newest.updatedAt, store.snapshots.values.contains(where: \.stale))
    }

    private struct ActivityItem: Identifiable {
        let programID: NativeProgramID
        let programTitle: String
        let record: ProgramRecord
        var id: String { "\(programID.rawValue)-\(record.id)" }
        private var normalized: String { record.status.lowercased() }
        var isRunning: Bool { ["pending", "running", "in_progress", "processing"].contains(normalized) }
        var needsAttention: Bool { ["failed", "error", "cancelled", "canceled"].contains(normalized) }
        var symbol: String { needsAttention ? "exclamationmark.triangle.fill" : isRunning ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill" }
        var tint: Color { needsAttention ? .red : isRunning ? ToolOneBrand.electric : .green }
        var statusLabel: String { needsAttention ? "Cần chú ý" : isRunning ? "Đang chạy" : "Hoàn tất" }
    }
}
