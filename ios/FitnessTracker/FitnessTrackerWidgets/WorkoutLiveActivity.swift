import ActivityKit
import SwiftUI
import WidgetKit

/// The gym session on the lock screen and in the Dynamic Island: the exercise
/// you're on, which set is next, the last set you logged, the rest countdown
/// and the session clock. The timers are drawn by the system from dates, so
/// they keep ticking without the app updating them every second.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .leading)
                    } icon: {
                        Image(systemName: "dumbbell.fill").foregroundStyle(AppColor.accent)
                    }
                    .font(.subheadline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestBadge(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SetSummary(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(AppColor.accent)
            } compactTrailing: {
                if let rest = activeRest(context.state, isStale: context.isStale) {
                    Text(timerInterval: Date.now...rest, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(AppColor.accent)
                } else {
                    Text("\(context.state.setsLogged)")
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(AppColor.accent)
            }
        }
    }
}

/// The rest end date while the countdown is still meaningful - nil once it has
/// run out (the activity goes stale at that moment) or if none is running.
private func activeRest(_ state: WorkoutActivityAttributes.ContentState, isStale: Bool) -> Date? {
    guard !isStale, let rest = state.restEndsAt, rest > Date.now else { return nil }
    return rest
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(context.attributes.workoutName, systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                    .lineLimit(1)
                Spacer()
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70, alignment: .trailing)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.exerciseName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    SetSummary(state: context.state)
                }
                Spacer(minLength: 8)
                RestBadge(state: context.state, isStale: context.isStale)
            }
        }
    }
}

/// "Set 3 of 4" with the last set logged under it.
private struct SetSummary: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.allDone {
                Text("\(state.setsLogged) sets logged - finish when you're ready")
                    .font(.subheadline)
            } else if let number = state.setNumber, let total = state.setTotal {
                Text("Set \(number) of \(total) \u{00b7} \(state.setsLogged) logged")
                    .font(.subheadline)
            }
            if let lastSet = state.lastSet {
                Text("Last: \(lastSet)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The rest countdown, or - once it has run out - a nudge to go again.
private struct RestBadge: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if let rest = activeRest(state, isStale: isStale) {
            VStack(spacing: 0) {
                Text("REST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColor.accent)
                Text(timerInterval: Date.now...rest, countsDown: true)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
            }
        } else if state.restEndsAt != nil {
            VStack(spacing: 0) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(AppColor.success)
                Text("Go")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.success)
            }
        }
    }
}
