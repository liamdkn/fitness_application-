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
    /// Exercises with at least one logged set - listed first.
    @Published private(set) var triedIds: Set<UUID> = []
    private let repository = ExerciseRepository()

    func isTried(_ exercise: Exercise) -> Bool { triedIds.contains(exercise.id) }

    /// Exercises you have history with first, then the ones you haven't
    /// tried; A-Z within each (the catalogue arrives A-Z, and this sort is
    /// stable).
    private func triedFirst(_ list: [Exercise]) -> [Exercise] {
        list.filter(isTried) + list.filter { !isTried($0) }
    }

    var filtered: [Exercise] {
        let matches = searchText.isEmpty
            ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return triedFirst(matches)
    }

    var groupedByMuscle: [(group: MuscleGroup, exercises: [Exercise])] {
        let byGroup = Dictionary(grouping: filtered) { $0.primaryMuscleGroup }
        return MuscleGroup.allCases.compactMap { group in
            guard let exercises = byGroup[group.rawValue], !exercises.isEmpty else { return nil }
            return (group, triedFirst(exercises))
        }
    }

    func load() async {
        do {
            exercises = try await repository.fetchAll()
            // Advisory ordering only - the list still loads if this fails.
            triedIds = (try? await repository.fetchTriedIds()) ?? []
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
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
            if listViewModel.searchText.isEmpty {
                ForEach(listViewModel.groupedByMuscle, id: \.group) { section in
                    Section(section.group.displayName) {
                        ForEach(section.exercises) { exercise in
                            row(exercise)
                        }
                    }
                    .listRowBackground(AppRowBackground())
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
    /// `false` marks an exercise with no logged sets yet; `nil` shows nothing.
    var isTried: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            if let equipment = exercise.equipment {
                Text(isTried == false ? "\(equipment) \u{00b7} not tried yet" : equipment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isTried == false {
                Text("Not tried yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !exercise.secondaryMuscleGroups.isEmpty {
                Text("Also works " + exercise.secondaryMuscleGroups
                    .map { (MuscleGroup(rawValue: $0)?.displayName ?? $0.capitalized).lowercased() }
                    .joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
