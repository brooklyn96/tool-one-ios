import Foundation
import OSLog

struct DashboardCatalogResponse: Codable, Equatable {
    let items: [DashboardEntry]
    let timestamp: Date
}

struct DashboardEntry: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let startURL: URL
    let allowedHosts: [String]
    let oauthHosts: [String]
    let authentication: Authentication
    let orientation: Orientation
    let downloadPolicy: DownloadPolicy
    let enabled: Bool
    let healthState: HealthState

    enum Authentication: String, Codable { case existingLogin = "existing-login"; case googleOAuth = "google-oauth" }
    enum Orientation: String, Codable { case portrait; case landscapeSupported = "landscape-supported" }
    enum DownloadPolicy: String, Codable { case safari }
    enum HealthState: String, Codable { case available, degraded, unavailable }
}

enum DashboardCatalogValidator {
    private struct Policy {
        let navigationHosts: Set<String>
        let oauthHosts: Set<String>
    }

    private static let policies: [String: Policy] = [
        "autoshopee": Policy(navigationHosts: ["scraper.deal-sync.online"], oauthHosts: []),
        "deal-sync": Policy(navigationHosts: ["traketqua.deal-sync.online"], oauthHosts: ["accounts.google.com"]),
        "external-sync": Policy(navigationHosts: ["update.deal-sync.online"], oauthHosts: []),
        "shopee-dashboard": Policy(navigationHosts: ["monitor.beyondk.live", "monitor.deal-sync.online"], oauthHosts: ["accounts.google.com"])
    ]
    private static let excludedHosts: Set<String> = ["performance.beyondk.live"]
    private static let logger = Logger(subsystem: "com.beyondk.admindomain", category: "dashboard-catalog")

    static func validated(_ entries: [DashboardEntry]) -> [DashboardEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            guard entry.enabled, !seen.contains(entry.id), let policy = policies[entry.id],
                  isSafeHTTPS(entry.startURL), let host = entry.startURL.host?.lowercased(),
                  entry.allowedHosts.map({ $0.lowercased() }).contains(host),
                  Set(entry.allowedHosts.map({ $0.lowercased() })).isSubset(of: policy.navigationHosts),
                  Set(entry.oauthHosts.map({ $0.lowercased() })).isSubset(of: policy.oauthHosts),
                  !entry.allowedHosts.contains(where: { excludedHosts.contains($0.lowercased()) }),
                  !entry.oauthHosts.contains(where: { excludedHosts.contains($0.lowercased()) }) else {
                logger.error("Rejected dashboard entry id=\(entry.id, privacy: .public)")
                return false
            }
            seen.insert(entry.id)
            return true
        }
    }

    static func isSafeHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              !excludedHosts.contains(host), !isIPLiteral(host) else { return false }
        return true
    }

    private static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in UInt8(part) != nil }
    }
}
