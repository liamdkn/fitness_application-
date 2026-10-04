import Foundation

/// Water logged from the widget. The widget can't talk to the backend, so a
/// tap is written here (in the App Group) and the app sends it the next time
/// it runs - with the time of the tap, so the log is stamped when you drank,
/// not when the app was next opened.
nonisolated struct PendingWaterEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let amountMl: Int
    let containerId: UUID?
    let at: Date
}

nonisolated enum PendingWater {
    private static let key = "pending-water-v1"

    static func all() -> [PendingWaterEntry] {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingWaterEntry].self, from: data)) ?? []
    }

    static func append(amountMl: Int, containerId: UUID?, at: Date = Date()) {
        var entries = all()
        entries.append(PendingWaterEntry(id: UUID(), amountMl: amountMl, containerId: containerId, at: at))
        save(entries)
    }

    /// Everything waiting, removed from the queue.
    static func drain() -> [PendingWaterEntry] {
        let entries = all()
        if !entries.isEmpty { save([]) }
        return entries
    }

    /// Millilitres waiting from today - added to the snapshot's total so the
    /// widget moves the moment it's tapped.
    static func pendingMlToday() -> Int {
        let calendar = Calendar.current
        return all().filter { calendar.isDateInToday($0.at) }.reduce(0) { $0 + $1.amountMl }
    }

    static func clear() { save([]) }

    private static func save(_ entries: [PendingWaterEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(data, forKey: key)
    }
}
