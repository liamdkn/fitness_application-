import SwiftUI

/// Only appears when there's something to review - a Watch-recorded
/// Indoor Walk/Stairmaster with no matching cardio session yet, or a
/// Functional Strength Training session that overlaps a workout already
/// logged in-app. Every action here is explicit (Import / Add to Workout /
/// Dismiss) - nothing is written just because this card loaded.
struct WatchActivityCard: View {
    @ObservedObject var viewModel: WatchActivityViewModel

    var body: some View {
        if !viewModel.candidates.isEmpty {
            DashboardCard(title: "Watch Activity") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { Divider() }
                        WatchActivityRow(candidate: candidate, viewModel: viewModel)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppColor.danger)
                    }
                }
            }
        }
    }
}

private struct WatchActivityRow: View {
    let candidate: WatchActivityCandidate
    @ObservedObject var viewModel: WatchActivityViewModel

    private var title: String {
        switch candidate {
        case .cardio(let workout, let cardioType):
            "\(cardioLabel(cardioType, isIndoor: workout.isIndoor)) from Apple Watch"
        case .strengthEnrichment(_, let workout):
            "Watch data for \(workout.name ?? "today's workout")"
        }
    }

    /// Both Indoor and Outdoor Walk map to the same `CardioType.outdoorWalk`
    /// (we only track one "Walk" category) - but at review time, telling
    /// the two apart is exactly what makes an unlabeled "Walk" recognizable
    /// as, say, an evening walk outside vs a treadmill-free indoor lap.
    /// `isIndoor == nil` means the Watch didn't record that flag at all, so
    /// this falls back to the plain, undifferentiated label rather than
    /// guessing.
    private func cardioLabel(_ cardioType: CardioType, isIndoor: Bool?) -> String {
        guard cardioType == .outdoorWalk, let isIndoor else { return cardioType.displayName }
        return isIndoor ? "Indoor Walk" : "Outdoor Walk"
    }

    private var subtitle: String {
        let workout = candidate.detectedWorkout
        let minutes = max(0, Int(workout.endedAt.timeIntervalSince(workout.startedAt) / 60))
        var parts: [String] = []
        if let meters = workout.distanceMeters, meters > 0 {
            parts.append(String(format: "%.2f km", meters / 1000))
        }
        parts.append("\(minutes) min")
        if let calories = workout.activeCalories { parts.append("\(Int(calories)) cal") }
        if let avgHeartRate = workout.avgHeartRate { parts.append("\(avgHeartRate) avg bpm") }
        return parts.joined(separator: " \u{00b7} ")
    }

    private var actionLabel: String {
        switch candidate {
        case .cardio: "Import"
        case .strengthEnrichment: "Add to Workout"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(actionLabel) { Task { await confirm() } }
                    .buttonStyle(.appPrimaryCompact)
                Button("Dismiss") { Task { await viewModel.dismiss(candidate.detectedWorkout) } }
                    .buttonStyle(.appSecondaryCompact)
                    .controlSize(.small)
                Spacer()
                if viewModel.isProcessing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func confirm() async {
        switch candidate {
        case .cardio(let workout, let cardioType):
            await viewModel.importCardio(workout, cardioType: cardioType)
        case .strengthEnrichment(let workout, let appWorkout):
            await viewModel.enrichStrength(workout, appWorkout: appWorkout)
        }
    }
}
