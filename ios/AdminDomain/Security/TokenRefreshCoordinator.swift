import Foundation

struct SessionTokens: Codable { let deviceId: String; let accessToken: String; let refreshToken: String; let accessExpiresAt: Date; let refreshExpiresAt: Date }

actor TokenRefreshCoordinator {
    private var current: SessionTokens?
    private var inFlight: Task<SessionTokens, Error>?
    func install(_ tokens: SessionTokens) { current = tokens }
    func accessToken(refresh: @escaping @Sendable (String) async throws -> SessionTokens) async throws -> String {
        if let current, current.accessExpiresAt.timeIntervalSinceNow > 30 { return current.accessToken }
        if let inFlight { return try await inFlight.value.accessToken }
        guard let credential = current?.refreshToken else { throw APIProblem(title: "Sign in required", status: 401, code: "unauthorized", detail: nil, retryAfterSeconds: nil) }
        let task = Task { try await refresh(credential) }; inFlight = task
        defer { inFlight = nil }
        let tokens = try await task.value; current = tokens; return tokens.accessToken
    }
    func clear() { current = nil; inFlight?.cancel(); inFlight = nil }
}
