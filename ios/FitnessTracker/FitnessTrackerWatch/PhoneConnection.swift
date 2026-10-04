import Foundation
import Observation
import WatchConnectivity

/// The Watch's line to the iPhone app: sends logs (queued, so they arrive
/// even when the phone is out of reach) and receives the water buttons and
/// today's total.
@Observable
final class PhoneConnection: NSObject, WCSessionDelegate {
    static let shared = PhoneConnection()

    var waterButtonsMl = [250, 500]
    var waterTodayMl = 0
    var waterTargetMl = 2500

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ info: [String: Any]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(info)
    }

    func sendWater(_ ml: Int) {
        waterTodayMl += ml
        send(WatchMessage.Water(amountMl: ml).userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard let config = WatchMessage.Config(context) else { return }
        Task { @MainActor in
            self.waterButtonsMl = config.waterButtonsMl.isEmpty ? [250, 500] : config.waterButtonsMl
            self.waterTodayMl = config.waterTodayMl
            self.waterTargetMl = config.waterTargetMl
        }
    }
}
