import XCTest
@testable import AdminDomain

final class DashboardTests: XCTestCase {
    func testCatalogAcceptsApprovedEntry() throws {
        let entry = makeEntry()
        XCTAssertEqual(DashboardCatalogValidator.validated([entry]), [entry])
    }

    func testCatalogRejectsUnknownIDInsecureURLIPAndExcludedHost() throws {
        let unknown = makeEntry(id: "unknown")
        let insecure = makeEntry(startURL: "http://scraper.deal-sync.online/login")
        let ip = makeEntry(startURL: "https://127.0.0.1", allowedHosts: ["127.0.0.1"])
        let excluded = makeEntry(startURL: "https://performance.beyondk.live", allowedHosts: ["performance.beyondk.live"])
        XCTAssertTrue(DashboardCatalogValidator.validated([unknown, insecure, ip, excluded]).isEmpty)
    }

    func testNavigationPolicyAllowsApprovedRedirectAndOAuth() throws {
        let entry = makeEntry(id: "shopee-dashboard", startURL: "https://monitor.beyondk.live/login.html", allowedHosts: ["monitor.beyondk.live", "monitor.deal-sync.online"], oauthHosts: ["accounts.google.com"])
        let policy = DashboardNavigationPolicy(entry: entry)
        XCTAssertEqual(policy.decision(for: try url("https://monitor.deal-sync.online/jobs")), .allow)
        XCTAssertEqual(policy.decision(for: try url("https://accounts.google.com/o/oauth2/v2/auth")), .allow)
    }

    func testNavigationPolicyHandsSafeExternalHTTPSLinkToSafari() throws {
        XCTAssertEqual(DashboardNavigationPolicy(entry: makeEntry()).decision(for: try url("https://support.apple.com/")), .openExternally)
    }

    func testNavigationPolicyBlocksUnsafeSchemeRawIPAndExcludedHost() throws {
        let policy = DashboardNavigationPolicy(entry: makeEntry())
        XCTAssertEqual(policy.decision(for: try url("file:///etc/passwd")), .cancel)
        XCTAssertEqual(policy.decision(for: try url("data:text/html,unsafe")), .cancel)
        XCTAssertEqual(policy.decision(for: try url("https://127.0.0.1/")), .cancel)
        XCTAssertEqual(policy.decision(for: try url("https://performance.beyondk.live/")), .cancel)
    }

    private func makeEntry(id: String = "autoshopee", startURL: String = "https://scraper.deal-sync.online/login", allowedHosts: [String] = ["scraper.deal-sync.online"], oauthHosts: [String] = []) -> DashboardEntry {
        DashboardEntry(id: id, title: "Dashboard", symbolName: "safari", startURL: URL(string: startURL)!, allowedHosts: allowedHosts, oauthHosts: oauthHosts, authentication: .existingLogin, orientation: .portrait, downloadPolicy: .safari, enabled: true, healthState: .available)
    }

    private func url(_ value: String) throws -> URL { try XCTUnwrap(URL(string: value)) }
}
