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

    private var rowCount: Int {
        activeExercise.loggedSets.count + activeExercise.pendingRows.count
    }

    var body: some View {
        Group {
            header
            ForEach(1...max(rowCount, 1), id: \.self) { setIndex in
                if setIndex <= activeExercise.loggedSets.count {
                    let set = activeExercise.loggedSets[setIndex - 1]
                    let isLast = setIndex == activeExercise.loggedSets.count
                    let label = set.isDropSet
                        ? "\u{21b3}D\(dropNumber(upToIndex: setIndex - 1))"
                        : "\(setIndex)"
                    ConfirmedSetRow(label: label, set: set, isLast: isLast, onAddDrop: onAddDrop, onUnlogSet: onUnlogSet)
                        .listRowSeparator(.hidden)
                } else {
                    let pendingIndex = setIndex - activeExercise.loggedSets.count - 1
                    let kind = activeExercise.pendingRows[safe: pendingIndex] ?? .normal
                    let label = kind == .drop ? "\u{21b3}D" : "\(setIndex)"
                    EditableSetRow(
                        label: label,
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
        SetGridHeader()
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

}

struct EditableSetRow: View {
    let label: String
    let kind: PendingSetKind
    let previous: WorkoutSet?
    let placeholder: (reps: Int, weightKg: Double)?
    let onConfirm: (Int, Double, Double?, Bool) -> Void

    @State private var kgText = ""
    @State private var repsText = ""
    @State private var rpeText = ""
    /// Debounced copies of `kgText`/`repsText`, used only to decide whether
    /// to show the "looks off" warning - typing "18" passes through "1"
    /// first, which alone genuinely looks way off from a reference of say
    /// 10, so judging the warning against every keystroke flashed it on
    /// briefly before the rest of the number arrived. `resolvedWeight`/
    /// `resolvedReps` (what actually gets saved) still read the live text
    /// with no delay - only the warning waits.
    @State private var debouncedKgText = ""
    @State private var debouncedRepsText = ""

    private var resolvedWeight: Double? {
        Double(kgText) ?? placeholder?.weightKg
    }

    private var resolvedReps: Int? {
        Int(repsText) ?? placeholder?.reps
    }

    /// Soft, non-blocking sanity check for the classic kg/reps mix-up (e.g.
    /// typing "20" reps into the kg box after a normal set of 8-12 reps at
    /// 20kg-ish). Only judges what the user actually typed - not the
    /// placeholder fallback itself, which by definition always matches - so
    /// an empty field never triggers it. `reference` prefers this session's
    /// own placeholder (last confirmed/previous-session value for this row)
    /// and falls back to `previous` when there's no placeholder yet.
    private var weightReference: Double? { placeholder?.weightKg ?? previous?.weightKg }
    private var repsReference: Int? { placeholder?.reps ?? previous?.reps }

    private var weightLooksOff: Bool {
        guard let entered = Double(debouncedKgText), let reference = weightReference, reference > 0 else { return false }
        let ratio = entered / reference
        return ratio > 1.8 || ratio < 0.5
    }

    private var repsLooksOff: Bool {
        guard let entered = Int(debouncedRepsText), let reference = repsReference, reference > 0 else { return false }
        let ratio = Double(entered) / Double(reference)
        return ratio > 2.5 || ratio < 0.35
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
            Text(label)
                .font(kind == .drop ? .caption2 : .body)
                .lineLimit(1)
                .frame(width: 28, alignment: .leading)
            Spacer(minLength: 0)
            TextField(
                "",
                text: $kgText,
                prompt: placeholder.map { Text(String(format: "%.1f", $0.weightKg)).foregroundStyle(.secondary.opacity(0.6)) }
            )
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 66)
            // Purely visual - never blocks confirming the set. A border
            // tint plus a small badge rather than extra text, so a row
            // that's already tight on width never has to reflow to fit a
            // warning (that's exactly the kind of column-shifting bug this
            // screen has had before).
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(weightLooksOff ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if weightLooksOff {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: -4)
                }
            }
            TextField(
                "",
                text: $repsText,
                prompt: placeholder.map { Text("\($0.reps)").foregroundStyle(.secondary.opacity(0.6)) }
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(repsLooksOff ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if repsLooksOff {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: -4)
                }
            }
            TextField("\u{2014}", text: $rpeText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 56)
            // Blank, but reserved at the same 50pt width as `ConfirmedSetRow`'s
            // "+Drop" slot - without this, an editable row has less
            // fixed-width content than a confirmed row does, so the two
            // don't line up under the same header (see `SetGridHeader`'s
            // matching placeholder for the full explanation).
            Color.clear.frame(width: 50, height: 1)
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
        .task(id: kgText) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            debouncedKgText = kgText
        }
        .task(id: repsText) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            debouncedRepsText = repsText
        }
    }

}

/// One already-logged set's row. Standalone (not private) and driven by a
/// precomputed `label` rather than a set index, so `SupersetLogGridView`
/// can reuse it for an interleaved "A1, B1, A2, B2..." layout without
/// duplicating this HStack.
struct ConfirmedSetRow: View {
    let label: String
    let set: WorkoutSet
    let isLast: Bool
    let onAddDrop: () -> Void
    let onUnlogSet: (WorkoutSet) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(set.isDropSet ? .caption2 : .body)
                .lineLimit(1)
                .frame(width: 28, alignment: .leading)
            Spacer(minLength: 0)
            Text(set.weightKg, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 66, alignment: .center)
            Text("\(set.reps)")
                .frame(width: 44, alignment: .center)
            Text(set.rpe.map { String(format: "%.1f", $0) } ?? "\u{2014}")
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .center)
            // Reserved at a fixed width and always rendered (hidden via
            // opacity, same trick the header uses for its checkmark glyph)
            // rather than conditionally included - an intrinsically-sized
            // "+ Drop" button that only sometimes appeared here used to
            // shift every fixed-width column after it (most visibly right
            // after confirming a drop set, since that's almost always the
            // newest "last" row), so the slot's width can never change now.
            Button {
                onAddDrop()
            } label: {
                Text("+ Drop")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .frame(width: 50, alignment: .trailing)
            .opacity(isLast ? 1 : 0)
            .disabled(!isLast)
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
}

/// Shared column header for both the single-exercise grid and the combined
/// superset grid - identical columns either way, just a different set of
/// rows underneath.
struct SetGridHeader: View {
    @State private var showingRPEInfo = false

    var body: some View {
        HStack {
            Text("Set").frame(width: 28, alignment: .leading)
            Spacer(minLength: 0)
            Text("kg").frame(width: 66, alignment: .center)
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
            // Reserves the same 50pt `ConfirmedSetRow` gives its "+Drop"
            // slot (always present there, shown or not) - without an
            // equal-width placeholder here, a confirmed row has 50pt more
            // fixed-width content than this header, so its own `Spacer`
            // shrinks to compensate and every column after it lands 50pt
            // left of where the header says it should be.
            Color.clear.frame(width: 50, height: 1)
            Image(systemName: "checkmark").frame(width: 24).opacity(0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
