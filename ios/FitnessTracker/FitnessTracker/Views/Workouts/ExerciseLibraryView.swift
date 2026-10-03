import SwiftUI

/// Every exercise in the catalog, browsable and searchable - reachable
/// straight from the Train tab, not just mid-workout. Tapping one opens
/// `ExerciseHistoryView`, the same full lifting history an exercise's
/// "..." menu opens during an active workout, just without needing a
/// workout in progress to get there. Shares its list/search/grouping and
/// "New Exercise" form with `ExercisePickerView` - same catalog, same
/// filtering rules, only the row's tap action differs.
struct ExerciseLibraryView: View {
    @StateObject private var listViewModel = ExerciseListViewModel()
    @State private var showingAddCustom = false

    var body: some View {
        ExerciseListContent(listViewModel: listViewModel) { exercise in
            NavigationLink {
                ExerciseHistoryView(exercise: exercise)
            } label: {
                ExerciseRowContent(exercise: exercise)
            }
        }
        .appScreen()
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Exercise") { showingAddCustom = true }
            }
        }
        .sheet(isPresented: $showingAddCustom) {
            AddCustomExerciseView { exercise in
                listViewModel.addCustom(exercise)
                showingAddCustom = false
            }
        }
    }
}
