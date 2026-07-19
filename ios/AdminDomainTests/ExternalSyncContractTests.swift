import XCTest
@testable import AdminDomain

final class ExternalSyncContractTests: XCTestCase {
    func testDashboardEnvelopeDecodesMobileV2Contract() throws {
        let json = """
        {
          "data": {
            "dealLists": {"total": 3, "active": 2},
            "processes": {"total": 10, "successful": 9, "failed": 1},
            "users": {"total": 2, "active": 2},
            "scheduler": {"isRunning": true, "activeDealLists": 2},
            "lastSync": null,
            "recentActivity": [],
            "generatedAt": "2026-07-18T00:00:00.000Z"
          },
          "meta": {"requestId": "request-1", "serverTime": "2026-07-18T00:00:00.000Z"}
        }
        """
        let envelope = try JSONDecoder.api.decode(ExternalEnvelope<DashboardDTO>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.data.dealLists.total, 3)
        XCTAssertEqual(envelope.data.processes.failed, 1)
        XCTAssertTrue(envelope.data.scheduler.isRunning)
    }

    func testUsersPageAllowsMissingCursorForNonPaginatedAdminEndpoint() throws {
        let json = """
        {"data":{"items":[{"id":"u1","username":"admin","email":null,"isAdmin":true,"isActive":true,"createdAt":"2026-07-18T00:00:00Z"}]},"meta":{"requestId":"r","serverTime":"2026-07-18T00:00:00Z"}}
        """
        let envelope = try JSONDecoder.api.decode(ExternalEnvelope<ExternalPage<AdminUserDTO>>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.data.items.first?.username, "admin")
        XCTAssertNil(envelope.data.nextCursor)
    }

    func testStableProblemEnvelopeDecodesFieldErrors() throws {
        let json = """
        {"error":{"code":"VALIDATION_ERROR","message":"Dữ liệu chưa hợp lệ.","fieldErrors":{"name":"Bắt buộc"},"requestId":"r1"}}
        """
        let problem = try JSONDecoder.api.decode(ExternalProblemEnvelope.self, from: Data(json.utf8)).error
        XCTAssertEqual(problem.code, "VALIDATION_ERROR")
        XCTAssertEqual(problem.fieldErrors?["name"], "Bắt buộc")
    }

    func testExternalSyncOriginIsHTTPSAndAllowlisted() {
        XCTAssertEqual(ExternalSyncClient.productionURL.scheme, "https")
        XCTAssertEqual(ExternalSyncClient.productionURL.host, "update.deal-sync.online")
    }

    func testZeroDealListsRemainAValidReadyDashboard() throws {
        let json = """
        {"data":{"dealLists":{"total":0,"active":0},"processes":{"total":0,"successful":0,"failed":0},"users":null,"scheduler":{"isRunning":true,"activeDealLists":0},"lastSync":null,"recentActivity":[],"generatedAt":"2026-07-19T00:00:00.000Z"},"meta":{"requestId":"zero","serverTime":"2026-07-19T00:00:00.000Z"}}
        """
        let dashboard = try JSONDecoder.api.decode(ExternalEnvelope<DashboardDTO>.self, from: Data(json.utf8)).data
        XCTAssertTrue(dashboard.isReadyEmpty)
        XCTAssertEqual(dashboard.dealLists.total, 0)
    }
}
