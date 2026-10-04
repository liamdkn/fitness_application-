import ActivityKit
import AppIntents
import Foundation

/// The supplements Live Activity: each supplement still in play today with
/// "x of y", and a button on each to tick the next dose off. Shared by the app
/// (starts and updates it) and the widget extension (draws it).
nonisolated struct SupplementActivityAttributes: ActivityAttributes {
    nonisolated struct Item: Codable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let taken: Int
        let goal: Int
        /// "1 scoop", for the line under the name.
        let amountText: String
        var isDone: Bool { taken >= goal }
    }

    nonisolated struct ContentState: Codable, Hashable {
        var items: [Item]
        var takenTotal: Int { items.reduce(0) { $0 + min($1.taken, $1.goal) } }
        var goalTotal: Int { items.reduce(0) { $0 + $1.goal } }
    }

    var day: String
}

/// Where a tap from the Live Activity goes. The system runs the intent in the
/// app's process, which installs `handler` at launch; if that hasn't happened
/// the tap is parked in the App Group and sent next time the app runs.
@MainActor
enum SupplementIntentBridge {
    static var handler: (@MainActor (UUID) async -> Void)?
}

nonisolated struct PendingSupplementTake: Codable, Equatable {
    let supplementId: UUID
    let at: Date
}

nonisolated enum PendingSupplementTakes {
    private static let key = "pending-supplement-takes-v1"

    static func append(_ supplementId: UUID, at: Date = Date()) {
        var all = list()
        all.append(PendingSupplementTake(supplementId: supplementId, at: at))
        save(all)
    }

    static func drain() -> [PendingSupplementTake] {
        let all = list()
        if !all.isEmpty { save([]) }
        return all
    }

    static func clear() { save([]) }

    private static func list() -> [PendingSupplementTake] {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingSupplementTake].self, from: data)) ?? []
    }

    private static func save(_ takes: [PendingSupplementTake]) {
        guard let data = try? JSONEncoder().encode(takes) else { return }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(data, forKey: key)
    }
}

/// The button on a supplement in the Live Activity.
struct TakeSupplementIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Take Supplement"

    @Parameter(title: "Supplement")
    var supplementId: String

    init() {}

    init(supplementId: UUID) {
        self.supplementId = supplementId.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: supplementId) else { return .result() }
        if let handler = SupplementIntentBridge.handler {
            await handler(id)
        } else {
            PendingSupplementTakes.append(id)
        }
        return .result()
    }
}
