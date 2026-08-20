import SwiftUI

/// Renders as a `Group` (not a `VStack`) so the header, each set row, and the
/// "Add Set" button become independent List rows rather than being bundled
/// into one shared row. Stacking multiple Buttons inside a single List row
/// caused a real bug on-device: tapping one checkmark could get misattributed
/// and fire every button sharing that row (all sets confirming at once plus
/// "Add Set" triggering). Giving each control its own row fixes that.
struct SetLogGridView: View {
    let activeExercise: ActiveExercise
    let onLogSet: (Int, Double, Double?, Bool) -> Void
    let onUnlogSet: (WorkoutSet) -> Void
    let onAddSet: () -> Void
    let onAddDrop: () -> Void
    let onRemoveSetRow: (Int) -> Void

    @State private var showingRPEInfo = false

    private var rowCount: Int {
        activeExercise.loggedSets.count + activeExercise.pendingRows.count
    }

    var body: some View {
        Group {
            header
            ForEach(1...max(rowCount, 1), id: \.self) { setIndex in
                if setIndex <= activeExercise.loggedSets.count {
                    let set = activeExercise.loggedSets[setIndex - 1]
                    confirmedRow(setIndex: setIndex, set: set)
                        .listRowSeparator(.hidden)
                } else {
                    let pendingIndex = setIndex - activeExercise.loggedSets.count - 1
                    let kind = activeExercise.pendingRows[safe: pendingIndex] ?? .normal
                    EditableSetRow(
                        setIndex: setIndex,
                        kind: kind,
                        previous: activeExercise.previousSets[safe: setIndex - 1],
                        placeholder: placeholder(forRowAt: setIndex),
                        onConfirm: onLogSet
                    )
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onRemoveSetRow(pendingIndex)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            Button {
                onAddSet()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Text("Set").frame(width: 28, alignment: .leading)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            Text("kg").frame(width: 52, alignment: .center)
            Text("Reps").frame(width: 44, alignment: .center)
            HStack(spacing: 2) {
                Text("RPE")
                Button {
                    showingRPEInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingRPEInfo) {
                    Text("Rate of Perceived Exertion (1\u{2013}10) \u{2014} how hard did that set feel?\n\n10 = you couldn't have done another rep.\n7 = you had about 3 more reps left.")
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: 260)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .frame(width: 56, alignment: .center)
            Image(systemName: "checkmark").frame(width: 24).opacity(0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func confirmedRow(setIndex: Int, set: WorkoutSet) -> some View {
        let isLast = setIndex == activeExercise.loggedSets.count
        HStack {
            if set.isDropSet {
                Text("\u{21b3} Drop \(dropNumber(upToIndex: setIndex - 1))")
                    .font(.caption2)
                    .frame(width: 28, alignment: .leading)
            } else {
                Text("\(setIndex)").frame(width: 28, alignment: .leading)
            }
            Text(previousText(for: activeExercise.previousSets[safe: setIndex - 1]))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(set.weightKg, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 52, alignment: .center)
            Text("\(set.reps)")
                .frame(width: 44, alignment: .center)
            Text(set.rpe.map { String(format: "%.1f", $0) } ?? "\u{2014}")
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .center)
            if isLast {
                Button {
                    onAddDrop()
                } label: {
                    Text("+ Drop")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            if isLast {
                Button {
                    onUnlogSet(set)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)
            }
        }
        .padding(.vertical, 4)
    }

    /// Counts how many consecutive drop-tagged sets end at (and include)
    /// this position, purely for the "Drop N" display label - no schema
    /// needed beyond the `isDropSet` tag itself.
    private func dropNumber(upToIndex index: Int) -> Int {
        var count = 0
        var i = index
        while i >= 0, activeExercise.loggedSets[i].isDropSet {
            count += 1
            i -= 1
        }
        return count
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
    let kind: PendingSetKind
    let previous: WorkoutSet?
    let placeholder: (reps: Int, weightKg: Double)?
    let onConfirm: (Int, Double, Double?, Bool) -> Void

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
            if kind == .drop {
                Text("\u{21b3} Drop").font(.caption2).frame(width: 28, alignment: .leading)
            } else {
                Text("\(setIndex)").frame(width: 28, alignment: .leading)
            }
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
                .frame(width: 56)
            Button {
                guard let reps = resolvedReps, let weight = resolvedWeight else { return }
                onConfirm(reps, weight, resolvedRPE, kind == .drop)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.plain)
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
