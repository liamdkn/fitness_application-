import SwiftUI

struct NutritionHistoryView: View {
    @State private var logs: [NutritionLog] = []
    @State private var errorMessage: String?
    private let repository = NutritionRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if logs.isEmpty {
                Text("No entries yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs) { log in
                    NutritionLogRow(log: log)
                }
            }
        }
        .navigationTitle("Nutrition History")
        .task { await load() }
    }

    private func load() async {
        do {
            logs = try await repository.fetchRecent(days: 365)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
