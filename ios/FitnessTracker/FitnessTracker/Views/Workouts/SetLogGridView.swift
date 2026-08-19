import SwiftUI

struct SetLogGridView: View {
    let activeExercise: ActiveExercise
    let onLogSet: (Int, Double, Double?) -> Void
    let onAddSet: () -> Void

    private var rowCount: Int {
        max(activeExercise.plannedSetCount, activeExercise.loggedSets.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(1...max(rowCount, 1), id: \.self) { setIndex in
                if setIndex <= activeExercise.loggedSets.count {
                    confirmedRow(setIndex: setIndex, set: activeExercise.loggedSets[setIndex - 1])
                } else {
                    EditableSetRow(
                        setIndex: setIndex,
                        previous: activeExercise.previousSets[safe: setIndex - 1],
                        placeholder: placeholder(forRowAt: setIndex),
                        onConfirm: onLogSet
                    )
                }
            }
            Button {
                onAddSet()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.caption)
            }
            .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack {
            Text("Set").frame(width: 28, alignment: .leading)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            Text("kg").frame(width: 52, alignment: .center)
            Text("Reps").frame(width: 44, alignment: .center)
            Text("RPE").frame(width: 40, alignment: .center)
            Image(systemName: "checkmark").frame(width: 24).opacity(0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func confirmedRow(setIndex: Int, set: WorkoutSet) -> some View {
        HStack {
            Text("\(setIndex)").frame(width: 28, alignment: .leading)
            Text(previousText(for: activeExercise.previousSets[safe: setIndex - 1]))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(set.weightKg, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 52, alignment: .center)
            Text("\(set.reps)")
                .frame(width: 44, alignment: .center)
            Text(set.rpe.map { String(format: "%.1f", $0) } ?? "\u{2014}")
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .center)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 24)
        }
        .padding(.vertical, 4)
    }

    /// If a set has already been confirmed this session, every later
    /// unconfirmed row's placeholder cascades from the most recently
    /// confirmed set. Otherwise it falls back to this row's own set index
    /// from last session's history.
    private func placeholder(forRowAt setIndex: Int) -> (reps: Int, weightKg: Double)? {
        if let last = activeExercise.loggedSets.last {
            return (last.reps, last.weightKg)
        }
        if let previous = activeExercise.previousSets[safe: setIndex - 1] {
            return (previous.reps, previous.weightKg)
        }
        return nil
    }

    private func previousText(for set: WorkoutSet?) -> String {
        guard let set else { return "\u{2014}" }
        var text = "\(set.reps) \u{00d7} \(String(format: "%.1f", set.weightKg))kg"
        if let rpe = set.rpe {
            text += " @\(String(format: "%.1f", rpe))"
        }
        return text
    }
}

private struct EditableSetRow: View {
    let setIndex: Int
    let previous: WorkoutSet?
    let placeholder: (reps: Int, weightKg: Double)?
    let onConfirm: (Int, Double, Double?) -> Void

    @State private var kgText = ""
    @State private var repsText = ""
    @State private var rpeText = ""

    private var resolvedWeight: Double? {
        Double(kgText) ?? placeholder?.weightKg
    }

    private var resolvedReps: Int? {
        Int(repsText) ?? placeholder?.reps
    }

    /// Unlike reps/weight, RPE never falls back to a placeholder - it's a
    /// subjective per-set reading, so a blank field means "not logged"
    /// rather than silently repeating last set's effort.
    private var resolvedRPE: Double? {
        guard !rpeText.isEmpty else { return nil }
        guard let value = Double(rpeText), (0...10).contains(value) else { return nil }
        return value
    }

    var body: some View {
        HStack {
            Text("\(setIndex)").frame(width: 28, alignment: .leading)
            Text(previousText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(
                "",
                text: $kgText,
                prompt: placeholder.map { Text(String(format: "%.1f", $0.weightKg)).foregroundStyle(.secondary.opacity(0.6)) }
            )
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 52)
            TextField(
                "",
                text: $repsText,
                prompt: placeholder.map { Text("\($0.reps)").foregroundStyle(.secondary.opacity(0.6)) }
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            TextField("\u{2014}", text: $rpeText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 40)
            Button {
                guard let reps = resolvedReps, let weight = resolvedWeight else { return }
                onConfirm(reps, weight, resolvedRPE)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .frame(width: 24)
            .disabled(resolvedReps == nil || resolvedWeight == nil)
        }
        .padding(.vertical, 2)
    }

    private var previousText: String {
        guard let previous else { return "\u{2014}" }
        var text = "\(previous.reps) \u{00d7} \(String(format: "%.1f", previous.weightKg))kg"
        if let rpe = previous.rpe {
            text += " @\(String(format: "%.1f", rpe))"
        }
        return text
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
