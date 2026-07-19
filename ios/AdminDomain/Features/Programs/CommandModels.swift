import Foundation

struct CommandCatalogEnvelope: Decodable {
    let programId: NativeProgramID
    let commands: [ProgramCommand]
    let timestamp: Date
}

struct ProgramCommand: Decodable, Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let destructive: Bool
    let confirmation: String?
    let fields: [CommandField]
}

struct CommandField: Decodable, Identifiable {
    enum Kind: String, Decodable { case text, secure, number, boolean, date, select }
    struct Option: Decodable, Identifiable { let label: String; let value: String; var id: String { value } }
    let key: String
    let label: String
    let kind: Kind
    let required: Bool
    let placeholder: String?
    let options: [Option]?
    var id: String { key }
}

struct CommandResult: Decodable {
    enum Status: String, Decodable { case succeeded, accepted }
    let programId: NativeProgramID
    let commandId: String
    let status: Status
    let message: String
    let changed: Int
    let resourceId: String?
    let oauthURL: URL?
    let timestamp: Date
}

struct CommandEnvelope: Encodable { let input: [String: CommandValue] }
enum CommandValue: Encodable {
    case string(String), number(Double), boolean(Bool)
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .string(let value): try container.encode(value); case .number(let value): try container.encode(value); case .boolean(let value): try container.encode(value) }
    }
}
