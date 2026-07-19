import Foundation

struct ExternalSyncLiveSummary: Codable, Equatable {
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
