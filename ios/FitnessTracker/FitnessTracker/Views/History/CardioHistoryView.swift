import SwiftUI

struct CardioHistoryView: View {
    @State private var sessions: [CardioTrackingSession] = []
    @State private var errorMessage: String?
    @State private var completingSession: CardioTrackingSession?
    private let repository = CardioSessionRepository()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if sessions.isEmpty {
                    Text("No cardio sessions logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Cardio History")
        .task { await load() }
        .sheet(item: $completingSession) { session in
            CardioSessionEndSheet(
                initialStepsAfter: session.stepsAfter,
                initialAvgHeartRate: session.avgHeartRate,
                allowsCancelActions: false,
                onSave: { stepsAfter, avgHeartRate in
                    await complete(session, stepsAfter: stepsAfter, avgHeartRate: avgHeartRate)
                }
            )
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: CardioTrackingSession) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(session.cardioType.displayName)
                .font(.subheadline.bold())
            HStack {
                Text(session.startedAt, style: .date)
                if session.endedAt != nil {
                    Text(formattedDuration(session.elapsed()))
                } else {
                    Text("in progress")
                }
                if let avgHeartRate = session.avgHeartRate {
                    Text("\(avgHeartRate) bpm avg")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isMissingDetails(session) {
                Text("Tap to add steps & heart rate")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }

        if isMissingDetails(session) {
            Button {
                completingSession = session
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func isMissingDetails(_ session: CardioTrackingSession) -> Bool {
        session.endedAt != nil && (session.stepsAfter == nil || session.avgHeartRate == nil)
    }

    private func load() async {
        do {
            sessions = try await repository.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func complete(_ session: CardioTrackingSession, stepsAfter: Int, avgHeartRate: Int) async {
        do {
            let updated = try await repository.updateSessionDetails(
                sessionId: session.id,
                stepsAfter: stepsAfter,
                avgHeartRate: avgHeartRate
            )
            if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
                sessions[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 60) min"
    }
}
