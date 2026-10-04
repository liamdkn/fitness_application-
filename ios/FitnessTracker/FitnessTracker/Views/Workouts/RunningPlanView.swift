import Combine
import SwiftUI

/// What the Watch recorded for a planned day, summed if there was more than
/// one run that day.
struct RunActual {
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let avgHeartRate: Int?

    var summary: String {
        var parts: [String] = []
        if distanceMeters > 0 { parts.append(RunFormat.km(distanceMeters / 1000)) }
        parts.append("\(Int((durationSeconds / 60).rounded())) min")
        if let pace = RunFormat.pace(seconds: durationSeconds, meters: distanceMeters) { parts.append(pace) }
        if let avgHeartRate { parts.append("\(avgHeartRate) bpm") }
        return parts.joined(separator: " \u{00b7} ")
    }
}

@MainActor
final class RunningPlanViewModel: ObservableObject {
    struct Week: Identifiable {
        let number: Int
        let monday: Date
        let runs: [PlannedRun]
        var id: Int { number }
    }

    @Published var plan: RunningPlan?
    @Published var runs: [PlannedRun] = []
    @Published var sessions: [CardioTrackingSession] = []
    @Published var errorMessage: String?
    @Published var isLoading = true
    /// How many Watch runs the last sync pulled in - shown once so it's
    /// clear where new rows came from.
    @Published var importedCount = 0
    @Published var isSyncing = false
    @Published var isSendingToWatch = false
    @Published var watchSyncMessage: String?
    @Published var watchSyncError: String?

    private let repository = RunningPlanRepository()
    private let watchWorkoutSync = RunWorkoutSyncService()
    private let calendar = Calendar.current

    /// Pulls any Watch runs not yet in the app straight in, no per-run
    /// confirmation - a running plan is only useful if the runs just
    /// appear beside it. Reuses the Dashboard card's detection (so a run
    /// already imported, dismissed there, or matching a live in-app session
    /// is skipped) and only acts on runs; walks, stairmaster and strength
    /// sessions stay behind that card's explicit Import. Best-effort: with
    /// Health access declined, or offline, it quietly imports nothing and
    /// the plan still loads from what's already stored.
    func syncRunsFromWatch() async {
        isSyncing = true
        defer { isSyncing = false }
        let watch = WatchActivityViewModel()
        await watch.loadCandidates()
        var imported = 0
        for candidate in watch.candidates {
            guard case .cardio(let workout, let cardioType) = candidate, workout.kind == .running else { continue }
            await watch.importCardio(workout, cardioType: cardioType)
            if !watch.candidates.contains(where: { $0.id == workout.id }) { imported += 1 }
        }
        importedCount = imported
    }

    func load() async {
        defer { isLoading = false }
        await syncRunsFromWatch()
        do {
            plan = try await repository.fetchActivePlan()
            guard let plan else {
                runs = []
                sessions = []
                return
            }
            runs = try await repository.fetchPlannedRuns(planId: plan.id)
            // From before the plan started, so runs that predate it still show.
            let from = calendar.date(byAdding: .day, value: -90, to: plan.start) ?? plan.start
            sessions = try await repository.fetchRuns(from: from)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var weeks: [Week] {
        guard let plan else { return [] }
        let firstMonday = DateFormatting.mondayOfWeek(containing: plan.start)
        let grouped = Dictionary(grouping: runs) { DateFormatting.mondayOfWeek(containing: $0.day) }
        return grouped.keys.sorted().map { monday in
            let weeksFromStart = calendar.dateComponents([.weekOfYear], from: firstMonday, to: monday).weekOfYear ?? 0
            return Week(
                number: plan.firstWeekNumber + weeksFromStart,
                monday: monday,
                runs: (grouped[monday] ?? []).sorted { $0.date < $1.date }
            )
        }
    }

    /// The run to open from a plan row - the longest one that day.
    func session(for run: PlannedRun) -> CardioTrackingSession? {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: run.day) }
            .max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
    }

