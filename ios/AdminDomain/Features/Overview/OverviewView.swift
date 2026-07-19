import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: ProgramsStore
    let api: APIClient
    let onOpenProgram: (NativeProgramID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ToolOneLayout.spacingM) {
                workspaceHeader
                availabilityCard

                VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
                    Text("Chương trình")
                        .font(.title2.bold())
                    ForEach(NativeProgramID.allCases) { id in
                        ProgramLauncherCard(
                            id: id,
                            snapshot: store.snapshots[id],
                            error: store.errors[id],
                            isLoading: store.isLoading,
                            onOpen: { onOpenProgram(id) },
                            onRetry: { Task { await store.load() } }
                        )
                    }
                }

                recentActivity
            }
            .padding(.horizontal, ToolOneLayout.spacingS)
            .padding(.vertical, ToolOneLayout.spacingS)
        }
        .background(ToolOneSurface.canvas)
        .navigationTitle("Tổng quan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var workspaceHeader: some View {
        HStack(spacing: ToolOneLayout.spacingS) {
            FoldedOneMark()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tool One")
                    .font(.title.bold())
                Text("Không gian làm việc đồng bộ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var availabilityCard: some View {
        HStack(spacing: ToolOneLayout.spacingS) {
            ZStack {
                Circle().fill(ToolOneBrand.electric.opacity(0.12))
                Image(systemName: availableCount == NativeProgramID.allCases.count ? "checkmark.shield.fill" : "wave.3.right.circle.fill")
                    .foregroundStyle(availableCount == NativeProgramID.allCases.count ? .green : .orange)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(availableCount)/\(NativeProgramID.allCases.count) chương trình sẵn sàng")
                    .font(.headline)
                Text(availabilityMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading { ProgressView().accessibilityLabel("Đang cập nhật") }
        }
        .toolOneCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
            Text("Hoạt động gần đây")
                .font(.title2.bold())
            if recentRecords.isEmpty {
                HStack(spacing: ToolOneLayout.spacingS) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(ToolOneBrand.electric)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chưa có hoạt động mới").font(.headline)
                        Text("Các tiến trình đồng bộ gần nhất sẽ xuất hiện tại đây.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toolOneCard()
            } else {
                ForEach(recentRecords.prefix(3)) { item in
                    HStack(alignment: .top, spacing: ToolOneLayout.spacingS) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(ToolOneBrand.electric)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline).lineLimit(2)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text(item.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .toolOneCard()
                }
            }
        }
    }

    private var availableCount: Int {
        store.snapshots.values.filter { $0.workspaceState != .unavailable }.count
    }

    private var availabilityMessage: String {
        if store.snapshots.values.contains(where: { $0.stale }) {
            return "Một số dữ liệu được lấy từ bộ nhớ đệm. Kéo xuống để cập nhật."
        }
        if !store.errors.isEmpty {
            return "Có chương trình chưa cập nhật được. Bạn vẫn có thể mở để thử lại."
        }
        return "Dữ liệu được tổng hợp từ Deal Sync và External Sync."
    }

    private var recentRecords: [ProgramRecord] {
        let activityIDs: Set<String> = ["activity", "processes", "transfers", "submissions", "logs"]
        return store.snapshots.values
            .flatMap(\.collections)
            .filter { activityIDs.contains($0.id) }
            .flatMap(\.items)
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

private struct ProgramLauncherCard: View {
    let id: NativeProgramID
    let snapshot: ProgramSnapshot?
    let error: String?
    let isLoading: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolOneLayout.spacingS) {
            HStack(alignment: .top, spacing: ToolOneLayout.spacingS) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ToolOneBrand.electric.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ToolOneBrand.electric)
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.bold())
                    if let snapshot {
                        HStack(spacing: ToolOneLayout.spacingXS) {
                            StatusPill(state: snapshot.state, compact: true)
                            FreshnessLabel(date: snapshot.updatedAt, stale: snapshot.stale)
                        }
                    } else if isLoading {
                        Label("Đang cập nhật", systemImage: "clock")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("Chưa cập nhật được", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            if let snapshot {
                let metrics = Array(snapshot.summary.prefix(3))
                if !metrics.isEmpty {
                    HStack(alignment: .top, spacing: ToolOneLayout.spacingS) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.value).font(.title3.bold()).minimumScaleFactor(0.7)
                                Text(metric.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(id == .externalSync ? "External Sync đã sẵn sàng. Chưa có Deal List." : "Chưa có số liệu tổng hợp.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error {
                Text(ToolOneFriendlyError.message(for: NSError(domain: error, code: 0)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Cập nhật lại", action: onRetry)
                    .frame(minHeight: ToolOneLayout.minimumTouchTarget)
            }

            PrimaryProgramButton(title: "Mở \(title)", systemImage: "arrow.up.right", action: onOpen)
        }
        .toolOneCard()
    }

    private var title: String { id == .dealSync ? "Deal Sync" : "External Sync" }
    private var symbol: String { id == .dealSync ? "arrow.triangle.2.circlepath" : "arrow.up.arrow.down" }
}
