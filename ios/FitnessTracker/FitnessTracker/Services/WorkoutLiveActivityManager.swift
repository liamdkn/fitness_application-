import ActivityKit
import Foundation

/// Starts, updates and ends the gym session's Live Activity (lock screen and
/// Dynamic Island). There is only ever one - a workout is one session - and
/// it's found again by workout id so reopening the app mid-session carries on
/// with the one already showing rather than stacking a second.
@MainActor
final class WorkoutLiveActivityManager {
    static let shared = WorkoutLiveActivityManager()

    private var activity: Activity<WorkoutActivityAttributes>?

    private init() {}

    func sync(workout: Workout, state: WorkoutActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Once the rest timer's end passes the activity goes stale, which is
        // what lets the widget swap the countdown for "Rest over".
        let content = ActivityContent(state: state, staleDate: state.restEndsAt)

        if activity == nil {
            activity = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.workoutId == workout.id }
            // A leftover from some other session isn't this workout's.
            for other in Activity<WorkoutActivityAttributes>.activities where other.attributes.workoutId != workout.id {
                await other.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let activity {
            await activity.update(content)
            return
        }
        let attributes = WorkoutActivityAttributes(
            workoutId: workout.id,
            workoutName: workout.name ?? "Workout",
            startedAt: workout.startedAt
        )
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func end() async {
        for current in Activity<WorkoutActivityAttributes>.activities {
            await current.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}
