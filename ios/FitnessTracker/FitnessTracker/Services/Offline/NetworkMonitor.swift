import Combine
import Foundation
import Network

/// Thin wrapper around `NWPathMonitor` - the one thing every offline-aware
/// piece of the app needs to know is "are we connected right now," plus a
/// hook to run something the instant that flips from false to true (that's
/// the trigger `OfflineWorkoutQueue` uses to flush whatever piled up while
/// the gym had no signal).
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.fitnesstracker.network-monitor")
    private var onReconnect: [() -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleUpdate(connected: connected)
            }
        }
        monitor.start(queue: queue)
    }

    private func handleUpdate(connected: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        if connected, !wasConnected {
            for action in onReconnect { action() }
        }
    }

    /// Registers a callback fired every time connectivity comes back after
    /// being down. Callbacks accumulate for the life of the app - this is
    /// only ever called once per long-lived singleton (`OfflineWorkoutQueue`),
    /// never from per-view state, so there's nothing to deregister.
    func onReconnected(_ action: @escaping () -> Void) {
        onReconnect.append(action)
    }
}
