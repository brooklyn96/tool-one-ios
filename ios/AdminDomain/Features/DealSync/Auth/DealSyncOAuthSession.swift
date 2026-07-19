import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class DealSyncOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?

    private enum Attempt {
        case success(DealSyncSessionPayload)
        case failure(DealSyncOAuthError)
    }

    func authorize(start: DealSyncOAuthStart, client: DealSyncClient) async throws -> DealSyncSessionPayload {
        let result = await withTaskGroup(of: Attempt.self, returning: Attempt.self) { group in
            group.addTask { [weak self] in
                guard let self else { return .failure(.callbackUnavailable) }
                do {
                    let code = try await self.authorizationCode(at: start.authorizationURL)
                    return .success(try await client.exchangeAuthorizationCode(code))
                } catch {
                    return .failure(Self.map(error))
                }
            }
            group.addTask {
                do { return .success(try await Self.pollUntilComplete(start: start, client: client)) }
                catch { return .failure(Self.map(error)) }
            }

            var lastFailure = DealSyncOAuthError.unknown
            while let attempt = await group.next() {
                switch attempt {
                case .success:
                    group.cancelAll()
                    return attempt
                case .failure(.cancelled):
                    group.cancelAll()
                    return attempt
                case .failure(let error):
                    lastFailure = error
                }
            }
            return .failure(lastFailure)
        }

        switch result {
        case .success(let payload): return payload
        case .failure(let error): throw error
        }
    }

    private func authorizationCode(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let startedAt = Date()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "admindomain") { [weak self] callback, error in
                Task { @MainActor in
                    self?.webSession = nil
                    if let error {
                        let mapped = Self.mapWebAuthentication(error, elapsed: Date().timeIntervalSince(startedAt))
                        if mapped == .callbackUnavailable { _ = await UIApplication.shared.open(url) }
                        continuation.resume(throwing: mapped)
                        return
                    }
                    guard let callback,
                          callback.host == "oauth", callback.path == "/deal-sync",
                          let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value,
                          !code.isEmpty else {
                        continuation.resume(throwing: DealSyncOAuthError.callbackUnavailable)
                        return
                    }
                    continuation.resume(returning: code)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            guard session.start() else {
                webSession = nil
                Task { @MainActor in
                    _ = await UIApplication.shared.open(url)
                    continuation.resume(throwing: DealSyncOAuthError.callbackUnavailable)
                }
                return
            }
        }
    }

    private static func pollUntilComplete(start: DealSyncOAuthStart, client: DealSyncClient) async throws -> DealSyncSessionPayload {
        var delayMilliseconds = max(start.pollAfterMs, 250)
        while Date() < start.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            do {
                switch try await client.pollAuthorization(start) {
                case .complete(let payload): return payload
                case .pending(let serverDelay):
                    delayMilliseconds = min(max(serverDelay, delayMilliseconds * 2), 3_000)
                }
            } catch {
                let mapped = map(error)
                if mapped == .serverUnavailable || mapped == .offline {
                    delayMilliseconds = min(delayMilliseconds * 2, 3_000)
                    continue
                }
                throw mapped
            }
        }
        throw DealSyncOAuthError.expired
    }

    private static func mapWebAuthentication(_ error: Error, elapsed: TimeInterval) -> DealSyncOAuthError {
        if let value = error as? ASWebAuthenticationSessionError, value.code == .canceledLogin {
            return elapsed < 1 ? .callbackUnavailable : .cancelled
        }
        return .callbackUnavailable
    }

    private static func map(_ error: Error) -> DealSyncOAuthError {
        if let error = error as? DealSyncOAuthError { return error }
        if let problem = error as? DealSyncProblem { return DealSyncOAuthError(problemCode: problem.code) }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut: return .offline
            default: return .serverUnavailable
            }
        }
        return .unknown
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

@MainActor
final class DealSyncSessionStore: ObservableObject {
    @Published var account: DealSyncAccount?
    @Published var isRestoring = true
    @Published var isWorking = false
    @Published var error: String?
    let client: DealSyncClient
    private let oauth = DealSyncOAuthSession()

    init(client: DealSyncClient) { self.client = client }

    func restore() async {
        defer { isRestoring = false }
        guard await client.hasStoredSession() else { return }
        do { account = try await client.restore() }
        catch { self.error = ToolOneFriendlyError.message(for: error) }
    }

    func login() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let start = try await client.startAuthorization()
            let payload = try await oauth.authorize(start: start, client: client)
            account = try await client.commitAuthorization(payload)
        } catch let oauthError as DealSyncOAuthError {
            error = oauthError.errorDescription
        } catch {
            error = ToolOneFriendlyError.message(for: error)
        }
    }

    func logout() async {
        await client.logout()
        account = nil
    }
}
