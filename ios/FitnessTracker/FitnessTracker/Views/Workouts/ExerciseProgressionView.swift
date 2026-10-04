import Charts
import SwiftUI

/// Est. 1RM trend for a single exercise, computed server-side via the
/// Epley formula in `v_exercise_progression`. Reachable from any list of
/// exercises (routine day detail, exercise picker) - this is purely a
/// read of data the app has already been computing since migration 0005,
/// just not surfaced anywhere until now.
struct ExerciseProgressionView: View {
    let exerciseId: UUID
    let exerciseName: String

    @State private var points: [ExerciseProgressionPoint] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    private let workoutRepository = WorkoutRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            if isLoading && points.isEmpty {
                ProgressView()
            } else if points.isEmpty {
                Text("No logged sets for this exercise yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Estimated 1RM") {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Date", point.performedAt),
                            y: .value("Est. 1RM (kg)", point.bestEst1RM)
                        )
                        PointMark(
                            x: .value("Date", point.performedAt),
                            y: .value("Est. 1RM (kg)", point.bestEst1RM)
                        )
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)

                    if let latest = points.last, let earliest = points.first, points.count > 1 {
                        let change = latest.bestEst1RM - earliest.bestEst1RM
                        Text(changeSummary(change: change, since: earliest.performedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppRowBackground())

                Section("Session History") {
                    ForEach(points.reversed()) { point in
                        HStack {
                            Text(point.performedAt, format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Est. 1RM \(point.bestEst1RM, specifier: "%.1f")kg")
                            Text("\u{00b7}")
                                .foregroundStyle(.secondary)
                            Text("\(Int(point.totalVolumeKg))kg volume")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle(exerciseName)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            points = try await workoutRepository.fetchProgression(exerciseId: exerciseId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeSummary(change: Double, since date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateText = formatter.string(from: date)
        if change > 0 {
            return "Up \(String(format: "%.1f", change))kg since \(dateText)."
        } else if change < 0 {
            return "Down \(String(format: "%.1f", -change))kg since \(dateText)."
        } else {
            return "Unchanged since \(dateText)."
        }
    }
}
