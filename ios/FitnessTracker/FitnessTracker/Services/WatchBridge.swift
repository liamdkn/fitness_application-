import Foundation
import WatchConnectivity

/// The iPhone's side of the Watch app: logs what the Watch sends (water,
/// finished treadmill sessions) and pushes the water buttons and today's
/// total back. Messages the Watch sends are queued by the system, so they
/// arrive even if this app wasn't running; one that can't be saved right away
/// (no connection) is kept and retried.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private static let pendingKey = "watch-pending-messages"

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Latest water settings for the Watch, as application context.
    func pushConfig(buttonsMl: [Int], todayMl: Int, targetMl: Int) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired else { return }
        let config = WatchMessage.Config(waterButtonsMl: buttonsMl, waterTodayMl: todayMl, waterTargetMl: targetMl)
        try? WCSession.default.updateApplicationContext(config.context)
    }

    /// Retries anything that couldn't be saved earlier.
    func retryPending() async {
        let pending = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
        guard !pending.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        for info in pending { await handle(info) }
    }

    /// Sign-out or account switch.
    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
    }

    private func handle(_ info: [String: Any]) async {
        do {
            if let water = WatchMessage.Water(info) {
                _ = try await WaterRepository().addLog(
                    date: water.at, amountMl: water.amountMl, containerId: nil, id: water.id, at: water.at
                )
                await WidgetSnapshotService.shared.refresh(force: true)
            } else if let session = WatchMessage.Treadmill(info) {
                try await importTreadmill(session)
            }
        } catch {
            keep(info)
        }
    }

    private func importTreadmill(_ session: WatchMessage.Treadmill) async throws {
        let repository = CardioSessionRepository()
        // Delivered twice (or also found by the Watch workout import)? Once is enough.
        let day = Calendar.current.startOfDay(for: session.start)
        let existing = try await repository.fetchHistory(from: day, to: session.end.addingTimeInterval(60))
        guard !existing.contains(where: { $0.healthkitUUID == session.workoutId.uuidString }) else { return }
        try await repository.importFromHealthKit(
            cardioType: .inclineTreadmill,
            startedAt: session.start,
            endedAt: session.end,
            avgHeartRate: session.avgHeartRate,
            activeCalories: session.activeCalories,
            healthkitUUID: session.workoutId.uuidString
        )
        // Steps before and after, the same record a hand-timed session leaves.
        _ = try? await CardioStepSessionRepository().logSession(
            date: session.start, stepsBefore: session.stepsBefore, stepsAfter: session.stepsAfter
        )
        await WidgetSnapshotService.shared.refresh(force: true)
    }

    private func keep(_ info: [String: Any]) {
        var pending = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String: Any]] ?? []
        pending.append(info)
        UserDefaults.standard.set(pending, forKey: Self.pendingKey)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in await self.handle(userInfo) }
    }
}
