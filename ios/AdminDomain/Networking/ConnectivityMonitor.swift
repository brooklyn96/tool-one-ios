import Network
import Foundation

@MainActor final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor(); private let queue = DispatchQueue(label: "com.beyondk.admindomain.connectivity")
    init() { monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.isOnline = path.status == .satisfied } }; monitor.start(queue: queue) }
    deinit { monitor.cancel() }
}
