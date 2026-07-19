import XCTest
@testable import AdminDomain

@MainActor
final class FoundationTests: XCTestCase {
    func testTabsHaveStableIdentifiers() {
        XCTAssertEqual(
            AppTab.allCases.map(\.rawValue),
            ["overview", "activity", "settings"]
        )
    }

    func testProgramRoundTripPreservesWorkspaceTab() {
        let router = AppRouter()
        router.selectedTab = .activity

        router.open(.externalSync)
        XCTAssertEqual(router.mode, .externalSync)

        router.closeProgram()
        XCTAssertEqual(router.mode, .workspace)
        XCTAssertEqual(router.selectedTab, .activity)
    }

    func testFriendlyErrorsHideFrameworkAndLocalizationDetails() {
        let authentication = NSError(
            domain: "com.apple.AuthenticationServices.WebAuthenticationSession",
            code: 1
        )
        XCTAssertFalse(ToolOneFriendlyError.message(for: authentication).contains("AuthenticationServices"))
        XCTAssertFalse(ToolOneFriendlyError.message(for: NSError(domain: "tab.overview", code: 0)).contains("tab.overview"))
    }

    func testTabTitlesResolveInsteadOfDisplayingLocalizationKeys() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.localizedTitle.hasPrefix("tab."))
            XCTAssertFalse(tab.localizedTitle.isEmpty)
        }
    }

    func testEnvironmentAcceptsHTTPS() throws {
        let url = try XCTUnwrap(URL(string: "https://admin-api.beyondk.live"))
        let environment = try AppEnvironment(deployment: .production, baseURL: url)

        XCTAssertEqual(environment.baseURL.scheme, "https")
    }

    func testEnvironmentRejectsHTTP() throws {
        let url = try XCTUnwrap(URL(string: "http://admin-api.beyondk.live"))

        XCTAssertThrowsError(try AppEnvironment(deployment: .development, baseURL: url)) { error in
            XCTAssertEqual(error as? AppEnvironmentError, .insecureBaseURL)
        }
    }
}
