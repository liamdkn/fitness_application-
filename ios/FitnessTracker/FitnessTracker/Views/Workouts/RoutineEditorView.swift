import SwiftUI

struct RoutineEditorView: View {
    @State private var routine: Routine?
    @State private var days: [RoutineDay] = []
    @State private var errorMessage: String?
    @State private var showingAddDay = false
    @State private var newDayLabel = ""
    private let repository = RoutineRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if routine == nil {
                Section {
                    Text("You don't have a split set up yet. Add your first day below - e.g. \"Push\", \"Pull\", \"Legs\", or \"Full Body\".")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(days) { day in
                NavigationLink {
                    RoutineDayEditorView(day: day)
                } label: {
                    Text(day.label)
                }
            }
            .onDelete(perform: removeDays)
        }
        .navigationTitle("My Split")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddDay = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .alert("New Day", isPresented: $showingAddDay) {
            TextField("e.g. Push", text: $newDayLabel)
            Button("Cancel", role: .cancel) { newDayLabel = "" }
            Button("Add") { Task { await addDay() } }
        } message: {
            Text("What's this day called?")
        }
    }

    private func load() async {
        do {
            var activeRoutine = try await repository.fetchActiveRoutine()
            if activeRoutine == nil {
                activeRoutine = try await repository.createRoutine(name: "My Split")
            }
            routine = activeRoutine
            if let routine {
                days = try await repository.fetchDays(routineId: routine.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addDay() async {
        guard let routine, !newDayLabel.isEmpty else { return }
        let label = newDayLabel
        newDayLabel = ""
        do {
            let nextPosition = (days.map(\.position).max() ?? 0) + 1
            let day = try await repository.addDay(routineId: routine.id, label: label, position: nextPosition)
            days.append(day)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeDays(at offsets: IndexSet) {
        let toRemove = offsets.map { days[$0] }
        days.remove(atOffsets: offsets)
        Task {
            for day in toRemove {
                do {
                    try await repository.removeDay(dayId: day.id)
                } catch {
                    // Deletion failed server-side - put the day back rather
                    // than leaving the UI showing it as gone when it isn't.
                    errorMessage = error.localizedDescription
                    days.append(day)
                    days.sort { $0.position < $1.position }
                }
            }
        }
    }
}
