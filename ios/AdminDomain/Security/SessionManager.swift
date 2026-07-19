import Foundation

actor SessionManager {
    private let baseURL: URL
    private let keychain: KeychainStore
    private var current: SessionTokens?
    private var inFlight: Task<SessionTokens, Error>?

    init(baseURL: URL, keychain: KeychainStore) {
        self.baseURL = baseURL
        self.keychain = keychain
    }

    func accessToken() async throws -> String? {
        if let current, current.accessExpiresAt.timeIntervalSinceNow > 30 { return current.accessToken }
        if let inFlight { return try await inFlight.value.accessToken }
        let storedRefreshToken = try keychain.read(account: "refresh-token")
        guard let refreshToken = current?.refreshToken ?? storedRefreshToken else { return nil }

        let task = Task<SessionTokens, Error> { [baseURL, keychain] in
            let api = APIClient(baseURL: baseURL)
            let tokens: SessionTokens = try await api.send(
                "/v1/auth/refresh",
                method: "POST",
                body: RefreshBody(refreshToken: refreshToken),
                authenticated: false
            )
            try keychain.save(tokens.refreshToken, account: "refresh-token")
            try keychain.save(tokens.deviceId, account: "device-id")
            return tokens
        }
        inFlight = task
        defer { inFlight = nil }
        do {
            let tokens = try await task.value
            current = tokens
            return tokens.accessToken
        } catch let problem as APIProblem where problem.status == 401 {
            try? keychain.delete(account: "refresh-token")
            current = nil
            throw problem
        }
    }

    func reset() {
        inFlight?.cancel()
        inFlight = nil
        current = nil
    }

    private struct RefreshBody: Encodable { let refreshToken: String }
}
