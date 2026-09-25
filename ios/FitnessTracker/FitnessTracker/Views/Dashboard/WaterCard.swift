import SwiftUI

/// Today's water intake at a glance - a total plus a progress bar toward
/// the daily target range, "Log" opening `WaterLogView` to add more or
/// manage containers. Presentation-only; `totalMl`/`targetMinMl`/
/// `targetMaxMl` come from `DashboardViewModel.loadWaterGlance()` like
/// every other Dashboard glance figure, and `onLogged` re-fetches them
/// after the sheet closes.
struct WaterCard: View {
    let totalMl: Int
    let targetMinMl: Int
    let targetMaxMl: Int
    let onLogged: () async -> Void

    @State private var showingLog = false

    /// Bar fills toward the top of the range (the max) - hitting anywhere
    /// in the range still reads as "on target" via `isOnTarget` below.
    private var progress: Double {
        guard targetMaxMl > 0 else { return 0 }
        return min(Double(totalMl) / Double(targetMaxMl), 1)
    }

    private var isOnTarget: Bool {
        totalMl >= targetMinMl
    }

    private var targetRangeText: String {
        targetMinMl == targetMaxMl
            ? formattedAmount(targetMinMl)
            : "\(formattedAmount(targetMinMl))\u{2013}\(formattedAmount(targetMaxMl))"
    }

    var body: some View {
        DashboardCard(title: "Water") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedAmount(totalMl))
                        .font(.title2.bold())
                    Text("/ \(targetRangeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Log") {
                        showingLog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                ProgressView(value: progress)
                    .tint(isOnTarget ? .green : .blue)
            }
        }
        .sheet(isPresented: $showingLog, onDismiss: { Task { await onLogged() } }) {
            WaterLogView()
        }
    }

    private func formattedAmount(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.1f L", Double(ml) / 1000) : "\(ml) ml"
    }
}
