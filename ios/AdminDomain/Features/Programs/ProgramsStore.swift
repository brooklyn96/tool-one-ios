import Foundation

@MainActor
final class ProgramsStore: ObservableObject {
    @Published private(set) var snapshots: [NativeProgramID: ProgramSnapshot] = [:]
    @Published private(set) var errors: [NativeProgramID: String] = [:]
    @Published private(set) var isLoading = false

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
            await loadCachedSnapshots()
        }

        async let deal = fetch(.dealSync)
        async let external = fetch(.externalSync)
        for result in await [deal, external] {
            switch result.result {
            case .success(let snapshot):
                snapshots[result.id] = snapshot
                errors[result.id] = nil
                try? await cache?.save(snapshot, key: cacheKey(result.id))
            case .failure(let error):
                errors[result.id] = error.localizedDescription
            }
        }
    }

    func applyExternalSync(_ summary: ExternalSyncLiveSummary) {
        let snapshot = summary.programSnapshot
        snapshots[.externalSync] = snapshot
        errors[.externalSync] = nil
        Task { try? await cache?.save(snapshot, key: cacheKey(.externalSync)) }
    }

    private func fetch(_ id: NativeProgramID) async -> LoadResult {
        do {
            let snapshot: ProgramSnapshot = try await api.send("/v1/programs/\(id.rawValue)")
            return LoadResult(id: id, result: .success(snapshot))
        } catch {
            return LoadResult(id: id, result: .failure(error))
        }
    }

    private func loadCachedSnapshots() async {
        for id in NativeProgramID.allCases {
            if let snapshot: ProgramSnapshot = try? await cache?.load(ProgramSnapshot.self, key: cacheKey(id)) {
                snapshots[id] = snapshot.cachedCopy()
            }
        }
    }

    private func cacheKey(_ id: NativeProgramID) -> String { "native-program-\(id.rawValue)" }

    private struct LoadResult {
        let id: NativeProgramID
        let result: Result<ProgramSnapshot, Error>
    }
}
