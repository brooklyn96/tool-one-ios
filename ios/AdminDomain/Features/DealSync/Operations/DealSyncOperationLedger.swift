import Foundation

@MainActor
final class DealSyncOperationLedger: ObservableObject {
    @Published private(set) var operationIDs: [String]
    private let key: String
    private let defaults: UserDefaults
    init(accountID: String, defaults: UserDefaults = .standard) {
        key = "deal-sync-operations-\(accountID)"
        self.defaults = defaults
        operationIDs = defaults.stringArray(forKey: key) ?? []
    }
    func register(_ id: String) {
        operationIDs.removeAll { $0 == id }; operationIDs.insert(id, at: 0)
        operationIDs = Array(operationIDs.prefix(30)); defaults.set(operationIDs, forKey: key)
    }
    func complete(_ id: String) {
        operationIDs.removeAll { $0 == id }; defaults.set(operationIDs, forKey: key)
    }
    func clear() { operationIDs = []; defaults.removeObject(forKey: key) }
}

struct DealSyncCachedSnapshot<Value: Codable>: Codable {
    let savedAt: Date
    let value: Value
}

actor DealSyncSnapshotStore {
    private let cache: SnapshotCache
    init(cache: SnapshotCache) { self.cache = cache }
    func save<Value: Codable>(_ value: Value, accountID: String, resource: String) async throws {
        try await cache.save(DealSyncCachedSnapshot(savedAt: Date(), value: value), key: "deal-sync-\(accountID)-\(resource)")
    }
    func load<Value: Codable>(_ type: Value.Type, accountID: String, resource: String) async throws -> DealSyncCachedSnapshot<Value>? {
        try await cache.load(DealSyncCachedSnapshot<Value>.self, key: "deal-sync-\(accountID)-\(resource)")
    }
}
