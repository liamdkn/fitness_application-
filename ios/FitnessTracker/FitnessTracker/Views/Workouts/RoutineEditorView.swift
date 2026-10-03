import SwiftUI

struct RoutineEditorView: View {
    @State private var routine: Routine?
    @State private var days: [RoutineDay] = []
    @State private var weeklySchedule: [WeeklyScheduleDay] = []
    @State private var goal: UserGoal?
    @State private var errorMessage: String?
    @State private var showingAddDay = false
    @State private var newDayLabel = ""
    @State private var renamingDay: RoutineDay?
    @State private var renameText = ""
    @State private var editingSlot: WeeklyScheduleDay?
    private let repository = RoutineRepository()
    private let goalsRepository = GoalsRepository()
    private let scheduleRepository = WeeklyScheduleRepository()

    /// From the current phase, if it sets a strength-training target -
    /// used to show whether the split has caught up to it yet.
    private var sessionsTarget: Int? {
        goal?.strengthSessionsPerWeek
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            if let sessionsTarget {
                Section {
                    sessionsBanner(target: sessionsTarget)
                }
            }

            if let routine {
                Section {
                    NavigationLink {
                        RoutineNotesView(routine: routine) {
                            Task { await load() }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Training Notes", systemImage: "cross.case")
                            Text(routine.notes.map { _ in "Pain rules, stop rules, retests" } ?? "Nothing added yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

            if routine != nil {
                Section {
                    ForEach(weeklySchedule) { slot in
                        scheduleRow(for: slot)
                    }
                } header: {
                    Text("Weekly Schedule")
                } footer: {
                    Text("What Train's day carousel shows for each day of the week - a specific workout, an active rest day like a run, or a full rest day.")
                }
            }
        }
        .appScreen()
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
        .sheet(item: $editingSlot) { slot in
            ScheduleSlotEditorView(slot: slot, availableDays: days) { updated in
                if let index = weeklySchedule.firstIndex(where: { $0.id == updated.id }) {
                    weeklySchedule[index] = updated
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleRow(for slot: WeeklyScheduleDay) -> some View {
        Button {
            editingSlot = slot
        } label: {
            HStack {
                Text(slot.weekdayName)
                Spacer()
                Text(scheduleSummary(for: slot))
                    .foregroundStyle(.secondary)
            }
            // Without this, only the two Text views themselves are
            // tappable - the Spacer's gap between them (most of the row)
            // would silently eat taps instead of opening the sheet.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleSummary(for slot: WeeklyScheduleDay) -> String {
        switch slot.dayType {
        case .workout:
            days.first { $0.id == slot.routineDayId }?.label ?? "No day linked"
        case .activeRest:
            slot.cardioType?.displayName ?? "Active Rest"
        case .rest:
            "Rest"
        }
    }

    private var renamingDayBinding: Binding<Bool> {
        Binding(get: { renamingDay != nil }, set: { if !$0 { renamingDay = nil } })
    }

    @ViewBuilder
    private func sessionsBanner(target: Int) -> some View {
        let onTrack = days.count >= target
        VStack(alignment: .leading, spacing: 4) {
            Text("\(days.count) of \(target) planned sessions set up")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(onTrack ? Color.primary : AppColor.warning)
            Text("From your current phase.")
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
                weeklySchedule = try await scheduleRepository.fetchSchedule(routineId: routine.id)
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

/// Sheet for one weekday's `WeeklyScheduleDay` slot - Workout/Active Rest/
/// Rest, plus which routine day or cardio type it maps to.
private struct ScheduleSlotEditorView: View {
    let slot: WeeklyScheduleDay
    let availableDays: [RoutineDay]
    let onSaved: (WeeklyScheduleDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dayType: ScheduledDayType
    @State private var selectedRoutineDayId: UUID?
    @State private var selectedCardioType: CardioType
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = WeeklyScheduleRepository()

    init(slot: WeeklyScheduleDay, availableDays: [RoutineDay], onSaved: @escaping (WeeklyScheduleDay) -> Void) {
        self.slot = slot
        self.availableDays = availableDays
        self.onSaved = onSaved
        _dayType = State(initialValue: slot.dayType)
        _selectedRoutineDayId = State(initialValue: slot.routineDayId ?? availableDays.first?.id)
        _selectedCardioType = State(initialValue: slot.cardioType ?? .inclineTreadmill)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day Type", selection: $dayType) {
                        ForEach(ScheduledDayType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .padding()
                }

                switch dayType {
                case .workout:
                    if availableDays.isEmpty {
                        Text("Add a day to your split first.").foregroundStyle(.secondary)
                    } else {
                        Picker("Workout", selection: Binding(
                            get: { selectedRoutineDayId ?? availableDays.first?.id },
                            set: { selectedRoutineDayId = $0 }
                        )) {
                            ForEach(availableDays) { day in
                                Text(day.label).tag(Optional(day.id))
                            }
                        }
                    }
                case .activeRest:
                    Picker("Cardio Type", selection: $selectedCardioType) {
                        ForEach(CardioType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                case .rest:
                    EmptyView()
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle(slot.weekdayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || (dayType == .workout && availableDays.isEmpty))
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await repository.setSlot(
                id: slot.id,
                dayType: dayType,
                routineDayId: dayType == .workout ? selectedRoutineDayId : nil,
                cardioType: dayType == .activeRest ? selectedCardioType : nil
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
