import XCTest
@testable import AdminDomain

final class ExternalSyncLiveStoreTests: XCTestCase {
    private func dealList(id: String, isActive: Bool, updatedAt: Date) -> DealListDTO {
        DealListDTO(
            id: id,
            name: id,
            sourceSpreadsheetId: "source",
            sourceSheetName: "Source",
            sourceColumnMapping: nil,
            targetSpreadsheetId: "target",
            targetSheetName: "Target",
            targetColumnMapping: nil,
            livestreamOn: nil,
            livestreamDate: nil,
            reviewAtcStopAt: nil,
            stopProcessingAt: nil,
            isActive: isActive,
            lastSyncAt: nil,
            syncCount: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func dashboard(total: Int, active: Int, generatedAt: Date) -> DashboardDTO {
        DashboardDTO(
            dealLists: .init(total: total, active: active),
            processes: .init(total: 10, successful: 9, failed: 1),
            users: nil,
            scheduler: .init(isRunning: active > 0, activeDealLists: active),
            lastSync: nil,
            recentActivity: [],
            generatedAt: generatedAt
        )
    }

    func testDealListBaselineUsesCurrentVisibleAndActiveItems() {
        let updatedAt = Date(timeIntervalSince1970: 200)
        let summary = ExternalSyncLiveSummary.baseline(
            items: [
                dealList(id: "one", isActive: true, updatedAt: updatedAt),
                dealList(id: "two", isActive: false, updatedAt: updatedAt)
            ],
            updatedAt: updatedAt
        )

        XCTAssertEqual(summary.dealListTotal, 2)
        XCTAssertEqual(summary.activeDealLists, 1)
        XCTAssertEqual(summary.programSnapshot.summary.first?.value, "2")
        XCTAssertFalse(summary.stale)
    }

    func testOlderDashboardCannotOverwriteNewerLiveDealListCounts() {
        let baseline = ExternalSyncLiveSummary.baseline(
            items: [dealList(id: "live", isActive: true, updatedAt: Date(timeIntervalSince1970: 200))],
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = baseline.merging(
            dashboard(total: 0, active: 0, generatedAt: Date(timeIntervalSince1970: 100))
        )

        XCTAssertEqual(merged.dealListTotal, 1)
        XCTAssertEqual(merged.activeDealLists, 1)
        XCTAssertEqual(merged.failedProcesses, 1)
    }

    func testNewerDashboardEnrichesMetricsAndCounts() {
        let baseline = ExternalSyncLiveSummary.baseline(
            items: [dealList(id: "old", isActive: false, updatedAt: Date(timeIntervalSince1970: 100))],
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let merged = baseline.merging(
            dashboard(total: 3, active: 2, generatedAt: Date(timeIntervalSince1970: 200))
        )

        XCTAssertEqual(merged.dealListTotal, 3)
        XCTAssertEqual(merged.activeDealLists, 2)
        XCTAssertEqual(merged.processTotal, 10)
        XCTAssertEqual(merged.successfulProcesses, 9)
        XCTAssertEqual(merged.failedProcesses, 1)
    }
}
