import XCTest
@testable import AdminDomain

private actor ExternalSyncLiveLoaderStub: ExternalSyncLiveLoading {
    enum StubError: Error { case unavailable }

    let items: [DealListDTO]
    let dashboard: DashboardDTO?
    let dealListError: Error?
    let dashboardDelay: UInt64
    private(set) var dealListRequests = 0

    init(
        items: [DealListDTO],
        dashboard: DashboardDTO? = nil,
        dealListError: Error? = nil,
        dashboardDelay: UInt64 = 0
    ) {
        self.items = items
        self.dashboard = dashboard
        self.dealListError = dealListError
        self.dashboardDelay = dashboardDelay
    }

    func loadDealLists() async throws -> [DealListDTO] {
        dealListRequests += 1
        if let dealListError { throw dealListError }
        return items
    }

    func loadDashboard() async throws -> DashboardDTO {
        if dashboardDelay > 0 { try await Task.sleep(nanoseconds: dashboardDelay) }
        guard let dashboard else { throw StubError.unavailable }
        return dashboard
    }
}

@MainActor
final class ExternalSyncLiveLoadingTests: XCTestCase {
    private func dealList(id: String, isActive: Bool) -> DealListDTO {
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
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    func testRefreshPublishesDealListsWithoutWaitingForSlowDashboard() async {
        let loader = ExternalSyncLiveLoaderStub(
            items: [dealList(id: "live", isActive: true)],
            dashboardDelay: 2_000_000_000
        )
        let store = ExternalSyncLiveStore(loader: loader, cache: nil)
        let completed = expectation(description: "fast baseline")

        Task {
            await store.refresh(force: true)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 0.5)
        XCTAssertEqual(store.summary?.dealListTotal, 1)
        XCTAssertEqual(store.summary?.activeDealLists, 1)
        XCTAssertFalse(store.isInitialLoading)
        XCTAssertTrue(store.isEnriching)
    }

    func testFailedRefreshRetainsPreviousDataAndMarksItStale() async {
        let loader = ExternalSyncLiveLoaderStub(
            items: [],
            dealListError: ExternalSyncLiveLoaderStub.StubError.unavailable
        )
        let store = ExternalSyncLiveStore(loader: loader, cache: nil)
        store.acceptDealLists([dealList(id: "cached", isActive: true)])

        await store.refresh(force: true)

        XCTAssertEqual(store.summary?.dealListTotal, 1)
        XCTAssertTrue(store.summary?.stale == true)
        XCTAssertNotNil(store.errorMessage)
    }
}
