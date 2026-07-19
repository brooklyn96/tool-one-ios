import SwiftUI

struct PairingStart: Codable { let deviceCode: String; let userCode: String; let verificationURL: URL; let expiresAt: Date; let intervalSeconds: Int }

@MainActor final class PairingViewModel: ObservableObject {
    @Published var pairing: PairingStart?
    @Published var isLoading = false
    @Published var message: String?
    private let api: APIClient
    private let keychain: KeychainStore
    private let paired: () -> Void
    private var pollTask: Task<Void, Never>?

    init(api: APIClient, keychain: KeychainStore, paired: @escaping () -> Void) { self.api = api; self.keychain = keychain; self.paired = paired }
    deinit { pollTask?.cancel() }

    func start() async {
        isLoading = true; defer { isLoading = false }
        do {
            let result: PairingStart = try await api.send("/v1/auth/device/start", method: "POST", body: StartBody(deviceIdentifier: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString, deviceName: UIDevice.current.name), authenticated: false)
            pairing = result; pollTask?.cancel(); pollTask = Task { await poll(result) }
        } catch { message = error.localizedDescription }
    }

    private func poll(_ request: PairingStart) async {
        while !Task.isCancelled && request.expiresAt > Date() {
            do {
                let tokens: SessionTokens = try await api.send("/v1/auth/device/token", method: "POST", body: TokenBody(deviceCode: request.deviceCode), authenticated: false)
                try keychain.save(tokens.refreshToken, account: "refresh-token")
                try keychain.save(tokens.deviceId, account: "device-id")
                paired(); return
            } catch let problem as APIProblem where problem.code == "authorization_pending" || problem.code == "slow_down" {
                let delay = problem.retryAfterSeconds ?? request.intervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(max(delay, 1)) * 1_000_000_000)
            } catch { message = error.localizedDescription; return }
        }
        if !Task.isCancelled { message = "Mã ghép nối đã hết hạn." }
    }

    private struct StartBody: Encodable { let deviceIdentifier: String; let deviceName: String; let requestedScopes = ["read", "audit:read", "operate:sync"] }
    private struct TokenBody: Encodable { let deviceCode: String }
}

struct PairingView: View {
    @StateObject private var model: PairingViewModel
    init(api: APIClient, keychain: KeychainStore, paired: @escaping () -> Void) { _model = StateObject(wrappedValue: PairingViewModel(api: api, keychain: keychain, paired: paired)) }
    var body: some View {
        NavigationStack { List {
            if let pairing = model.pairing { Section("Mã thiết bị") { Text(pairing.userCode).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled); Link("Mở trang xác nhận", destination: pairing.verificationURL); Text("Ứng dụng sẽ tự hoàn tất sau khi quản trị viên phê duyệt.").foregroundStyle(.secondary) } }
            else { Section { Button("Bắt đầu ghép nối") { Task { await model.start() } }.disabled(model.isLoading) } }
            if let message = model.message { Section { Text(message).foregroundStyle(.red); Button("Thử lại") { Task { await model.start() } } } }
        }.navigationTitle("Ghép nối").task { if model.pairing == nil { await model.start() } } }
    }
}
