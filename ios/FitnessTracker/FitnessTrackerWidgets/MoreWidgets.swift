import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// Nil when nothing's been saved yet or it's from a previous day.
    let snapshot: WidgetSnapshot?
    /// Millilitres tapped on the water widget that the app hasn't logged yet.
    let pendingWaterMl: Int
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: SummaryProvider.sample, pendingWaterMl: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func current() -> SnapshotEntry {
        let saved = WidgetSnapshot.load()
        return SnapshotEntry(
            date: Date(),
            snapshot: saved?.day == WidgetSnapshot.dayString() ? saved : nil,
            pendingWaterMl: PendingWater.pendingMlToday()
        )
    }
}

private func grouped(_ value: Int) -> String {
    value.formatted(.number.grouping(.automatic))
}

private struct OpenAppPrompt: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text("Open Fitness Tracker to update today")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Water (tap to log)

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaterTap", provider: SnapshotProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Today's water, with buttons to log a drink in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var total: Int { (entry.snapshot?.waterMl ?? 0) + entry.pendingWaterMl }
    private var target: Int { entry.snapshot?.waterTargetMl ?? 2500 }
    private var buttons: [WidgetSnapshot.WaterButton] {
        let saved = entry.snapshot?.waterButtons ?? []
        let all = saved.isEmpty ? [WidgetSnapshot.WaterButton(name: "Glass", ml: 250, containerId: nil)] : saved
        return Array(all.prefix(family == .systemSmall ? 2 : 3))
    }

    var body: some View {
        if entry.snapshot == nil && entry.pendingWaterMl == 0 {
            OpenAppPrompt()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(String(format: "%.2f L", Double(total) / 1000), systemImage: "drop.fill")
                        .font(.headline)
                        .foregroundStyle(AppColor.water)
                    Spacer()
                    Text("of \(String(format: "%.1f", Double(target) / 1000)) L")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(Double(total) / Double(max(target, 1)), 1))
                    .tint(AppColor.water)
                HStack(spacing: 6) {
                    ForEach(buttons) { button in
                        Button(intent: AddWaterIntent(amountMl: button.ml, containerId: button.containerId)) {
                            VStack(spacing: 1) {
                                Text("+\(button.ml)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                Text(button.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColor.water)
                    }
                }
            }
        }
    }
}

// MARK: - Workout

struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWorkout", provider: SnapshotProvider()) { entry in
            WorkoutWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Workout")
        .description("What's planned for today, and whether it's done.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct WorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let title = snapshot.workoutTitle {
            let done = snapshot.workoutDone == true
            let isRest = snapshot.isRestDay == true
            VStack(alignment: .leading, spacing: 4) {
                if family == .accessoryRectangular {
                    Text(title).font(.headline)
                    Text(isRest ? "Take it easy" : (done ? "Done today" : (snapshot.workoutDetail ?? "")))
                        .font(.caption)
                } else {
                    Image(systemName: isRest ? "bed.double.fill" : (done ? "checkmark.circle.fill" : "figure.strengthtraining.traditional"))
                        .font(.title2)
                        .foregroundStyle(done ? AppColor.success : AppColor.accent)
                    Spacer()
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(isRest ? "Rest" : (done ? "Done" : (snapshot.workoutDetail ?? "")))
                        .font(.caption)
                        .foregroundStyle(done ? AppColor.success : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            OpenAppPrompt()
        }
    }
}

// MARK: - Steps after cardio

struct StepsAfterCardioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StepsAfterCardio", provider: SnapshotProvider()) { entry in
            StepsAfterCardioView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Steps After Cardio")
        .description("Today's steps with the steps counted during cardio taken off.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct StepsAfterCardioView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let walking = snapshot.walkingSteps {
            let cardio = snapshot.cardioSteps ?? 0
            let progress = snapshot.stepTarget.map { min(Double(walking) / Double(max($0, 1)), 1) } ?? 0
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "figure.walk")
                } currentValueLabel: {
                    Text(walking >= 1000 ? String(format: "%.1fk", Double(walking) / 1000) : "\(walking)")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(grouped(walking)) steps").font(.headline)
                    Text(cardio > 0 ? "+ \(grouped(cardio)) on cardio" : "No cardio steps")
                        .font(.caption)
                    if snapshot.stepTarget != nil { ProgressView(value: progress) }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Walking steps", systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(grouped(walking))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(progress >= 1 ? AppColor.success : .primary)
                    if let target = snapshot.stepTarget {
                        ProgressView(value: progress).tint(AppColor.steps)
                        Text("of \(grouped(target))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(cardio > 0 ? "\(grouped(cardio)) more on cardio" : "No cardio steps today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            OpenAppPrompt()
        }
    }
}
