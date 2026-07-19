import XCTest
@testable import AdminDomain

final class DealSyncFoundationTests: XCTestCase {
    func testDestinationDecodesLegacyJSONStringShopIDs() throws {
        let data = try XCTUnwrap(#"{"id":"d1","name":"Sheet","spreadsheetId":"book","shopIds":"[\"1\",\"2\"]","fromLinkedUser":true}"#.data(using: .utf8))
        let value = try JSONDecoder.api.decode(DealSyncDestination.self, from: data)
        XCTAssertEqual(value.shopIds ?? [], ["1", "2"])
        XCTAssertEqual(value.fromLinkedUser, true)
    }

    func testOperationTerminalStatesAreStable() throws {
        let base = #"{"id":"op","kind":"SYNC","state":"SUCCEEDED","progress":100,"createdAt":"2026-07-18T10:00:00.000Z","updatedAt":"2026-07-18T10:01:00.000Z"}"#
        let operation = try JSONDecoder.api.decode(DealSyncOperation.self, from: XCTUnwrap(base.data(using: .utf8)))
        XCTAssertTrue(operation.isTerminal)
        XCTAssertEqual(operation.progress, 100)
    }

    @MainActor
    func testOperationLedgerIsAccountScopedAndBounded() {
        let suite = "DealSyncFoundationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DealSyncOperationLedger(accountID: "a", defaults: defaults)
        let second = DealSyncOperationLedger(accountID: "b", defaults: defaults)
        for index in 0..<35 { first.register("op-\(index)") }
        XCTAssertEqual(first.operationIDs.count, 30)
        XCTAssertTrue(second.operationIDs.isEmpty)
        first.complete("op-34")
        XCTAssertFalse(first.operationIDs.contains("op-34"))
    }

    func testOAuthErrorsMapToStableFriendlyStates() {
        XCTAssertEqual(DealSyncOAuthError(problemCode: "account_not_allowed"), .accountNotAllowed)
        XCTAssertEqual(DealSyncOAuthError(problemCode: "authorization_transaction_expired"), .expired)
        XCTAssertEqual(DealSyncOAuthError(problemCode: "authorization_transaction_used"), .sessionClaimed)
        XCTAssertEqual(DealSyncOAuthError(problemCode: "http_503"), .serverUnavailable)
    }
}
