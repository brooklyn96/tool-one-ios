import Foundation

extension Notification.Name {
    static let dealSyncSessionInvalid = Notification.Name("DealSyncSessionInvalid")
}

actor DealSyncClient {
    static let productionURL = URL(string: "https://traketqua.deal-sync.online")!
    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainStore
    private let refreshAccount = "deal-sync-refresh-token"
    private let installationIDAccount = "deal-sync-installation-id"
    private let installationNonceAccount = "deal-sync-installation-nonce"
    private var accessToken: String?
    private var accessExpiry: Date?
    private var account: DealSyncAccount?
    private var refreshTask: Task<DealSyncSessionPayload, Error>?

    init(baseURL: URL = productionURL, session: URLSession = .shared, keychain: KeychainStore) {
        precondition(baseURL.scheme == "https" && baseURL.host == Self.productionURL.host)
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
    }

    func currentAccount() -> DealSyncAccount? { account }
    func hasStoredSession() -> Bool { (try? keychain.read(account: refreshAccount)) != nil }

    func startAuthorization() async throws -> DealSyncOAuthStart {
        struct Body: Encodable { let installationNonce: String; let callbackScheme: String }
        return try await raw(
            DealSyncEndpoint("/api/mobile/v2/auth/google/start", method: "POST"),
            body: Body(installationNonce: try installationNonce(), callbackScheme: "admindomain"),
            authenticated: false,
            idempotencyKey: UUID().uuidString,
            decodeEnvelope: false
        )
    }

    func pollAuthorization(_ start: DealSyncOAuthStart) async throws -> DealSyncOAuthStatus {
        struct Body: Encodable {
            let transactionId: String
            let pollingSecret: String
            let installationNonce: String
            let installationId: String
        }
        let response: DealSyncOAuthPollResponse = try await raw(
            DealSyncEndpoint("/api/mobile/v2/auth/google/status", method: "POST"),
            body: Body(
                transactionId: start.transactionId,
                pollingSecret: start.pollingSecret,
                installationNonce: try installationNonce(),
                installationId: try installationID()
            ),
            authenticated: false,
            idempotencyKey: UUID().uuidString,
            decodeEnvelope: false
        )
        return response.status
    }

    func exchangeAuthorizationCode(_ code: String) async throws -> DealSyncSessionPayload {
        struct Body: Encodable { let code: String; let installationNonce: String; let installationId: String }
        return try await raw(
            DealSyncEndpoint("/api/mobile/v2/auth/exchange", method: "POST"),
            body: Body(code: code, installationNonce: try installationNonce(), installationId: try installationID()),
            authenticated: false,
            idempotencyKey: UUID().uuidString,
            decodeEnvelope: false
        )
    }

    func commitAuthorization(_ payload: DealSyncSessionPayload) throws -> DealSyncAccount {
        try persist(payload)
        return payload.account
    }

    func restore() async throws -> DealSyncAccount {
        _ = try await refresh()
        let me: DealSyncMePayload = try await raw(DealSyncEndpoint("/api/mobile/v2/auth/me"), body: Optional<DealSyncEmptyBody>.none, authenticated: true, decodeEnvelope: false)
        account = me.account
        return me.account
    }

    func logout() async {
        if let token = try? keychain.read(account: refreshAccount) {
            struct Body: Encodable { let refreshToken: String }
            let _: DealSyncEmptyResult? = try? await raw(DealSyncEndpoint("/api/mobile/v2/auth/logout", method: "POST"), body: Body(refreshToken: token), authenticated: false, decodeEnvelope: false)
        }
        clear()
    }

    func send<Response: Decodable, Body: Encodable>(
        _ endpoint: DealSyncEndpoint<Response>, body: Body? = Optional<DealSyncEmptyBody>.none,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        if accessToken == nil || (accessExpiry?.timeIntervalSinceNow ?? 0) < 30 { _ = try await refresh() }
        let mutationKey = endpoint.method == "GET" ? nil : (idempotencyKey ?? UUID().uuidString)
        do { return try await raw(endpoint, body: body, authenticated: true, idempotencyKey: mutationKey, decodeEnvelope: true) }
        catch let problem as DealSyncProblem where ["access_token_invalid", "access_token_expired"].contains(problem.code) {
            _ = try await refresh()
            return try await raw(endpoint, body: body, authenticated: true, idempotencyKey: mutationKey, decodeEnvelope: true)
        }
    }

    private func refresh() async throws -> DealSyncSessionPayload {
        if let refreshTask { return try await refreshTask.value }
        guard let token = try keychain.read(account: refreshAccount) else { throw URLError(.userAuthenticationRequired) }
        struct Body: Encodable { let refreshToken: String }
        let task = Task { [self] in
            let payload: DealSyncSessionPayload = try await raw(DealSyncEndpoint("/api/mobile/v2/auth/refresh", method: "POST"), body: Body(refreshToken: token), authenticated: false, decodeEnvelope: false)
            try persist(payload)
            return payload
        }
        refreshTask = task
        defer { refreshTask = nil }
        do { return try await task.value }
        catch { clear(notify: true); throw error }
    }

    private func raw<Response: Decodable, Body: Encodable>(
        _ endpoint: DealSyncEndpoint<Response>, body: Body?, authenticated: Bool,
        idempotencyKey: String? = nil, decodeEnvelope: Bool
    ) async throws -> Response {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL), url.scheme == "https", url.host == baseURL.host else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if authenticated, let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body { request.httpBody = try JSONEncoder.api.encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let problem = try? JSONDecoder.api.decode(DealSyncProblem.self, from: data) { throw problem }
            throw DealSyncProblem(code: "http_\(http.statusCode)", message: "Không thể kết nối Deal Sync.", fieldErrors: nil, requestId: nil)
        }
        if decodeEnvelope, let envelope = try? JSONDecoder.api.decode(DealSyncEnvelope<Response>.self, from: data) { return envelope.data }
        return try JSONDecoder.api.decode(Response.self, from: data)
    }

    private func persist(_ payload: DealSyncSessionPayload) throws {
        try keychain.save(payload.refreshToken, account: refreshAccount)
        accessToken = payload.accessToken
        accessExpiry = Date().addingTimeInterval(payload.expiresIn)
        account = payload.account
    }
    private func installationID() throws -> String {
        if let value = try keychain.read(account: installationIDAccount) { return value }
        let value = UUID().uuidString; try keychain.save(value, account: installationIDAccount); return value
    }
    private func installationNonce() throws -> String {
        if let value = try keychain.read(account: installationNonceAccount) { return value }
        let value = UUID().uuidString + UUID().uuidString
        try keychain.save(value, account: installationNonceAccount); return value
    }
    private func clear(notify: Bool = false) {
        try? keychain.delete(account: refreshAccount)
        accessToken = nil; accessExpiry = nil; account = nil
        if notify { NotificationCenter.default.post(name: .dealSyncSessionInvalid, object: nil) }
    }
}
