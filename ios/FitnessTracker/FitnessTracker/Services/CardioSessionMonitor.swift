import Combine
import Foundation

@MainActor
final class CardioSessionMonitor: ObservableObject {
    static let shared = CardioSessionMonitor()

    @Published private(set) var activeSession: CardioTrackingSession?

    private let repository = CardioSessionRepository()

    private init() {}

    func refresh() async {
        activeSession = try? await repository.fetchActive()
    }

    func sessionStarted(_ session: CardioTrackingSession) {
        activeSession = session
    }

    func sessionUpdated(_ session: CardioTrackingSession) {
        activeSession = session
    }

    func sessionEnded() {
        activeSession = nil
    }
}
