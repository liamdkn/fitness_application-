import SwiftUI

/// Fibre goal and the preworkout carb target, both editable.
struct NutritionTargetsView: View {
    @State private var fibreGoal = 30
    @State private var preworkoutCarbsPerKg = 1.0
    @State private var loaded = false
    @State private var errorMessage: String?
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        Form {
            Section {
                Stepper(value: $fibreGoal, in: 0...100, step: 1) {
                    LabeledContent("Fibre", value: "\(fibreGoal) g a day")
                }
            } header: {
                Text("Fibre")
            } footer: {
                Text("Shown as a bar in the Nutrition tab. 30 g is a common adult target; set whatever your dietitian or doctor gave you.")
            }
            .listRowBackground(AppRowBackground())

            Section {
                Stepper(value: $preworkoutCarbsPerKg, in: 0...3, step: 0.1) {
                    LabeledContent(
                        "Carbs",
                        value: preworkoutCarbsPerKg == 0 ? "Off" : "\(preworkoutCarbsPerKg.formatted(.number.precision(.fractionLength(1)))) g per kg"
                    )
                }
            } header: {
                Text("Preworkout carbs")
            } footer: {
                Text("What to eat before training, per kg of your latest logged weight. The Preworkout meal shows how many carbs that is and how far along you are, and food you add to it shows how much of that food gets you there. It isn't shown on rest days.")
            }
            .listRowBackground(AppRowBackground())

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle("Fibre & Preworkout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: fibreGoal) { save() }
        .onChange(of: preworkoutCarbsPerKg) { save() }
    }

    private func load() async {
        if let prefs = try? await preferencesRepository.fetch() {
            fibreGoal = prefs.fibreGoalG
            preworkoutCarbsPerKg = prefs.preworkoutCarbsGPerKg
        }
        // Let the assignments above settle before changes count as the user's own.
        try? await Task.sleep(nanoseconds: 300_000_000)
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let (fibre, carbs) = (fibreGoal, (preworkoutCarbsPerKg * 10).rounded() / 10)
        Task {
            do {
                try await preferencesRepository.setNutritionTargets(fibreGoalG: fibre, preworkoutCarbsGPerKg: carbs)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
