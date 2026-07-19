import XCTest
@testable import AdminDomain

final class AdminDomainTests: XCTestCase {
    func testBaselineMatchesTargetDevice() {
        let baseline = AppBaseline()

        XCTAssertEqual(baseline.minimumIOS, "16.0")
        XCTAssertEqual(baseline.targetDevice, "iPhone X")
        XCTAssertEqual(baseline.targetIOS, "16.7.15")
        XCTAssertEqual(baseline.liveContainer, "LiveContainer 3.7.2")
    }

    func testToolOneIdentityAndLaunchTiming() {
        XCTAssertEqual(AppBaseline().appName, "Tool One")
        XCTAssertGreaterThanOrEqual(ToolOneLaunchTimeline.standardDuration, 1.2)
        XCTAssertLessThanOrEqual(ToolOneLaunchTimeline.standardDuration, 1.6)
        XCTAssertLessThan(
            ToolOneLaunchTimeline.reducedMotionDuration,
            ToolOneLaunchTimeline.standardDuration
        )
    }

    func testExternalSyncZeroDataIsReadyInsteadOfUnavailable() {
        let snapshot = ProgramSnapshot(
            id: .externalSync,
            title: "External Sync",
            state: .online,
            stale: false,
            updatedAt: Date(),
            summary: [.init(id: "deal-lists", label: "Deal Lists", value: "0", tone: .neutral)],
            collections: [],
            partial: false,
            timestamp: Date()
        )

        XCTAssertEqual(snapshot.workspaceState, .ready)
        XCTAssertEqual(snapshot.cachedCopy().workspaceState, .cached)
    }
}
