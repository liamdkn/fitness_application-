import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Supplements still to take today, on the lock screen and in the Dynamic
/// Island, each with "x of y" and a button that ticks the next dose off.
struct SupplementLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SupplementActivityAttributes.self) { context in
            SupplementLockScreen(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.takenTotal) of \(context.state.goalTotal)", systemImage: "pills.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ForEach(context.state.items.filter { !$0.isDone }.prefix(2)) { item in
                            SupplementRow(item: item)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "pills.fill").foregroundStyle(AppColor.accent)
            } compactTrailing: {
                Text("\(context.state.takenTotal)/\(context.state.goalTotal)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "pills.fill").foregroundStyle(AppColor.accent)
            }
        }
    }
}

private struct SupplementLockScreen: View {
    let state: SupplementActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Supplements", systemImage: "pills.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                Spacer()
                Text("\(state.takenTotal) of \(state.goalTotal)")
                    .font(.subheadline.monospacedDigit())
            }
            ForEach(state.items.prefix(4)) { item in
                SupplementRow(item: item)
            }
        }
    }
}

private struct SupplementRow: View {
    let item: SupplementActivityAttributes.Item

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(item.taken) of \(item.goal) \u{00b7} \(item.amountText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColor.success)
            } else {
                Button(intent: TakeSupplementIntent(supplementId: item.id)) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
