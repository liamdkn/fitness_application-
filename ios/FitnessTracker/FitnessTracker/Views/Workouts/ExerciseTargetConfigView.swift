import SwiftUI

struct ExerciseTargetConfigView: View {
    let exerciseName: String
    let initialTargetSets: Int
    let initialRepRangeLow: Int
    let initialRepRangeHigh: Int
    let initialWeightIncrementKg: Double
    let onSave: (Int, Int, Int, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetSets: Int
    @State private var repRangeLow: Int
    @State private var repRangeHigh: Int
    @State private var weightIncrementKg: Double

    init(
        exerciseName: String,
        initialTargetSets: Int = 3,
        initialRepRangeLow: Int = 8,
        initialRepRangeHigh: Int = 12,
        initialWeightIncrementKg: Double = 2.5,
        onSave: @escaping (Int, Int, Int, Double) -> Void
    ) {
        self.exerciseName = exerciseName
        self.initialTargetSets = initialTargetSets
        self.initialRepRangeLow = initialRepRangeLow
        self.initialRepRangeHigh = initialRepRangeHigh
        self.initialWeightIncrementKg = initialWeightIncrementKg
        self.onSave = onSave
        _targetSets = State(initialValue: initialTargetSets)
        _repRangeLow = State(initialValue: initialRepRangeLow)
        _repRangeHigh = State(initialValue: initialRepRangeHigh)
        _weightIncrementKg = State(initialValue: initialWeightIncrementKg)
    }

    private var isValid: Bool { repRangeLow > 0 && repRangeHigh >= repRangeLow }

    var body: some View {
        NavigationStack {
            Form {
                Section(exerciseName) {
                    Stepper("Target Sets: \(targetSets)", value: $targetSets, in: 1...10)
                    Stepper("Rep Range Low: \(repRangeLow)", value: $repRangeLow, in: 1...50)
                    Stepper("Rep Range High: \(repRangeHigh)", value: $repRangeHigh, in: 1...50)
                    HStack {
                        Text("Weight Increment")
                        Spacer()
                        TextField(
                            "",
                            value: $weightIncrementKg,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        Text("kg").foregroundStyle(.secondary).font(.caption)
                    }
                }
                if !isValid {
                    Text("Rep range high must be at least rep range low.")
                        .foregroundStyle(AppColor.danger)
                }
            }
            .appScreen()
            .navigationTitle("Configure Exercise")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(targetSets, repRangeLow, repRangeHigh, weightIncrementKg)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
