import Charts
import SwiftUI

private struct ProgressionPointDisplay: Identifiable {
    let point: ExerciseProgressionPoint
    let isPR: Bool
    var id: UUID { point.id }
}

struct ExerciseProgressionView: View {
    let exercise: Exercise

    @State private var points: [ProgressionPointDisplay] = []
    @State private var errorMessage: String?
    private let repository = ProgressionRepository()

    private var prCount: Int {
        points.count(where: \.isPR)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if points.isEmpty {
                    Text("No logged sets for this exercise yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading) {
                        Text("Estimated 1RM")
                            .font(.headline)
                        Chart(points) { entry in
                            LineMark(
                                x: .value("Date", entry.point.performedAt),
                                y: .value("Est. 1RM (kg)", entry.point.bestEst1RM)
                            )
                            PointMark(
                                x: .value("Date", entry.point.performedAt),
                                y: .value("Est. 1RM (kg)", entry.point.bestEst1RM)
                            )
                            .foregroundStyle(entry.isPR ? Color.orange : Color.accentColor)
                            .symbolSize(entry.isPR ? 80 : 30)
                        }
                        .frame(height: 220)
                    }

                    VStack(alignment: .leading) {
                        Text("Volume")
                            .font(.headline)
                        Chart(points) { entry in
                            BarMark(
                                x: .value("Date", entry.point.performedAt),
                                y: .value("Volume (kg)", entry.point.totalVolumeKg)
                            )
                        }
                        .frame(height: 180)
                    }

                    Text("\(prCount) PR\(prCount == 1 ? "" : "s") logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .task { await load() }
    }

    private func load() async {
        do {
            let progression = try await repository.fetchProgression(exerciseId: exercise.id)
            var runningBest = -Double.infinity
            points = progression.map { point in
                let isPR = point.bestEst1RM >= runningBest
                runningBest = max(runningBest, point.bestEst1RM)
                return ProgressionPointDisplay(point: point, isPR: isPR)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
