import SwiftUI

/// One movement within a combined superset card - wraps an `ActiveExercise`
/// with the per-exercise callbacks `SupersetLogGridView` needs to route taps
/// back to the right exercise, plus which letter ("A", "B", ...) this
/// movement is within the pair/circuit.
struct SupersetMember: Identifiable {
    let activeExercise: ActiveExercise
    let movementLetter: String
    let onLogSet: (Int, Double, Double?, Bool) -> Void
    let onUnlogSet: (WorkoutSet) -> Void
    let onAddDrop: () -> Void
    let onRemoveSetRow: (Int) -> Void

    var id: UUID { activeExercise.id }
}

/// Combines a superset's member exercises into one alternating grid -
/// "A1, B1, A2, B2..." in performance order - instead of two separate
/// exercise cards you have to scroll between mid-set. Nothing about how
/// sets are stored or logged changes (each member is still its own
/// `ActiveExercise` with its own independent data); this view only changes
/// how those members are interleaved on screen. Reuses `ConfirmedSetRow`,
/// `EditableSetRow`, and `SetGridHeader` from SetLogGridView.swift so a
/// normal single-exercise grid and a superset grid render identically
/// row-for-row, just in a different order.
struct SupersetLogGridView: View {
    let members: [SupersetMember]
    /// Fires for every member at once - a superset's rounds are meant to
    /// stay in lockstep (that's the point of pairing them), so "add a set"
    /// here means "add a round for the whole pair," not just one
    /// movement's set.
    let onAddRound: () -> Void

    private var maxRounds: Int {
        members.map { $0.activeExercise.loggedSets.count + $0.activeExercise.pendingRows.count }.max() ?? 0
    }

    var body: some View {
        Group {
            SetGridHeader()
            ForEach(1...max(maxRounds, 1), id: \.self) { round in
                ForEach(members) { member in
                    row(for: member, round: round)
                }
            }
            Button {
                onAddRound()
            } label: {
                Label("Add Round", systemImage: "plus")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func row(for member: SupersetMember, round: Int) -> some View {
        let exercise = member.activeExercise
        if round <= exercise.loggedSets.count {
            let set = exercise.loggedSets[round - 1]
            let isLast = round == exercise.loggedSets.count
            let label = set.isDropSet
                ? "\(member.movementLetter)\u{21b3}D"
                : "\(member.movementLetter)\(round)"
            ConfirmedSetRow(label: label, set: set, isLast: isLast, onAddDrop: member.onAddDrop, onUnlogSet: member.onUnlogSet)
                .listRowSeparator(.hidden)
        } else if round <= exercise.loggedSets.count + exercise.pendingRows.count {
            let pendingIndex = round - exercise.loggedSets.count - 1
            let kind = exercise.pendingRows[safe: pendingIndex] ?? .normal
            let label = kind == .drop
                ? "\(member.movementLetter)\u{21b3}D"
                : "\(member.movementLetter)\(round)"
            EditableSetRow(
                label: label,
                kind: kind,
                previous: exercise.previousSets[safe: round - 1],
                placeholder: Self.placeholder(for: exercise, atRow: round),
                onConfirm: member.onLogSet
            )
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    member.onRemoveSetRow(pendingIndex)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        // Else: this member has fewer rounds logged/pending than the
        // group's max this round - leave a gap rather than an empty row,
        // since forcing it to match would mean inventing a set that isn't
        // there for either exercise.
    }

    /// Mirrors `SetLogGridView.placeholder(forRowAt:)` - kept as its own
    /// copy (rather than a shared free function) since it's a two-line,
    /// self-contained rule and duplicating it here is clearer than routing
    /// through the other view's private state.
    private static func placeholder(for activeExercise: ActiveExercise, atRow setIndex: Int) -> (reps: Int, weightKg: Double)? {
        if let last = activeExercise.loggedSets.last {
            return (last.reps, last.weightKg)
        }
        if let previous = activeExercise.previousSets[safe: setIndex - 1] {
            return (previous.reps, previous.weightKg)
        }
        return nil
    }
}
