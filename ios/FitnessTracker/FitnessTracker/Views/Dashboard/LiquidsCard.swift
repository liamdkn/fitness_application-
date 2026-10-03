import SwiftUI

/// Today's liquids at a glance - water and every other drink together,
/// against the daily target range, plus the day's caffeine. "Log" opens
/// `LiquidsLogView` to add water or a drink. Presentation-only;
/// the figures come from `DashboardViewModel.loadLiquidsGlance()` like every
/// other Dashboard glance figure, and `onLogged` re-fetches them after the
/// sheet closes.
struct LiquidsCard: View {
    let totalMl: Int
    let targetMinMl: Int
    let targetMaxMl: Int
    let caffeineMg: Int
    let caffeineLimitMg: Int
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
        DashboardCard(title: "Liquids") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedAmount(totalMl))
                        .font(.title2.bold())
                        .rolling(Double(totalMl))
                    Text("/ \(targetRangeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Log") {
                        showingLog = true
                    }
                    .buttonStyle(.appPrimaryCompact)
                    .controlSize(.small)
                }
                AppProgressBar(value: progress)
                    .tint(isOnTarget ? AppColor.success : AppColor.water)
                if caffeineMg > 0 {
                    Label("Caffeine \(caffeineMg) / \(caffeineLimitMg) mg", systemImage: "cup.and.saucer.fill")
                        .font(.caption)
                        .foregroundStyle(caffeineMg > caffeineLimitMg ? AppColor.danger : .secondary)
                }
            }
        }
        .sheet(isPresented: $showingLog, onDismiss: { Task { await onLogged() } }) {
            LiquidsLogView()
        }
    }

    private func formattedAmount(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.1f L", Double(ml) / 1000) : "\(ml) ml"
    }
}
