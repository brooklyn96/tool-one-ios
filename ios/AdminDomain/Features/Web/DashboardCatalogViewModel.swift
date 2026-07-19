import Foundation

@MainActor
final class DashboardCatalogViewModel: ObservableObject {
    @Published private(set) var entries: [DashboardEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?

    private let api: APIClient
    private let cache: SnapshotCache?
    private var loadedCache = false

    init(api: APIClient, cache: SnapshotCache?) {
        self.api = api
        self.cache = cache
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if !loadedCache {
            loadedCache = true
            if let cached: DashboardCatalogResponse = try? await cache?.load(DashboardCatalogResponse.self, key: "dashboard-catalog") {
                entries = DashboardCatalogValidator.validated(cached.items)
                isStale = !entries.isEmpty
            }
        }

        do {
            let response: DashboardCatalogResponse = try await api.send("/v1/dashboards")
            let validated = DashboardCatalogValidator.validated(response.items)
            let safeResponse = DashboardCatalogResponse(items: validated, timestamp: response.timestamp)
            entries = validated
            isStale = false
            errorMessage = nil
            try? await cache?.save(safeResponse, key: "dashboard-catalog")
        } catch {
            isStale = !entries.isEmpty
            errorMessage = error.localizedDescription
        }
    }
}
