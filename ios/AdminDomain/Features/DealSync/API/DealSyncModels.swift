import Foundation

enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
    var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return value ? "Có" : "Không"
        case .object, .array: return "Chi tiết"
        case .null: return "—"
        }
    }
}

struct DealSyncEnvelope<Value: Decodable>: Decodable {
    let apiVersion: String
    let minimumAppVersion: String?
    let serverTime: Date?
    let requestId: String
    let data: Value
}

struct DealSyncCollection<Item: Codable & Identifiable>: Codable {
    let items: [Item]
    let nextCursor: String?
}

struct DealSyncProblem: Decodable, Error, LocalizedError, Equatable {
    let code: String
    let message: String
    let fieldErrors: [String: [String]]?
    let requestId: String?
    var errorDescription: String? { message }
}

struct DealSyncCapabilities: Codable, Equatable {
    let canSync: Bool
    let canSubmitDeal: Bool
    let canCreateSheet: Bool
    let linkedToUserId: String?
}

struct DealSyncAccount: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let name: String?
    let image: URL?
    let isAdmin: Bool
    let capabilities: DealSyncCapabilities
    var displayName: String { name?.isEmpty == false ? name! : email }
}

struct DealSyncSessionPayload: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: TimeInterval
    let account: DealSyncAccount
}

struct DealSyncOAuthStart: Decodable, Equatable {
    let transactionId: String
    let pollingSecret: String
    let authorizationURL: URL
    let expiresAt: Date
    let pollAfterMs: Int

    private enum CodingKeys: String, CodingKey {
        case transactionId, pollingSecret, expiresAt, pollAfterMs
        case authorizationURL = "authorizationUrl"
    }
}

enum DealSyncOAuthStatus: Equatable {
    case pending(retryAfterMilliseconds: Int)
    case complete(DealSyncSessionPayload)
}

struct DealSyncOAuthPollResponse: Decodable, Equatable {
    let status: DealSyncOAuthStatus

    private enum PendingKeys: String, CodingKey { case status, retryAfterMs }

    init(from decoder: Decoder) throws {
        if let pending = try? decoder.container(keyedBy: PendingKeys.self),
           (try? pending.decode(String.self, forKey: .status)) == "pending" {
            status = .pending(retryAfterMilliseconds: try pending.decode(Int.self, forKey: .retryAfterMs))
            return
        }
        status = .complete(try DealSyncSessionPayload(from: decoder))
    }
}

enum DealSyncOAuthError: Error, Equatable, LocalizedError {
    case offline
    case cancelled
    case callbackUnavailable
    case expired
    case accountNotAllowed
    case sessionClaimed
    case bindingMismatch
    case serverUnavailable
    case unknown

    init(problemCode: String) {
        switch problemCode {
        case "account_not_allowed", "account_disabled": self = .accountNotAllowed
        case "authorization_transaction_expired", "authorization_code_expired": self = .expired
        case "authorization_transaction_used", "authorization_state_used": self = .sessionClaimed
        case "authorization_transaction_binding_mismatch", "authorization_code_binding_mismatch": self = .bindingMismatch
        case let code where code.hasPrefix("http_5"): self = .serverUnavailable
        case "internal_error": self = .serverUnavailable
        default: self = .unknown
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline: return "Không có kết nối mạng. Kiểm tra mạng rồi thử lại."
        case .cancelled: return "Bạn đã đóng đăng nhập Google."
        case .callbackUnavailable: return "Đang tiếp tục đăng nhập bằng trình duyệt."
        case .expired: return "Phiên đăng nhập đã hết hạn. Vui lòng bắt đầu lại."
        case .accountNotAllowed: return "Tài khoản này không được phép sử dụng Deal Sync."
        case .sessionClaimed: return "Phiên đăng nhập đã được sử dụng. Vui lòng bắt đầu lại."
        case .bindingMismatch: return "Phiên đăng nhập không thuộc thiết bị này."
        case .serverUnavailable: return "Deal Sync đang tạm gián đoạn. Vui lòng thử lại sau."
        case .unknown: return "Chưa thể hoàn tất đăng nhập Deal Sync. Vui lòng thử lại."
        }
    }
}

struct DealSyncMePayload: Decodable {
    let account: DealSyncAccount
}

struct DealSyncOperation: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let state: String
    let progress: Int
    let currentItem: String?
    let result: JSONValue?
    let errorCode: String?
    let createdAt: Date
    let updatedAt: Date
    var isTerminal: Bool { ["SUCCEEDED", "FAILED", "CANCELLED"].contains(state) }
}

struct DealSyncSchedule: Codable, Identifiable, Hashable {
    let id: String
    let date: String?
    let kolName: String?
    let spreadsheetId: String?
    let poolSpreadsheetId: String?
    let externalSpreadsheetId: String?
    let liveItemIdSpreadsheetId: String?
    let brandPoolSheetUrl: String?
    let bdCheckColumn: String?
    let isArchived: Bool?
    var title: String { [date, kolName].compactMap { $0 }.joined(separator: " · ") }
}

