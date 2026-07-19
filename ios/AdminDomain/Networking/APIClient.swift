import Foundation

struct APIProblem: Decodable, Error {
    let title: String
    let status: Int
    let code: String
    let detail: String?
    let retryAfterSeconds: Int?
}

extension APIProblem: LocalizedError {
    var errorDescription: String? { detail ?? title }
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let accessToken: () async throws -> String?

    init(baseURL: URL, session: URLSession = .shared, accessToken: @escaping () async throws -> String? = { nil }) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
    }

    func send<Response: Decodable, Body: Encodable>(_ path: String, method: String = "GET", body: Body? = Optional<String>.none, authenticated: Bool = true, idempotencyKey: String? = nil) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL), url.scheme == "https", url.host == baseURL.host else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            request.httpBody = try JSONEncoder.api.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token = try await accessToken() else {
                throw APIProblem(title: "Sign in required", status: 401, code: "unauthorized", detail: nil, retryAfterSeconds: nil)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw (try? JSONDecoder.api.decode(APIProblem.self, from: data)) ?? APIProblem(title: "Server error", status: http.statusCode, code: "http_error", detail: nil, retryAfterSeconds: nil)
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try JSONDecoder.api.decode(Response.self, from: data)
    }
}

struct EmptyResponse: Codable {}

extension JSONDecoder {
    static var api: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .custom(ISO8601DateCoding.decode)
        return value
    }
}

extension JSONEncoder {
    static var api: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }
}
