import Foundation

struct ExternalEnvelope<Value: Decodable>: Decodable {
    let data: Value
    let meta: ExternalMeta
}
struct ExternalMeta: Decodable { let requestId: String; let serverTime: Date }
struct ExternalProblemEnvelope: Decodable { let error: ExternalProblem }
struct ExternalProblem: Decodable, Error, LocalizedError {
    let code: String
    let message: String
    let fieldErrors: [String: String]?
    let requestId: String
    var errorDescription: String? { message }
}

struct ExternalUser: Codable, Identifiable, Hashable {
    let id: String
    var username: String
    var isAdmin: Bool
}
struct ExternalSession: Decodable {
    let user: ExternalUser
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}
struct ExternalMe: Decodable { let user: ExternalUser }

struct ExternalPage<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

struct DealListDTO: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var sourceSpreadsheetId: String
    var sourceSheetName: String
    var sourceColumnMapping: [String: String]?
    var targetSpreadsheetId: String
    var targetSheetName: String
    var targetColumnMapping: [String: String]?
    var livestreamOn: String?
    var livestreamDate: String?
    var reviewAtcStopAt: Date?
    var stopProcessingAt: Date?
    var isActive: Bool
    var lastSyncAt: Date?
    var syncCount: Int
    var createdAt: Date
    var updatedAt: Date
}
struct DealListDetailDTO: Decodable {
    let id: String; let name: String; let sourceSpreadsheetId: String; let sourceSheetName: String
    let sourceColumnMapping: [String: String]?; let targetSpreadsheetId: String; let targetSheetName: String
    let targetColumnMapping: [String: String]?; let livestreamOn: String?; let livestreamDate: String?
    let reviewAtcStopAt: Date?; let stopProcessingAt: Date?; let isActive: Bool; let lastSyncAt: Date?
    let syncCount: Int; let createdAt: Date; let updatedAt: Date; let history: [ProcessLogDTO]
}
struct DealListInputDTO: Encodable {
    var name = ""; var sourceSpreadsheetId = ""; var sourceSheetName = ""
    var sourceColumnMapping: [String: String]?; var targetSpreadsheetId = ""; var targetSheetName = ""
    var targetColumnMapping: [String: String]?; var livestreamOn: String?; var livestreamDate: String?
    var reviewAtcStopAt: Date?; var stopProcessingAt: Date?
}

struct ProcessLogDTO: Codable, Identifiable {
    let id: String; let dealListId: String?; let action: String; let status: String; let message: String
    let processedRecords: Int?; let updatedRecords: Int?; let errorMessage: String?
    let startedAt: Date; let completedAt: Date?; let createdAt: Date
}
struct LogDetailDTO: Decodable, Identifiable {
    let id: String; let dealListId: String?; let action: String; let status: String; let message: String
    let processedRecords: Int?; let updatedRecords: Int?; let errorMessage: String?
    let startedAt: Date; let completedAt: Date?; let createdAt: Date
}
struct ConditionDTO: Codable, Identifiable, Hashable {
    let id: String; var name: String; var columnGroups: [String]; var description: String?
    var isActive: Bool; let createdAt: Date; let updatedAt: Date
}
struct ConditionsDTO: Decodable { let items: [ConditionDTO]; let columnGroupOptions: [String] }
struct ConditionInputDTO: Encodable { let name: String; let columnGroups: [String]; let description: String? }
struct ConditionUpdateDTO: Encodable { let name: String?; let columnGroups: [String]?; let description: String?; let isActive: Bool? }

struct AdminUserDTO: Decodable, Identifiable {
    let id: String; let username: String; let email: String?; let isAdmin: Bool; let isActive: Bool; let createdAt: Date
}
struct UserInputDTO: Encodable { let username: String; let password: String; let email: String?; let isAdmin: Bool }
struct UserUpdateDTO: Encodable { let username: String?; let email: String?; let password: String?; let isAdmin: Bool?; let isActive: Bool? }

struct DashboardDTO: Codable {
    struct Count: Codable { let total: Int; let active: Int }
    struct Processes: Codable { let total: Int; let successful: Int; let failed: Int }
    let dealLists: Count; let processes: Processes; let users: Count?; let scheduler: SchedulerDTO
    let lastSync: ProcessLogDTO?; let recentActivity: [ProcessLogDTO]; let generatedAt: Date
    var isReadyEmpty: Bool { dealLists.total == 0 }
}
struct SchedulerDTO: Codable { let isRunning: Bool; let activeDealLists: Int }
struct SystemDTO: Decodable {
    struct Memory: Decodable { let totalBytes: Int64; let usedBytes: Int64; let availableBytes: Int64; let percentUsed: Int }
    let memory: Memory; let uptimeSeconds: Int; let scheduler: SchedulerDTO; let lastSync: ProcessLogDTO?
    let leases: [LeaseDTO]; let generatedAt: Date
}
struct LeaseDTO: Decodable, Identifiable { var id: String { name }; let name: String; let ownerId: String; let acquiredAt: Date; let expiresAt: Date }
struct SheetDiscoveryDTO: Decodable { let spreadsheetId: String; let sheets: [String] }
struct OperationDTO: Decodable, Identifiable {
    let id: String; let kind: String; let status: String; let progress: Int; let errorCode: String?
    let errorMessage: String?; let createdAt: Date; let startedAt: Date?; let completedAt: Date?
}
struct DeleteResult: Decodable { let deleted: Bool }
struct ChangeResult: Decodable { let changed: Bool }
struct LogoutResult: Decodable { let loggedOut: Bool }
struct ResetPreviewDTO: Decodable { let requiresConfirmation: Bool; let existingCount: Int?; let defaultCount: Int? }
struct ClearLogsDTO: Decodable { let requiresConfirmation: Bool; let count: Int?; let deleted: Int?; let olderThanDays: Int }
