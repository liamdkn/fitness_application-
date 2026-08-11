import SwiftUI

struct NutritionEntryView: View {
    @State private var selectedDate = Date()
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var recentLogs: [NutritionLog] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = NutritionRepository()

    private var isValid: Bool {
        Double(calories) != nil && Double(protein) != nil && Double(carbs) != nil && Double(fat) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Log a Day") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .onChange(of: selectedDate) { _, _ in Task { await loadForSelectedDate() } }

                    LabeledTextField(label: "Calories", text: $calories, unit: "kcal")
                    LabeledTextField(label: "Protein", text: $protein, unit: "g")
                    LabeledTextField(label: "Carbs", text: $carbs, unit: "g")
                    LabeledTextField(label: "Fat", text: $fat, unit: "g")

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }

                Section("Recent") {
                    if recentLogs.isEmpty {
                        Text("No entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentLogs) { log in
                            HStack {
                                Text(log.date)
                                Spacer()
                                Text("\(Int(log.calories)) kcal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nutrition")
            .task {
                await loadForSelectedDate()
                await loadRecent()
            }
        }
    }

    private func loadForSelectedDate() async {
        do {
            if let log = try await repository.fetchLog(date: selectedDate) {
                calories = String(log.calories)
                protein = String(log.proteinG)
                carbs = String(log.carbsG)
                fat = String(log.fatG)
            } else {
                calories = ""
                protein = ""
                carbs = ""
                fat = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRecent() async {
        do {
            recentLogs = try await repository.fetchRecent(days: 14)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard
            let caloriesValue = Double(calories),
            let proteinValue = Double(protein),
            let carbsValue = Double(carbs),
            let fatValue = Double(fat)
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await repository.upsertLog(
                date: selectedDate,
                calories: caloriesValue,
                proteinG: proteinValue,
                carbsG: carbsValue,
                fatG: fatValue
            )
            errorMessage = nil
            await loadRecent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
