import SwiftUI

struct WeightHistoryView: View {
    /// When set, only the most recent `displayLimit` weigh-ins show, with a
    /// "More" link pushing an unrestricted instance of this same view -
    /// same recent-N-then-View-All pattern as `CardioHistoryView`.
    var displayLimit: Int? = 20

    @State private var logs: [BodyWeightLog] = []
    @State private var errorMessage: String?
    @State private var logToDelete: BodyWeightLog?
    private let repository = BodyWeightRepository()

    private var displayedLogs: [BodyWeightLog] {
        guard let displayLimit else { return logs }
        return Array(logs.prefix(displayLimit))
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if logs.isEmpty {
                Text("No weigh-ins logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedLogs) { log in
                    logRow(log)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                logToDelete = log
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                if let displayLimit, logs.count > displayLimit {
                    NavigationLink("More") {
                        WeightHistoryView(displayLimit: nil)
                    }
                }
            }
        }
        .navigationTitle("Weigh-Ins")
        .task { await load() }
        .confirmationDialog(
            "Delete this weigh-in? This can't be undone.",
            isPresented: Binding(get: { logToDelete != nil }, set: { if !$0 { logToDelete = nil } })
        ) {
            Button("Delete Weigh-In", role: .destructive) {
                if let log = logToDelete {
                    Task { await delete(log) }
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(_ log: BodyWeightLog) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.loggedAt, style: .date)
                    .font(.subheadline)
                if log.source != "manual" {
                    Text(log.source == "healthkit" ? "Apple Health" : log.source.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(String(format: "%.1f kg", log.weightKg))
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            logs = try await repository.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ log: BodyWeightLog) async {
        do {
            try await repository.deleteLog(id: log.id)
            logs.removeAll { $0.id == log.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        logToDelete = nil
    }
}