struct DealSyncDestination: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let spreadsheetId: String
    let sheetKeyword: String?
    let skipBkAms: Bool?
    let shopIds: [String]?
    let fromLinkedUser: Bool?

    enum CodingKeys: String, CodingKey { case id, name, spreadsheetId, sheetKeyword, skipBkAms, shopIds, fromLinkedUser }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id); name = try box.decode(String.self, forKey: .name); spreadsheetId = try box.decode(String.self, forKey: .spreadsheetId)
        sheetKeyword = try box.decodeIfPresent(String.self, forKey: .sheetKeyword); skipBkAms = try box.decodeIfPresent(Bool.self, forKey: .skipBkAms); fromLinkedUser = try box.decodeIfPresent(Bool.self, forKey: .fromLinkedUser)
        if let values = try? box.decodeIfPresent([String].self, forKey: .shopIds) { shopIds = values }
        else if let raw = try? box.decodeIfPresent(String.self, forKey: .shopIds), let data = raw.data(using: .utf8) { shopIds = try? JSONDecoder().decode([String].self, from: data) }
        else { shopIds = nil }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self); try box.encode(id, forKey: .id); try box.encode(name, forKey: .name); try box.encode(spreadsheetId, forKey: .spreadsheetId); try box.encodeIfPresent(sheetKeyword, forKey: .sheetKeyword); try box.encodeIfPresent(skipBkAms, forKey: .skipBkAms); try box.encodeIfPresent(shopIds, forKey: .shopIds); try box.encodeIfPresent(fromLinkedUser, forKey: .fromLinkedUser)
    }
}

struct DealSyncSubmission: Codable, Identifiable, Hashable {
    let id: String
    let spreadsheetId: String?
    let sheetName: String?
    let scheduleId: String?
    let isIgnored: Bool?
    let isSkipped: Bool?
    let lastProcessedRow: Int?
    let createdAt: Date?
    let userEmail: String?
    let scheduleDate: Date?
    let scheduleKol: String?
}

struct DealSyncProjectAuthorization: Codable, Identifiable, Hashable {
    let projectId: String
    let name: String
    let authorized: Bool
    let expired: Bool
    let expiresAt: Date?
    let authorizationUrl: String
    var id: String { projectId }
}

struct DealSyncTier2Session: Codable, Identifiable, Hashable {
    let id: String
    let month: Int
    let year: Int
    let poolSpreadsheetId: String?
    let label: String?
}

struct DealSyncProcessRecovery: Codable {
    let hasInterrupted: Bool
    let sessions: [DealSyncProcessSession]
}

struct DealSyncProcessSession: Codable, Identifiable, Hashable {
    struct RowProgress: Codable, Hashable { let completed: Int; let pending: Int; let total: Int }
    let id: String
    let status: String
    let userId: String?
    let scheduleId: String?
    let startedAt: Date?
    let lastActivityAt: Date?
    let rowProgress: RowProgress?
}

struct DealSyncGenericItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let name: String?
    let email: String?
    let status: String?
    let detail: String?
    var displayTitle: String { title ?? name ?? email ?? id }
}

struct DealSyncMasterSheet: Codable { let id: String?; let spreadsheetId: String; let sheetName: String }
struct DealSyncTabs: Codable { let sheets: [String] }
struct DealSyncTransferTarget: Codable, Identifiable, Hashable { let id: String; let name: String?; let email: String; var title: String { name?.isEmpty == false ? name! : email } }
struct DealSyncAdminUser: Codable, Identifiable, Hashable {
    struct Counts: Codable, Hashable { let destinations: Int?; let sheetSubmissions: Int? }
    let id: String; let name: String?; let email: String?; let canSubmitDeal: Bool?; let canCreateSheet: Bool?; let canSync: Bool?; let isBanned: Bool?; let targetSheetName: String?; let linkedToUserId: String?; let _count: Counts?
    var title: String { name?.isEmpty == false ? name! : (email ?? id) }
}
struct DealSyncTransferSheet: Codable, Identifiable, Hashable { let id: String; let name: String; let spreadsheetId: String }
struct DealSyncTransfer: Codable, Identifiable, Hashable {
    let id: String; let fromUserId: String; let toUserId: String; let status: String; let sheets: [DealSyncTransferSheet]?; let createdAt: Date?
}
struct DealSyncTransfers: Codable { let sent: [DealSyncTransfer]; let pendingReview: [DealSyncTransfer]? }

struct DealSyncDuplicateScanResult: Codable {
    struct Label: Codable, Identifiable, Hashable {
        struct Row: Codable, Identifiable, Hashable {
            let rowIndex: Int; let sheetRowIndex: Int; let brandCode: String?; let shopId: String?; let review: String?; let brandName: String?; let productName: String?
            var id: Int { sheetRowIndex }
            var title: String { [brandName, productName, brandCode].compactMap { $0 }.first { !$0.isEmpty } ?? "Dòng \(sheetRowIndex)" }
        }
        let label: String; let baseBrandCode: String; let shopId: String; let plusVariants: [String]; let matchedRows: [Row]
        var id: String { label }
    }
    struct ColumnMap: Codable { let review: Int? }
    let labels: [Label]; let sheetName: String?; let dealListSheetName: String?; let colMap: ColumnMap?; let fromCache: Bool?; let message: String?
}

struct DealSyncDuplicateSelection: Codable, Hashable {
    let labelKey: String; let brandCodeWithPlus: String; let rowIndex: Int; let sheetRowIndex: Int; let reviewColIndex: Int?; let reviewOverride: String?
}

struct DealSyncTheme: Codable, Identifiable, Hashable { let id: String; let name: String?; let enabled: Bool; var title: String { name ?? id } }
struct DealSyncAdminProject: Codable, Identifiable, Hashable { let id: String; let code: String; let name: String; let clientId: String?; let isActive: Bool; let priority: Int; let createdAt: Date?; let updatedAt: Date? }
struct DealSyncAdminProjects: Codable { let success: Bool; let projects: [DealSyncAdminProject] }

struct DealSyncEndpoint<Response: Decodable> {
    let path: String
    let method: String
    init(_ path: String, method: String = "GET") { self.path = path; self.method = method }
}

struct DealSyncEmptyBody: Codable {}
struct DealSyncEmptyResult: Codable {}
