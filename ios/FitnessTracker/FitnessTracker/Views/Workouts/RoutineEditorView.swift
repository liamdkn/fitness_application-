import SwiftUI

struct RoutineEditorView: View {
    @State private var routine: Routine?
    @State private var days: [RoutineDay] = []
    @State private var goal: UserGoal?
    @State private var errorMessage: String?
    @State private var showingAddDay = false
    @State private var newDayLabel = ""
    @State private var renamingDay: RoutineDay?
    @State private var renameText = ""
    private let repository = RoutineRepository()
    private let goalsRepository = GoalsRepository()

    /// From the current phase, if it sets a strength-training target -
    /// used to show whether the split has caught up to it yet.
    private var sessionsTarget: (total: Int, optional: Int)? {
        guard let total = goal?.strengthSessionsPerWeek else { return nil }
        return (total, goal?.strengthOptionalSessions ?? 0)
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if let sessionsTarget {
                Section {
                    sessionsBanner(target: sessionsTarget.total, optional: sessionsTarget.optional)
                }
            }

            if routine == nil {
                Section {
                    Text("You don't have a split set up yet. Add your first day below - e.g. \"Push\", \"Pull\", \"Legs\", or \"Full Body\".")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(days) { day in
                dayRow(for: day)
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
        .alert("Rename Day", isPresented: renamingDayBinding) {
            TextField("e.g. Day 1 - Upper", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await renameDay() } }
        } message: {
            Text("What's this day called?")
        }
    }

    private var renamingDayBinding: Binding<Bool> {
        Binding(get: { renamingDay != nil }, set: { if !$0 { renamingDay = nil } })
    }

    @ViewBuilder
    private func sessionsBanner(target: Int, optional: Int) -> some View {
        let required = target - optional
        let onTrack = days.count >= required
        VStack(alignment: .leading, spacing: 4) {
            Text("\(days.count) of \(target) planned sessions set up")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(onTrack ? Color.primary : Color.orange)
            Text(optional > 0
                ? "\(required) required + \(optional) optional, from your current phase."
                : "From your current phase - tap a day's badge to mark it optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayRow(for day: RoutineDay) -> some View {
        HStack {
            NavigationLink {
                RoutineDayEditorView(day: day)
            } label: {
                Text(day.label)
            }
            Spacer()
            Button {
                Task { await toggleOptional(day) }
            } label: {
                Text(day.isOptional ? "Optional" : "Required")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(day.isOptional ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(day.isOptional ? .orange : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Rename") {
                renamingDay = day
                renameText = day.label
            }
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
            goal = try? await goalsRepository.fetchCurrentGoal()
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

    private func renameDay() async {
        guard let renamingDay, !renameText.isEmpty else { return }
        do {
            let updated = try await repository.renameDay(dayId: renamingDay.id, label: renameText)
            if let index = days.firstIndex(where: { $0.id == updated.id }) {
                days[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleOptional(_ day: RoutineDay) async {
        do {
            let updated = try await repository.setDayOptional(dayId: day.id, isOptional: !day.isOptional)
            if let index = days.firstIndex(where: { $0.id == updated.id }) {
                days[index] = updated
            }
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
