import Foundation

enum NativeProgramID: String, Codable, CaseIterable, Identifiable {
    case dealSync = "deal-sync"
    case externalSync = "external-sync"

    var id: String { rawValue }
}
struct ProgramSnapshot: Codable, Identifiable, Equatable {
    let id: NativeProgramID
    let title: String
    let state: ProgramState
    let stale: Bool
    let updatedAt: Date
    let summary: [ProgramMetric]
    let collections: [ProgramCollection]
    let partial: Bool
    let timestamp: Date

    func cachedCopy() -> ProgramSnapshot {
        ProgramSnapshot(id: id, title: title, state: state, stale: true, updatedAt: updatedAt, summary: summary, collections: collections, partial: partial, timestamp: timestamp)
    }

    var workspaceState: WorkspaceProgramState {
        if stale { return .cached }
        if partial { return .attention }
        switch state {
        case .online: return .ready
        case .degraded: return .attention
        case .offline, .unknown: return .unavailable
        }
    }
}

enum WorkspaceProgramState: Equatable {
    case ready
    case cached
    case attention
    case unavailable
}

enum ProgramState: String, Codable {
    case online, degraded, offline, unknown
}

struct ProgramMetric: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let tone: Tone

    enum Tone: String, Codable { case neutral, success, warning, critical }
}

struct ProgramCollection: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let total: Int
    let nextCursor: String?
    let items: [ProgramRecord]
}

struct ProgramRecord: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let status: String
    let updatedAt: Date
    let fields: [ProgramField]
}

struct ProgramField: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let value: String
    let kind: Kind

    var id: String { key }
    enum Kind: String, Codable { case text, number, date, boolean, status }
}
