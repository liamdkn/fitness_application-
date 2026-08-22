import SwiftUI

struct CardioHistoryView: View {
    /// When set, only the most recent `displayLimit` sessions show, with a
    /// "More" link pushing an unrestricted instance of this same view -
    /// pass `nil` (as that pushed instance does) to show everything.
    var displayLimit: Int? = 7

    @State private var sessions: [CardioTrackingSession] = []
    @State private var errorMessage: String?
    @State private var completingSession: CardioTrackingSession?
    @State private var sessionToDelete: CardioTrackingSession?
    private let repository = CardioSessionRepository()

    private var displayedSessions: [CardioTrackingSession] {
        guard let displayLimit else { return sessions }
        return Array(sessions.prefix(displayLimit))
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if sessions.isEmpty {
                Text("No cardio sessions logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedSessions) { session in
                    sessionRow(session)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                sessionToDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if let displayLimit, sessions.count > displayLimit {
                    NavigationLink("More") {
                        CardioHistoryView(displayLimit: nil)
                    }
                }
            }
        }
        .navigationTitle("Cardio History")
        .task { await load() }
        .sheet(item: $completingSession) { session in
            CardioSessionEndSheet(
                initialStepsAfter: session.stepsAfter,
                initialAvgHeartRate: session.avgHeartRate,
                requiresSteps: session.cardioType.involvesSteps,
                allowsCancelActions: false,
                onSave: { stepsAfter, avgHeartRate in
                    await complete(session, stepsAfter: stepsAfter, avgHeartRate: avgHeartRate)
                }
            )
        }
        .confirmationDialog(
            "Delete this cardio session? This can't be undone.",
            isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })
        ) {
            Button("Delete Session", role: .destructive) {
                if let session = sessionToDelete {
                    Task { await delete(session) }
                }
            }
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
                Text("Tap to add \(session.cardioType.involvesSteps ? "steps & " : "")heart rate")
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

    /// A session whose type never collects steps (Bike/Rowing/Swimming/
    /// etc.) isn't "missing" steps just because `stepsAfter` is nil - that's
    /// simply not applicable to it, so only heart rate (and steps, when
    /// this type actually tracks them) count toward missing.
    private func isMissingDetails(_ session: CardioTrackingSession) -> Bool {
        guard session.endedAt != nil else { return false }
        let missingSteps = session.cardioType.involvesSteps && session.stepsAfter == nil
        return missingSteps || session.avgHeartRate == nil
    }

    private func load() async {
        do {
            sessions = try await repository.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func complete(_ session: CardioTrackingSession, stepsAfter: Int?, avgHeartRate: Int) async {
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

    private func delete(_ session: CardioTrackingSession) async {
        do {
            try await repository.discardSession(sessionId: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        sessionToDelete = nil
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 60) min"
    }
}
