import Foundation

/// Today's numbers for the home-screen and Lock Screen widgets. A widget
/// can't sign in to the backend itself, so the app writes this into the App
/// Group's shared defaults whenever it learns something new and asks
/// WidgetKit to redraw.
nonisolated struct WidgetSnapshot: Codable, Equatable {
    var day: String
    var updatedAt: Date
    var calories: Int
    var calorieTarget: Int?
    var proteinG: Int
    var proteinTargetG: Int?
    var carbsG: Int
    var carbsTargetG: Int?
    var fatG: Int
    var fatTargetG: Int?
    var steps: Int?
    var stepTarget: Int?
    var waterMl: Int
    var waterTargetMl: Int
    var caffeineMg: Int
    var caffeineLimitMg: Int

    static let appGroup = "group.dkn.FitnessTracker"
    private static let key = "widget-snapshot-v1"

    /// Local calendar day as yyyy-MM-dd - a snapshot from yesterday must not
    /// pass as today's when the app hasn't run yet this morning.
    static func dayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Removes the saved numbers (sign-out / account switch).
    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: key)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
