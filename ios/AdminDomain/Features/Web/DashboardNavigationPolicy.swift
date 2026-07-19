import Foundation

enum DashboardNavigationDecision: Equatable {
    case allow
    case openExternally
    case cancel
}

struct DashboardNavigationPolicy {
    let entry: DashboardEntry

    func decision(for url: URL) -> DashboardNavigationDecision {
        guard DashboardCatalogValidator.isSafeHTTPS(url), let host = url.host?.lowercased() else { return .cancel }
        let embeddedHosts = Set((entry.allowedHosts + entry.oauthHosts).map { $0.lowercased() })
        return embeddedHosts.contains(host) ? .allow : .openExternally
    }
}
