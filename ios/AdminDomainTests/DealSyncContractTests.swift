import XCTest
@testable import AdminDomain

final class DealSyncContractTests: XCTestCase {
    func testProductionOriginAndFiveTabsAreFixed() {
        XCTAssertEqual(DealSyncClient.productionURL.scheme, "https")
        XCTAssertEqual(DealSyncClient.productionURL.host, "traketqua.deal-sync.online")
        XCTAssertEqual(DealSyncTab.allCases.map(\.rawValue), ["sync", "submit", "sheets", "kpi", "more"])
    }

    func testSuccessFixtureDecodes() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "deal-sync-success", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder.api.decode(DealSyncEnvelope<JSONValue>.self, from: data)
        XCTAssertEqual(value.apiVersion, "2.0.0")
        XCTAssertFalse(value.requestId.isEmpty)
    }

    func testProblemNeverContainsCredentialFields() throws {
        let data = try XCTUnwrap(#"{"code":"validation_failed","message":"Dữ liệu chưa hợp lệ","fieldErrors":{},"requestId":"ios-test"}"#.data(using: .utf8))
        let problem = try JSONDecoder.api.decode(DealSyncProblem.self, from: data)
        XCTAssertEqual(problem.code, "validation_failed")
        XCTAssertFalse(String(describing: problem).localizedCaseInsensitiveContains("token"))
    }

    func testResilientOAuthStartAndPendingPayloadsDecode() throws {
        let startData = try XCTUnwrap(#"{"transactionId":"tx-1234567890123456","pollingSecret":"secret-1234567890123456","authorizationUrl":"https://traketqua.deal-sync.online/auth/signin?mobileState=opaque","expiresAt":"2026-07-19T10:00:00.000Z","pollAfterMs":750}"#.data(using: .utf8))
        let start = try JSONDecoder.api.decode(DealSyncOAuthStart.self, from: startData)
        XCTAssertEqual(start.pollAfterMs, 750)
        XCTAssertEqual(start.authorizationURL.scheme, "https")

        let pendingData = try XCTUnwrap(#"{"status":"pending","retryAfterMs":1200}"#.data(using: .utf8))
        let pending = try JSONDecoder.api.decode(DealSyncOAuthPollResponse.self, from: pendingData)
        XCTAssertEqual(pending.status, .pending(retryAfterMilliseconds: 1200))
    }
}
