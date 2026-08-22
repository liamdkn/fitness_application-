import Combine
import Foundation

@MainActor
final class CardioSessionViewModel: ObservableObject {
    @Published private(set) var session: CardioTrackingSession
    @Published var errorMessage: String?
    @Published var isFinished = false
    @Published private(set) var isMutating = false

    private let repository = CardioSessionRepository()

    init(session: CardioTrackingSession) {
        self.session = session
    }

    func pause() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            session = try await repository.pauseSession(sessionId: session.id)
            CardioSessionMonitor.shared.sessionUpdated(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() async {
        guard !isMutating, let pausedAt = session.pausedAt else { return }
        isMutating = true
        defer { isMutating = false }
        let newPausedSeconds = session.pausedSeconds + Int(Date().timeIntervalSince(pausedAt))
        do {
            session = try await repository.resumeSession(sessionId: session.id, newPausedSeconds: newPausedSeconds)
            CardioSessionMonitor.shared.sessionUpdated(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish(stepsAfter: Int?, avgHeartRate: Int) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            session = try await repository.finishSession(
                sessionId: session.id,
                finalPausedSeconds: finalPausedSeconds(),
                stepsAfter: stepsAfter,
                avgHeartRate: avgHeartRate
            )
            CardioSessionMonitor.shared.sessionEnded()
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishWithoutDetails() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            session = try await repository.finishSessionWithoutDetails(
                sessionId: session.id,
                finalPausedSeconds: finalPausedSeconds()
            )
            CardioSessionMonitor.shared.sessionEnded()
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discard() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.discardSession(sessionId: session.id)
            CardioSessionMonitor.shared.sessionEnded()
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finalPausedSeconds() -> Int {
        guard let pausedAt = session.pausedAt else { return session.pausedSeconds }
        return session.pausedSeconds + Int(Date().timeIntervalSince(pausedAt))
    }
}
