import SwiftUI

struct ToolOneRootCoordinator: View {
    @ObservedObject var router: AppRouter
    let environment: AppEnvironment
    let api: APIClient
    let cache: SnapshotCache?
    let keychain: KeychainStore
    let onUnpaired: () async -> Void

    @StateObject private var programsStore: ProgramsStore
    @StateObject private var externalSyncLiveStore: ExternalSyncLiveStore
    private let externalSyncClient: ExternalSyncClient
    private let dealSyncClient: DealSyncClient

    init(
        router: AppRouter,
        environment: AppEnvironment,
        api: APIClient,
        cache: SnapshotCache?,
        keychain: KeychainStore,
        onUnpaired: @escaping () async -> Void
    ) {
        self.router = router
        self.environment = environment
        self.api = api
        self.cache = cache
        self.keychain = keychain
        self.onUnpaired = onUnpaired
        let externalSyncClient = ExternalSyncClient(keychain: keychain)
        self.externalSyncClient = externalSyncClient
        self.dealSyncClient = DealSyncClient(keychain: keychain)
        _programsStore = StateObject(wrappedValue: ProgramsStore(api: api, cache: cache))
        _externalSyncLiveStore = StateObject(wrappedValue: ExternalSyncLiveStore(client: externalSyncClient, cache: cache))
    }

    @ViewBuilder
    var body: some View {
        switch router.mode {
        case .workspace:
            RootTabView(
                router: router,
                environment: environment,
                api: api,
                cache: cache,
                keychain: keychain,
                programsStore: programsStore,
                externalSyncLiveStore: externalSyncLiveStore,
                onUnpaired: onUnpaired
            )
        case .dealSync:
            DealSyncRootView(client: dealSyncClient, cache: cache, onBackToToolOne: router.closeProgram)
        case .externalSync:
            ExternalSyncRootView(
                client: externalSyncClient,
                cache: cache,
                liveStore: externalSyncLiveStore,
                onBackToToolOne: router.closeProgram
            )
        }
    }
}
