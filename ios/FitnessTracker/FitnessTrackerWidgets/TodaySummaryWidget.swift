import SwiftUI
import WidgetKit

/// Today at a glance - calories, macros, steps, water - for the home screen
/// (small, medium) and the Lock Screen (circular, rectangular). The numbers
/// come from the snapshot the app last saved; if that's from an earlier day
/// the widget says so rather than showing yesterday as today.
struct TodaySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySummary", provider: SummaryProvider()) { entry in
            SummaryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Calories, macros, steps and water for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    /// Nil when nothing's been saved yet or it's from a previous day.
    let snapshot: WidgetSnapshot?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        // The app asks for a reload whenever the numbers change; this is the
        // fallback so a new day is noticed even if the app hasn't been opened.
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func current() -> SummaryEntry {
        let saved = WidgetSnapshot.load()
        return SummaryEntry(date: Date(), snapshot: saved?.day == WidgetSnapshot.dayString() ? saved : nil)
    }

    static let sample = WidgetSnapshot(
        day: WidgetSnapshot.dayString(), updatedAt: Date(),
        calories: 1450, calorieTarget: 2100, proteinG: 118, proteinTargetG: 180, carbsG: 140, carbsTargetG: 220,
        fatG: 46, fatTargetG: 60, steps: 6400, stepTarget: 10000, waterMl: 1750, waterTargetMl: 3000,
        caffeineMg: 190, caffeineLimitMg: 400
    )
}

private func fraction(_ value: Int, of target: Int?) -> Double {
    guard let target, target > 0 else { return 0 }
    return min(Double(value) / Double(target), 1)
}

private func grouped(_ value: Int) -> String {
    value.formatted(.number.grouping(.automatic))
}

struct SummaryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(spacing: 8) {
            if let s = entry.snapshot {
                CalorieRing(snapshot: s).frame(maxHeight: .infinity)
                Label("\(grouped(s.steps ?? 0))", systemImage: "figure.walk")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stepColor(s))
            } else {
                openAppPrompt
            }
        }
    }

    private var medium: some View {
        Group {
            if let s = entry.snapshot {
                HStack(spacing: 16) {
                    CalorieRing(snapshot: s).frame(width: 110)
                    VStack(alignment: .leading, spacing: 7) {
                        MacroBar(label: "Protein", value: s.proteinG, target: s.proteinTargetG, color: AppColor.protein)
                        MacroBar(label: "Carbs", value: s.carbsG, target: s.carbsTargetG, color: AppColor.carbs)
                        MacroBar(label: "Fat", value: s.fatG, target: s.fatTargetG, color: AppColor.fat)
                        HStack {
                            Label("\(grouped(s.steps ?? 0))", systemImage: "figure.walk")
                                .foregroundStyle(stepColor(s))
                            Spacer()
                            Label("\(String(format: "%.1f", Double(s.waterMl) / 1000)) L", systemImage: "drop.fill")
                                .foregroundStyle(AppColor.water)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            } else {
                openAppPrompt
            }
        }
    }

    private func stepColor(_ s: WidgetSnapshot) -> Color {
        if let target = s.stepTarget, (s.steps ?? 0) >= target { return AppColor.success }
        return .primary
    }

    private var openAppPrompt: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text("Open Fitness Tracker to update today")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Lock Screen

    private var circular: some View {
        Group {
            if let s = entry.snapshot, let target = s.stepTarget, target > 0 {
                Gauge(value: fraction(s.steps ?? 0, of: target)) {
                    Image(systemName: "figure.walk")
                } currentValueLabel: {
                    Text(compact(s.steps ?? 0))
                }
                .gaugeStyle(.accessoryCircular)
            } else if let s = entry.snapshot {
                Text(compact(s.steps ?? 0))
            } else {
                Image(systemName: "figure.walk")
            }
        }
    }

    private var rectangular: some View {
        Group {
            if let s = entry.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    if let target = s.calorieTarget {
                        Text("\(grouped(max(target - s.calories, 0))) kcal left")
                            .font(.headline)
                    } else {
                        Text("\(grouped(s.calories)) kcal")
                            .font(.headline)
                    }
                    Text("P \(s.proteinG)g \u{00b7} \(grouped(s.steps ?? 0)) steps")
                        .font(.caption)
                    if let target = s.stepTarget, target > 0 {
                        ProgressView(value: fraction(s.steps ?? 0, of: target))
                    }
                }
            } else {
                Text("Open app to update")
            }
        }
    }

    private func compact(_ steps: Int) -> String {
        steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)"
    }
}

/// Calories eaten against the target, with what's left in the middle (or the
/// total eaten when there's no target).
private struct CalorieRing: View {
    let snapshot: WidgetSnapshot

    private var remaining: Int? { snapshot.calorieTarget.map { $0 - snapshot.calories } }
    private var isOver: Bool { (remaining ?? 0) < 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 9)
            Circle()
                .trim(from: 0, to: fraction(snapshot.calories, of: snapshot.calorieTarget))
                .stroke(isOver ? AppColor.danger : AppColor.calories, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(grouped(abs(remaining ?? snapshot.calories)))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(remaining == nil ? "kcal" : (isOver ? "kcal over" : "kcal left"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(4)
    }
}

private struct MacroBar: View {
    let label: String
    let value: Int
    let target: Int?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(target.map { "\(value)/\($0)g" } ?? "\(value)g")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
            ProgressView(value: fraction(value, of: target))
                .tint(color)
        }
    }
}
