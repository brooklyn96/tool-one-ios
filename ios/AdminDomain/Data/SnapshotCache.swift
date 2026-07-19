import Foundation

actor SnapshotCache {
    private let directory: URL
    init(fileManager: FileManager = .default) throws {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = base.appendingPathComponent("AdminDomainSnapshots", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func save<T: Encodable>(_ value: T, key: String) throws { try JSONEncoder.api.encode(value).write(to: fileURL(key), options: .atomic) }
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? { let url = fileURL(key); guard FileManager.default.fileExists(atPath: url.path) else { return nil }; return try JSONDecoder.api.decode(type, from: Data(contentsOf: url)) }
    func removeAll() throws { try? FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    private func fileURL(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_")).appendingPathExtension("json") }
}
