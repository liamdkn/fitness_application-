import SwiftUI

/// Today's supplements: tap the circle to log a dose, "1 of 2" counts them up.
/// Long-press (or the menu) for today's override, editing, or undoing a dose.
struct SupplementsView: View {
    @State private var days: [SupplementDay] = []
    @State private var editing: Supplement?
    @State private var adding = false
    @State private var overriding: SupplementDay?
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var deleting: Supplement?
    @AppStorage(SupplementReminderService.liveActivityKey) private var liveActivityOn = false
    private let repository = SupplementRepository()

    var body: some View {
        List {
            if days.isEmpty && loaded {
                Section {
                    Text("Nothing set up yet. Add the supplements you take, how much, and when you'd like a reminder.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppRowBackground())
            }
            ForEach(days) { day in
                row(day)
            }
            .listRowBackground(AppRowBackground())
            Section {
                Toggle("Live Activity", isOn: $liveActivityOn)
            } footer: {
                Text("Shows today's supplements on the Lock Screen and in the Dynamic Island, with a button to tick each one off. Off by default.")
            }
            .listRowBackground(AppRowBackground())
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .onChange(of: liveActivityOn) { Task { await SupplementReminderService.shared.refresh() } }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "this supplement")? Its history is deleted too.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let supplement = deleting { Task { await delete(supplement) } }
                deleting = nil
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .appToolbarTint()
            }
        }
        .task { await load() }
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) {
            SupplementEditorView(supplement: nil, nextSortOrder: days.count)
        }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { supplement in
            SupplementEditorView(supplement: supplement, nextSortOrder: supplement.sortOrder)
        }
        .sheet(item: $overriding, onDismiss: { Task { await load() } }) { day in
            SupplementOverrideSheet(day: day, date: Date())
        }
    }

    private func row(_ day: SupplementDay) -> some View {
        HStack(spacing: 14) {
            Button {
                Task { await take(day) }
            } label: {
                Image(systemName: day.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(day.isDone ? AppColor.success : AppColor.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: day.taken)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.supplement.name).font(.body.weight(.medium))
                    Text(detail(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(day.taken) of \(day.servingsGoal)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(day.isDone ? AppColor.success : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = day.supplement }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = day.supplement } label: { Label("Delete", systemImage: "trash") }
            Button { editing = day.supplement } label: { Label("Edit", systemImage: "pencil") }
                .tint(AppColor.accent)
        }
        .contextMenu {
            Button { overriding = day } label: { Label("Change Today", systemImage: "calendar.badge.clock") }
            if day.taken > 0 {
                Button { Task { await undo(day) } } label: { Label("Undo Last Dose", systemImage: "arrow.uturn.backward") }
            }
            Button { editing = day.supplement } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleting = day.supplement } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// "1 scoop (5 g) each, 5 g a day, changed today, 9:00 AM".
    private func detail(_ day: SupplementDay) -> String {
        var each = day.supplement.amountText(day.amountPerServing)
        if day.supplement.unit == .scoop, let size = day.supplement.scoopSizeG {
            each += " (\(AmountLabel.trimmed(day.amountPerServing * size)) g)"
        }
        var text = "\(each) each"
        if let grams = day.goalGrams, day.servingsGoal > 1 || day.supplement.unit == .scoop {
            text += " \u{00b7} \(AmountLabel.trimmed(grams)) g a day"
        }
        if day.isOverridden { text += " \u{00b7} changed today" }
        if !day.supplement.reminderTimes.isEmpty {
            text += " \u{00b7} " + day.supplement.reminderTimes.map { Self.clock($0) }.joined(separator: ", ")
        }
        return text
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func load() async {
        do {
            days = try await repository.day(date: Date())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
        await SupplementReminderService.shared.refresh()
    }

    private func take(_ day: SupplementDay) async {
        do {
            try await repository.take(supplementId: day.supplement.id, amount: day.amountPerServing)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ day: SupplementDay) async {
        guard let last = day.logs.last else { return }
        do {
            try await repository.deleteLog(id: last.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ supplement: Supplement) async {
        do {
            try await repository.delete(id: supplement.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Add or change a supplement.
struct SupplementEditorView: View {
    let supplement: Supplement?
    let nextSortOrder: Int

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit: SupplementUnit = .capsule
    @State private var amount = 1.0
    @State private var scoopSizeText = ""
    @State private var servings = 1
    @State private var reminderTimes: [Date] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = SupplementRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") {
                    TextField("Name (e.g. Creatine)", text: $name)
                    Picker("Measured in", selection: $unit) {
                        ForEach(SupplementUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper(value: $amount, in: 0.5...100, step: 0.5) {
                        LabeledContent("Each time", value: "\(AmountLabel.trimmed(amount)) \(unit.name(for: amount))")
                    }
                    if unit == .scoop {
                        HStack {
                            Text("Scoop size")
                            Spacer()
                            TextField("5", text: $scoopSizeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $servings, in: 1...12) {
                        LabeledContent("Times a day", value: "\(servings)")
                    }
                }
                .listRowBackground(AppRowBackground())

                Section {
                    ForEach(reminderTimes.indices, id: \.self) { index in
                        DatePicker("Reminder", selection: $reminderTimes[index], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { reminderTimes.remove(atOffsets: $0) }
                    if reminderTimes.count < 8 {
                        Button {
                            let base = Calendar.current.date(bySettingHour: 9 + reminderTimes.count * 4, minute: 0, second: 0, of: Date()) ?? Date()
                            reminderTimes.append(base)
                        } label: {
                            Label("Add Reminder", systemImage: "bell.badge.plus")
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Optional. A reminder only goes off if that dose is still to take.")
                }
                .listRowBackground(AppRowBackground())

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                        .listRowBackground(Color.clear)
                }
            }
            .appScreen()
            .navigationTitle(supplement == nil ? "New Supplement" : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .appToolbarTint()
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let supplement else { return }
        name = supplement.name
        unit = supplement.unit
        amount = supplement.amountPerServing
        scoopSizeText = supplement.scoopSizeG.map { AmountLabel.trimmed($0) } ?? ""
        servings = supplement.servingsPerDay
        reminderTimes = supplement.reminderTimes.map {
            Calendar.current.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: Date()) ?? Date()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let calendar = Calendar.current
        let minutes = reminderTimes.map {
            let parts = calendar.dateComponents([.hour, .minute], from: $0)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        do {
            try await repository.save(
                supplement, name: name.trimmingCharacters(in: .whitespaces), unit: unit, amountPerServing: amount,
                scoopSizeG: Double(scoopSizeText), servingsPerDay: servings, reminderTimes: minutes, sortOrder: nextSortOrder
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Change one day's servings or amount without touching the usual plan.
struct SupplementOverrideSheet: View {
    let day: SupplementDay
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var servings: Int
    @State private var amount: Double
    @State private var errorMessage: String?
    private let repository = SupplementRepository()

    init(day: SupplementDay, date: Date) {
        self.day = day
        self.date = date
        _servings = State(initialValue: day.servingsGoal)
        _amount = State(initialValue: day.amountPerServing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $servings, in: 0...12) {
                        LabeledContent("Times today", value: "\(servings)")
                    }
                    Stepper(value: $amount, in: 0.5...100, step: 0.5) {
                        LabeledContent("Each time", value: day.supplement.amountText(amount))
                    }
                } footer: {
                    Text("Only for today. The usual is \(day.supplement.servingsPerDay) \u{00d7} \(day.supplement.amountText()).")
                }
                .listRowBackground(AppRowBackground())
                if day.isOverridden {
                    Section {
                        Button("Back to the Usual", role: .destructive) {
                            Task {
                                try? await repository.clearOverride(supplementId: day.supplement.id, date: date)
                                dismiss()
                            }
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                        .listRowBackground(Color.clear)
                }
            }
            .appScreen()
            .navigationTitle(day.supplement.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }.appToolbarTint()
                }
            }
        }
    }

    private func save() async {
        do {
            try await repository.setOverride(
                supplementId: day.supplement.id, date: date,
                servingsPerDay: servings, amountPerServing: amount
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The dashboard's glance: how many doses are done today.
struct SupplementsCard: View {
    @State private var days: [SupplementDay] = []
    @State private var loaded = false
    private let repository = SupplementRepository()

    private var taken: Int { days.reduce(0) { $0 + min($1.taken, $1.servingsGoal) } }
    private var goal: Int { days.reduce(0) { $0 + $1.servingsGoal } }

    var body: some View {
        NavigationLink {
            SupplementsView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Supplements").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                if days.isEmpty {
                    Text(loaded ? "Set up your supplements" : " ")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(taken) of \(goal)")
                            .font(.title2.bold())
                            .foregroundStyle(taken >= goal ? AppColor.success : .primary)
                        Text("taken today").foregroundStyle(.secondary)
                    }
                    AppProgressBar(value: goal > 0 ? Double(taken) / Double(goal) : 0)
                        .tint(taken >= goal ? AppColor.success : AppColor.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .task {
            days = (try? await repository.day(date: Date())) ?? []
            loaded = true
        }
    }
}
