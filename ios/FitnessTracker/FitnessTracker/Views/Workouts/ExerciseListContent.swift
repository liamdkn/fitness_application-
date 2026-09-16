import Combine
import SwiftUI

/// Shared load/search/group-by-muscle-group logic behind every screen that
/// browses the exercise catalog - `ExercisePickerView` (pick one to add to
/// a workout) and `ExerciseLibraryView` (browse the catalog, view history)
/// both read the same catalog and filter it the same way; only what
/// happens when a row is tapped differs between them.
@MainActor
final class ExerciseListViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var searchText = ""
    @Published var errorMessage: String?
    private let repository = ExerciseRepository()

    var filtered: [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var groupedByMuscle: [(group: MuscleGroup, exercises: [Exercise])] {
        let byGroup = Dictionary(grouping: filtered) { $0.primaryMuscleGroup }
        return MuscleGroup.allCases.compactMap { group in
            guard let exercises = byGroup[group.rawValue], !exercises.isEmpty else { return nil }
            return (group, exercises)
        }
    }

    func load() async {
        do {
            exercises = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Folds a just-created custom exercise into the already-loaded list,
    /// re-sorted, rather than re-fetching the whole catalog.
    func addCustom(_ exercise: Exercise) {
        exercises.append(exercise)
        exercises.sort { $0.name < $1.name }
    }
}

/// The shared List scaffold (search, grouped-by-muscle sections, flat
/// filtered results while searching) - each host supplies its own action
/// per row (pick-and-dismiss vs navigate-to-history) via `row`, plus its
/// own navigationTitle/toolbar/sheet chrome around this.
struct ExerciseListContent<Row: View>: View {
    @ObservedObject var listViewModel: ExerciseListViewModel
    @ViewBuilder let row: (Exercise) -> Row

    var body: some View {
        List {
            if let errorMessage = listViewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if listViewModel.searchText.isEmpty {
                ForEach(listViewModel.groupedByMuscle, id: \.group) { section in
                    Section(section.group.displayName) {
                        ForEach(section.exercises) { exercise in
                            row(exercise)
                        }
                    }
                }
            } else {
                ForEach(listViewModel.filtered) { exercise in
                    row(exercise)
                }
            }
        }
        .searchable(text: $listViewModel.searchText, prompt: "Search exercises")
        .task { await listViewModel.load() }
    }
}

/// Shared row label - name plus equipment (when known), used by every
/// exercise-catalog row regardless of what tapping it does.
struct ExerciseRowContent: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            if let equipment = exercise.equipment {
                Text(equipment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
