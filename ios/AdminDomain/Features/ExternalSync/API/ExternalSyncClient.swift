import Foundation

extension Notification.Name {
    static let externalSyncSessionInvalid = Notification.Name("ExternalSyncSessionInvalid")
}

actor ExternalSyncClient {
    static let productionURL = URL(string: "https://update.deal-sync.online")!
    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainStore
    private var accessToken: String?
    private var accessExpiry: Date?
    private var user: ExternalUser?
    private var refreshTask: Task<ExternalSession, Error>?
    private let refreshAccount = "external-sync-refresh-token"

    init(baseURL: URL = productionURL, session: URLSession = .shared, keychain: KeychainStore) {
        self.baseURL = baseURL; self.session = session; self.keychain = keychain
    }

    func currentUser() -> ExternalUser? { user }
    func hasStoredSession() -> Bool { (try? keychain.read(account: refreshAccount)) != nil }

    func login(username: String, password: String) async throws -> ExternalUser {
        let value: ExternalSession = try await raw("/api/mobile/v2/auth/login", method: "POST",
            body: ["username": username, "password": password, "clientLabel": "Tool One iOS"], authenticated: false)
        try persist(value); return value.user
    }

    func forgotPassword(username: String) async throws -> String {
        struct Body: Encodable { let username: String }
        struct Result: Decodable { let accepted: Bool; let message: String }
        let result: Result = try await raw(
            "/api/mobile/v2/auth/forgot-password",
            method: "POST",
            body: Body(username: username),
            authenticated: false
        )
        return result.message
    }

    func resetPassword(token: String, newPassword: String) async throws {
        struct Body: Encodable { let token: String; let newPassword: String }
        struct Result: Decodable { let reset: Bool; let user: ExternalUser }
        let _: Result = try await raw(
            "/api/mobile/v2/auth/reset-password",
            method: "POST",
            body: Body(token: token, newPassword: newPassword),
            authenticated: false
        )
    }

    func restore() async throws -> ExternalUser {
        _ = try await refresh()
        let me: ExternalMe = try await send("/api/mobile/v2/auth/me")
        user = me.user; return me.user
    }

    func logout() async {
        if let refresh = try? keychain.read(account: refreshAccount) {
            let _: LogoutResult? = try? await raw("/api/mobile/v2/auth/logout", method: "POST",
                body: ["refreshToken": refresh], authenticated: false)
        }
        clear()
    }

    func send<Response: Decodable, Body: Encodable>(
        _ path: String, method: String = "GET", body: Body? = Optional<String>.none,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        if accessToken == nil || (accessExpiry?.timeIntervalSinceNow ?? 0) < 30 { _ = try await refresh() }
        do { return try await raw(path, method: method, body: body, authenticated: true, idempotencyKey: idempotencyKey) }
        catch let problem as ExternalProblem where problem.code == "AUTH_SESSION_INVALID" {
            _ = try await refresh()
            return try await raw(path, method: method, body: body, authenticated: true, idempotencyKey: idempotencyKey)
        }
    }

    private func refresh() async throws -> ExternalSession {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = try keychain.read(account: refreshAccount) else { throw URLError(.userAuthenticationRequired) }
        let task = Task { [self] in
            let value: ExternalSession = try await raw("/api/mobile/v2/auth/refresh", method: "POST",
                body: ["refreshToken": refreshToken], authenticated: false)
            try persist(value); return value
        }
        refreshTask = task; defer { refreshTask = nil }
        do { return try await task.value } catch { clear(notify: true); throw error }
    }

    private func persist(_ value: ExternalSession) throws {
        try keychain.save(value.refreshToken, account: refreshAccount)
        accessToken = value.accessToken; accessExpiry = value.accessTokenExpiresAt; user = value.user
    }
    func clear(notify: Bool = false) {
        try? keychain.delete(account: refreshAccount); accessToken = nil; accessExpiry = nil; user = nil
        if notify { NotificationCenter.default.post(name: .externalSyncSessionInvalid, object: nil) }
    }

    private func raw<Response: Decodable, Body: Encodable>(
        _ path: String, method: String, body: Body?, authenticated: Bool, idempotencyKey: String? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL), url.scheme == "https", url.host == baseURL.host else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if authenticated, let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body { request.httpBody = try JSONEncoder.api.encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let problem = try? JSONDecoder.api.decode(ExternalProblemEnvelope.self, from: data).error { throw problem }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.api.decode(ExternalEnvelope<Response>.self, from: data).data
    }
}
