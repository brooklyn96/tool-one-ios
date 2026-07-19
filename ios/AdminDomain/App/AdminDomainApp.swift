import SwiftUI

@main
struct AdminDomainApp: App {
    @StateObject private var router = AppRouter()
    @State private var isPaired: Bool
    private let environment: AppEnvironment
    private let keychain: KeychainStore
    private let api: APIClient
    private let cache: SnapshotCache?
    private let session: SessionManager

    init() {
        let environment = AppEnvironment.current
        let keychain = KeychainStore(service: "com.beyondk.admindomain")
        let session = SessionManager(baseURL: environment.baseURL, keychain: keychain)
        self.environment = environment
        self.keychain = keychain
        self.session = session
        self.api = APIClient(baseURL: environment.baseURL, accessToken: { try await session.accessToken() })
        self.cache = try? SnapshotCache()
        _isPaired = State(initialValue: (try? keychain.read(account: "refresh-token")) != nil)
    }

    var body: some Scene {
        WindowGroup {
            ToolOneLaunchGate {
                if isPaired {
                    ToolOneRootCoordinator(router: router, environment: environment, api: api, cache: cache, keychain: keychain) {
                        await session.reset()
                        isPaired = false
                    }
                } else {
                    PairingView(api: APIClient(baseURL: environment.baseURL), keychain: keychain) { isPaired = true }
                }
            }
        }
    }
}
