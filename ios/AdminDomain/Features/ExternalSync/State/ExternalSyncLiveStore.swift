import Foundation
import SwiftUI

protocol ExternalSyncLiveLoading {
    func loadDealLists() async throws -> [DealListDTO]
    func loadDashboard() async throws -> DashboardDTO
}

struct ExternalSyncClientLiveLoader: ExternalSyncLiveLoading {
    let client: ExternalSyncClient

    func loadDealLists() async throws -> [DealListDTO] {
        let page: ExternalPage<DealListDTO> = try await client.send("/api/mobile/v2/deal-lists?limit=100")
        return page.items
    }

    func loadDashboard() async throws -> DashboardDTO {
        try await client.send("/api/mobile/v2/dashboard")
    }
}

struct ExternalSyncLiveSummary: Codable {
    var dealListTotal: Int
    var activeDealLists: Int
    var processTotal: Int
    var successfulProcesses: Int
    var failedProcesses: Int
    var recentActivity: [ProcessLogDTO]
    var updatedAt: Date
    var stale: Bool

    static func baseline(items: [DealListDTO], updatedAt: Date = Date()) -> Self {
        .init(
            dealListTotal: items.count,
            activeDealLists: items.filter(\.isActive).count,
            processTotal: 0,
            successfulProcesses: 0,
            failedProcesses: 0,
            recentActivity: [],
            updatedAt: updatedAt,
            stale: false
        )
    }

    func merging(_ dashboard: DashboardDTO) -> Self {
        let dashboardIsCurrent = dashboard.generatedAt >= updatedAt
        return .init(
            dealListTotal: dashboardIsCurrent ? dashboard.dealLists.total : dealListTotal,
            activeDealLists: dashboardIsCurrent ? dashboard.dealLists.active : activeDealLists,
            processTotal: dashboard.processes.total,
            successfulProcesses: dashboard.processes.successful,
            failedProcesses: dashboard.processes.failed,
            recentActivity: dashboard.recentActivity,
            updatedAt: max(updatedAt, dashboard.generatedAt),
            stale: false
        )
    }

    var programSnapshot: ProgramSnapshot {
        ProgramSnapshot(
            id: .externalSync,
            title: "External Sync",
            state: .online,
            stale: stale,
            updatedAt: updatedAt,
            summary: [
                ProgramMetric(
                    id: "deal-lists",
                    label: "Deal List",
                    value: String(dealListTotal),
                    tone: .neutral
                ),
                ProgramMetric(
                    id: "running",
                    label: "Đang chạy",
                    value: String(activeDealLists),
                    tone: activeDealLists > 0 ? .success : .neutral
                ),
                ProgramMetric(
                    id: "failed",
                    label: "Log lỗi gần đây",
                    value: String(failedProcesses),
                    tone: failedProcesses > 0 ? .critical : .neutral
                )
            ],
            collections: [],
            partial: false,
            timestamp: updatedAt
        )
    }
}

@MainActor
final class ExternalSyncLiveStore: ObservableObject {
    @Published private(set) var summary: ExternalSyncLiveSummary?
    @Published private(set) var isInitialLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var isEnriching = false
    @Published private(set) var errorMessage: String?

    private let loader: any ExternalSyncLiveLoading
    private let cache: SnapshotCache?
    private var loadedCache = false

    convenience init(client: ExternalSyncClient, cache: SnapshotCache?) {
        self.init(loader: ExternalSyncClientLiveLoader(client: client), cache: cache)
    }

    init(loader: any ExternalSyncLiveLoading, cache: SnapshotCache?) {
        self.loader = loader
        self.cache = cache
    }

    func refresh(force: Bool = false) async {
        if isRefreshing && !force { return }
        await restoreCacheIfNeeded()
        isRefreshing = true
        defer {
            isRefreshing = false
            isInitialLoading = false
        }

        do {
            let items = try await loader.loadDealLists()
            acceptDealLists(items)
            errorMessage = nil
            isEnriching = true
            Task { [weak self] in
                await self?.enrichDashboard()
            }
        } catch {
            if summary != nil { summary?.stale = true }
            errorMessage = ToolOneFriendlyError.message(for: error)
        }
    }

    func acceptDealLists(_ items: [DealListDTO]) {
        let baseline = ExternalSyncLiveSummary.baseline(items: items)
        summary = baseline
        Task { [cache] in
            try? await cache?.save(baseline, key: Self.cacheKey)
        }
    }

    func invalidateAndRefresh() async {
        await refresh(force: true)
    }

    private func restoreCacheIfNeeded() async {
        guard !loadedCache else { return }
        loadedCache = true
        if let cached = try? await cache?.load(ExternalSyncLiveSummary.self, key: Self.cacheKey) {
            var stale = cached
            stale.stale = true
            summary = stale
            isInitialLoading = false
        }
    }

    private func enrichDashboard() async {
        defer { isEnriching = false }
        do {
            let dashboard = try await loader.loadDashboard()
            let merged = (summary ?? .baseline(items: [])).merging(dashboard)
            summary = merged
            errorMessage = nil
            try? await cache?.save(merged, key: Self.cacheKey)
        } catch {
            if summary == nil {
                errorMessage = ToolOneFriendlyError.message(for: error)
            }
        }
    }

    private static let cacheKey = "external-live-summary"
}
