import ActivityKit
import Foundation

/// The gym session's Live Activity. Shared by the app (which starts and
/// updates it) and the widget extension (which draws it) - ActivityKit
/// matches the two by this type's name, so it must exist once, in both.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// The exercise you're on, or the one coming up after a finished one.
        var exerciseName: String
        /// Which set of that exercise is next ("Set 3 of 4"); nil when every
        /// planned set of every exercise is done.
        var setNumber: Int?
        var setTotal: Int?
        /// The set just logged, e.g. "Bench Press · 80 kg x 8".
        var lastSet: String?
        /// When the rest timer ends, nil if there isn't one running.
        var restEndsAt: Date?
        /// Sets logged across the whole workout.
        var setsLogged: Int
        var allDone: Bool
    }

    var workoutId: UUID
    var workoutName: String
    var startedAt: Date
}