    func actual(for run: PlannedRun) -> RunActual? {
        let matching = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: run.day) }
        guard !matching.isEmpty else { return nil }
        let heartRates = matching.compactMap(\.avgHeartRate)
        return RunActual(
            distanceMeters: matching.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            durationSeconds: matching.reduce(0) { $0 + $1.elapsed() },
            avgHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count
        )
    }

    /// Runs the Watch recorded on days with no planned run - everything
    /// before the plan started, or on a day it left blank.
    var otherRuns: [CardioTrackingSession] {
        let plannedDays = Set(runs.filter { $0.runType != .rest }.map { calendar.startOfDay(for: $0.day) })
        return sessions
            .filter { !plannedDays.contains(calendar.startOfDay(for: $0.startedAt)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Planned runs up to and including today - what "how am I doing so
    /// far" is measured against.
    private var dueRuns: [PlannedRun] {
        let today = calendar.startOfDay(for: Date())
        return runs.filter { $0.runType != .rest && calendar.startOfDay(for: $0.day) <= today }
    }

    var dueCount: Int { dueRuns.count }
    var doneCount: Int { dueRuns.filter { actual(for: $0) != nil }.count }

    /// Distance recorded on planned days so far, against the distance
    /// targets that have come due. Time-targeted runs (an easy 35 minutes)
    /// have no distance to compare, so they count as done/not-done above but
    /// not here.
    var kmRun: Double {
        dueRuns.compactMap { actual(for: $0)?.distanceMeters }.reduce(0, +) / 1000
    }

    var kmPlanned: Double {
        dueRuns.compactMap(\.targetDistanceKm).reduce(0, +)
    }

    var plannedDistanceRunsDone: Double {
        dueRuns.filter { $0.targetDistanceKm != nil }.compactMap { actual(for: $0)?.distanceMeters }.reduce(0, +) / 1000
    }

    func reloadSessions() async {
        guard let plan else { return }
        let from = calendar.date(byAdding: .day, value: -90, to: plan.start) ?? plan.start
        if let fresh = try? await repository.fetchRuns(from: from) { sessions = fresh }
    }

    func sendUpcomingRunsToWatch() async {
        isSendingToWatch = true
        watchSyncMessage = nil
        watchSyncError = nil
        defer { isSendingToWatch = false }

        do {
            let result = try await watchWorkoutSync.syncUpcomingRuns(runs)
            if result.requestedCount == 0 {
                watchSyncMessage = "There are no upcoming runs in this plan to send."
            } else if result.limitReached {
                watchSyncMessage = "Sent \(result.scheduledCount) of \(result.requestedCount) upcoming runs. Apple Watch has reached its scheduled-workout limit."
            } else if result.scheduledCount < result.requestedCount {
                watchSyncError = "Apple Watch couldn't confirm every scheduled run. Try syncing again."
            } else {
                watchSyncMessage = "Sent \(result.scheduledCount) upcoming runs to Apple Watch. Find them in the Workout app under Scheduled."
            }
        } catch {
            watchSyncError = error.localizedDescription
        }
    }

    func delete(_ run: PlannedRun) async {
        do {
            try await repository.deleteRun(id: run.id)
            runs.removeAll { $0.id == run.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The running plan: every planned run laid out by week, each next to what
/// the Apple Watch actually recorded that day. Informational, not a
/// pass/fail - a long run 1 km short isn't a failure, it's just the number.
struct RunningPlanView: View {
    @StateObject private var viewModel = RunningPlanViewModel()
    @State private var editingRun: PlannedRun?
    @State private var addingRun = false
    @State private var creatingPlan = false
    @State private var detailSession: CardioTrackingSession?

    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            if viewModel.isSyncing || viewModel.importedCount > 0 {
                Section {
                    if viewModel.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking your Watch for runs...").foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Imported \(viewModel.importedCount) run\(viewModel.importedCount == 1 ? "" : "s") from your Watch", systemImage: "applewatch")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            if let plan = viewModel.plan {
                Section {
                    header(plan)
                }
                .listRowBackground(AppRowBackground())
                ForEach(viewModel.weeks) { week in
                    Section {
                        ForEach(week.runs) { run in
                            runRow(run)
                        }
                    } header: {
                        Text("Week \(week.number) \u{00b7} \(weekRange(week.monday))")
                    }
                    .listRowBackground(AppRowBackground())
                }
            } else if !viewModel.isLoading {
                Section {
                    ContentUnavailableView {
                        Label("No running plan yet", systemImage: "figure.run")
                    } description: {
                        Text("Create a plan, add the runs you're aiming for, and your Watch runs fill in beside them.")
                    } actions: {
                        Button("New Plan") { creatingPlan = true }
                            .buttonStyle(.appPrimaryCompact)
                    }
                    .listRowBackground(Color.clear)
                }
                .listRowBackground(AppRowBackground())
            }

            if !viewModel.otherRuns.isEmpty {
                Section("Other runs") {
                    ForEach(viewModel.otherRuns) { session in
                        otherRunRow(session)
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle("Running Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.plan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingRun = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .appToolbarTint()
                }
            }
        }
        .task {
            await viewModel.load()
            // Fill the extras and route onto runs imported before they were
            // read, then show them - the first open after this update.
            await WatchActivityViewModel().backfillRunExtras()
            await viewModel.reloadSessions()
        }
        .refreshable { await viewModel.load() }
        .navigationDestination(item: $detailSession) { session in
            RunDetailView(session: session)
        }
        .sheet(item: $editingRun) { run in
            PlannedRunEditSheet(planId: run.runningPlanId, existing: run) {
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: $addingRun) {
            if let plan = viewModel.plan {
                PlannedRunEditSheet(planId: plan.id, existing: nil) {
                    Task { await viewModel.load() }
                }
            }
        }
        .sheet(isPresented: $creatingPlan) {
            NewRunningPlanSheet {
                Task { await viewModel.load() }
            }
        }
    }

    private func header(_ plan: RunningPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.name).font(.headline)
            if viewModel.dueCount > 0 {
                AppProgressBar(value: Double(viewModel.doneCount), total: Double(viewModel.dueCount))
                Text("\(viewModel.doneCount) of \(viewModel.dueCount) planned runs done so far")
                    .font(.subheadline)
                if viewModel.kmPlanned > 0 {
                    Text("Distance runs: \(RunFormat.km(viewModel.plannedDistanceRunsDone)) of \(RunFormat.km(viewModel.kmPlanned)) planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Starts \(plan.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let notes = plan.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.sendUpcomingRunsToWatch() }
            } label: {
                if viewModel.isSendingToWatch {
                    Label("Sending to Apple Watch...", systemImage: "applewatch")
                } else {
                    Label("Send upcoming runs to Apple Watch", systemImage: "applewatch")
                }
            }
            .disabled(viewModel.isSendingToWatch)
            .appToolbarTint()
            Text("Each workout has a 10-minute warm-up and cool-down. Pace is calculated when both distance and time are set.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let watchSyncMessage = viewModel.watchSyncMessage {
                Text(watchSyncMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let watchSyncError = viewModel.watchSyncError {
                Text(watchSyncError)
                    .font(.caption)
                    .foregroundStyle(AppColor.error)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func runRow(_ run: PlannedRun) -> some View {
        let actual = viewModel.actual(for: run)
        let isPast = Calendar.current.startOfDay(for: run.day) < today
        let isToday = Calendar.current.isDate(run.day, inSameDayAs: today)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(run.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .foregroundStyle(.primary)
                    Text(run.runType.displayName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                    if isToday {
                        Text("Today").font(.caption2.bold()).foregroundStyle(AppColor.accent)
                    }
                    Spacer()
                    Text(run.targetLabel).foregroundStyle(.secondary)
                }
                if let actual {
                    Label(actual.summary, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColor.success)
                } else if isPast && run.runType != .rest {
                    Text("No run recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = run.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingRun = run }
            if let session = viewModel.session(for: run) {
                Button {
                    detailSession = session
                } label: {
                    Image(systemName: session.hasRoute ? "map" : "chart.bar")
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await viewModel.delete(run) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func otherRunRow(_ session: CardioTrackingSession) -> some View {
        let actual = RunActual(
            distanceMeters: session.distanceMeters ?? 0,
            durationSeconds: session.elapsed(),
            avgHeartRate: session.avgHeartRate
        )
        return Button {
            detailSession = session
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .foregroundStyle(.primary)
                    Text(actual.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: session.hasRoute ? "map" : "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weekRange(_ monday: Date) -> String {
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        let format = Date.FormatStyle().day().month(.abbreviated)
        return "\(monday.formatted(format)) - \(sunday.formatted(format))"
    }
}

/// Add or edit one planned run - date, type, and whichever targets apply.
private struct PlannedRunEditSheet: View {
    let planId: UUID
    let existing: PlannedRun?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var runType: RunType = .easy
    @State private var distanceText = ""
    @State private var durationText = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    private let repository = RunningPlanRepository()

    init(planId: UUID, existing: PlannedRun?, onSaved: @escaping () -> Void) {
        self.planId = planId
        self.existing = existing
        self.onSaved = onSaved
        if let existing {
            _date = State(initialValue: existing.day)
            _runType = State(initialValue: existing.runType)
            _distanceText = State(initialValue: existing.targetDistanceKm.map { RunningPlanDefaults.plain($0) } ?? "")
            _durationText = State(initialValue: existing.targetDurationMin.map(String.init) ?? "")
            _notes = State(initialValue: existing.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $runType) {
                        ForEach(RunType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                .listRowBackground(AppRowBackground())
                if runType != .rest {
                    Section("Target (either or both)") {
                        HStack {
                            Text("Distance")
                            Spacer()
                            TextField("-", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("km").foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Time")
                            Spacer()
                            TextField("-", text: $durationText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("min").foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }
                Section("Notes") {
                    TextField("e.g. 6 x 1 km, easy effort", text: $notes, axis: .vertical)
                }
                .listRowBackground(AppRowBackground())
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle(existing == nil ? "New Run" : "Edit Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                    .appToolbarTint()
                }
            }
        }
    }

    private func save() async {
        let distance = runType == .rest ? nil : Double(distanceText)
        let duration = runType == .rest ? nil : Int(durationText)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing {
                try await repository.updateRun(
                    id: existing.id, date: date, runType: runType,
                    targetDistanceKm: distance, targetDurationMin: duration,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            } else {
                try await repository.addRun(
                    planId: planId, date: date, runType: runType,
                    targetDistanceKm: distance, targetDurationMin: duration,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum RunningPlanDefaults {
    /// "9" not "9.0", "8.5" stays.
    static func plain(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

/// Just enough to start a plan from the app: a name, a start date, and which
/// programme week that start falls in.
private struct NewRunningPlanSheet: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startDate = Date()
    @State private var firstWeek = 1
    @State private var errorMessage: String?
    private let repository = RunningPlanRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Half marathon build)", text: $name)
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Stepper("First week is week \(firstWeek)", value: $firstWeek, in: 1...52)
                }
                .listRowBackground(AppRowBackground())
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .appToolbarTint()
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        do {
            try await repository.createPlan(
                name: name.trimmingCharacters(in: .whitespaces),
                startDate: startDate,
                firstWeekNumber: firstWeek
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
