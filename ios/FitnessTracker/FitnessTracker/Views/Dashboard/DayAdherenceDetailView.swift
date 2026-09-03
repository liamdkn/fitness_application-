import SwiftUI

/// One day's adherence breakdown, reached by tapping a day in Weekly
/// Insights' week strip. All the data it shows was already computed as
/// part of that week's `WeeklyAdherenceScore` - no fetching of its own.
struct DayAdherenceDetailView: View {
    let dayScore: DailyAdherenceScore

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: dayScore.date)
    }

    private func bandColor(_ score: Double) -> Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    if let overall = dayScore.overall {
                        ScoreRingView(score: overall, color: bandColor(overall), diameter: 120, ringWidth: 14)
                        Text("\(dayScore.scoredCount) of \(dayScore.totalCount) tracked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not enough logged this day for a score.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)

            Section("Breakdown") {
                ForEach(dayScore.components) { component in
                    HStack {
                        Text(component.component.label)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(component.score.map { "\(Int($0.rounded()))" } ?? "-")
                                .fontWeight(.semibold)
                                .foregroundStyle(component.score == nil ? .secondary : .primary)
                            Text(component.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DayAdherenceDetailView(dayScore: DailyAdherenceScore(
            date: Date(),
            components: [
                AdherenceComponentScore(component: .calories, score: 92, detail: "2050/2150 kcal"),
                AdherenceComponentScore(component: .protein, score: 100, detail: "185/180g"),
                AdherenceComponentScore(component: .steps, score: 78, detail: "7800/10000"),
                AdherenceComponentScore(component: .training, score: 100, detail: "Workout logged")
            ]
        ))
    }
}
