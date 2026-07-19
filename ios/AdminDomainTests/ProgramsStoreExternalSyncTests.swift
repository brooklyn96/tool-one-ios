import XCTest
@testable import AdminDomain

@MainActor
final class ProgramsStoreExternalSyncTests: XCTestCase {
    func testApplyExternalSyncReplacesStaleGatewaySnapshot() {
        let api = APIClient(baseURL: URL(string: "https://invalid.example")!)
        let store = ProgramsStore(api: api, cache: nil)
        let summary = ExternalSyncLiveSummary(
            dealListTotal: 1,
            activeDealLists: 1,
            processTotal: 7,
            successfulProcesses: 7,
            failedProcesses: 0,
            recentActivity: [],
            updatedAt: Date(timeIntervalSince1970: 100),
            stale: false
        )

        store.applyExternalSync(summary)

        XCTAssertEqual(store.snapshots[.externalSync], summary.programSnapshot)
        XCTAssertNil(store.errors[.externalSync])
    }
}
