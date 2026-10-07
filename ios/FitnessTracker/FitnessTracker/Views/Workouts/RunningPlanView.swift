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
                if let line = run.structureLine {
                    Text(line).font(.caption).foregroundStyle(.secondary)
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
    @State private var warmupText = "10"
    @State private var warmupPaceText = ""
    @State private var cooldownText = "10"
    @State private var cooldownPaceText = ""
    @State private var warmupByDistance = false
    @State private var warmupKmText = ""
    @State private var cooldownByDistance = false
    @State private var cooldownKmText = ""
    @State private var mainPaceText = ""
    @State private var blocks: [BlockDraft] = []
    @State private var errorMessage: String?
    private let repository = RunningPlanRepository()

    /// One repeated piece being edited: everything as the text typed.
    private struct BlockDraft: Identifiable {
        let id = UUID()
        var reps = "1"
        var byDistance = true
        var work = ""        // metres when byDistance, else seconds
        var workPace = ""
        var recoverySeconds = ""
        var recoveryPace = ""

        init() {}

        init(_ block: RunBlock) {
            reps = String(block.reps)
            byDistance = block.work.distanceM != nil
            work = block.work.distanceM.map { String(Int($0)) } ?? block.work.seconds.map(String.init) ?? ""
            workPace = PaceText.field(block.work.paceSecPerKm)
            recoverySeconds = block.recovery?.seconds.map(String.init) ?? ""
            recoveryPace = PaceText.field(block.recovery?.paceSecPerKm)
        }

        var block: RunBlock? {
            guard let reps = Int(reps), reps > 0, let amount = Double(work), amount > 0 else { return nil }
            let step = RunStep(
                distanceM: byDistance ? amount : nil,
                seconds: byDistance ? nil : Int(amount),
                paceSecPerKm: PaceText.parse(workPace)
            )
            var recovery: RunStep?
            if let seconds = Int(recoverySeconds), seconds > 0 {
                recovery = RunStep(distanceM: nil, seconds: seconds, paceSecPerKm: PaceText.parse(recoveryPace))
            }
            return RunBlock(reps: reps, work: step, recovery: recovery)
        }
    }

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
            _warmupText = State(initialValue: String(existing.warmupMin ?? 10))
            _warmupPaceText = State(initialValue: PaceText.field(existing.warmupPaceSec))
            _cooldownText = State(initialValue: String(existing.cooldownMin ?? 10))
            _cooldownPaceText = State(initialValue: PaceText.field(existing.cooldownPaceSec))
            _warmupByDistance = State(initialValue: existing.warmupKm != nil)
            _warmupKmText = State(initialValue: existing.warmupKm.map { RunningPlanDefaults.plain($0) } ?? "")
            _cooldownByDistance = State(initialValue: existing.cooldownKm != nil)
            _cooldownKmText = State(initialValue: existing.cooldownKm.map { RunningPlanDefaults.plain($0) } ?? "")
            _mainPaceText = State(initialValue: PaceText.field(existing.mainPaceSec))
            _blocks = State(initialValue: (existing.blocks ?? []).map(BlockDraft.init))
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
                        paceField("Pace", text: $mainPaceText)
                    }
                    .listRowBackground(AppRowBackground())

                    Section {
                        lengthField(byDistance: $warmupByDistance, minutes: $warmupText, km: $warmupKmText)
                        paceField("Pace", text: $warmupPaceText)
                    } header: {
                        Text("Warm-up")
                    } footer: {
                        Text("By time or distance. 0 means no warm-up. Pace is optional, as minutes:seconds per km, e.g. 6:30.")
                    }
                    .listRowBackground(AppRowBackground())

                    Section {
                        ForEach($blocks) { $block in
                            blockEditor($block)
                        }
                        .onDelete { blocks.remove(atOffsets: $0) }
                        Button {
                            blocks.append(BlockDraft())
                        } label: {
                            Label(blocks.isEmpty ? "Add Intervals or Pace Blocks" : "Add Another Block", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Intervals and blocks")
                    } footer: {
                        Text("Repeat a piece at its own pace, e.g. 6 \u{00d7} 400 m at 4:30 with 90 s recovery. When there are blocks they replace the single target above on the Watch.")
                    }
                    .listRowBackground(AppRowBackground())

                    Section {
                        lengthField(byDistance: $cooldownByDistance, minutes: $cooldownText, km: $cooldownKmText)
                        paceField("Pace", text: $cooldownPaceText)
                    } header: {
                        Text("Cool-down")
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

    private func paceField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("m:ss", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("/km").foregroundStyle(.secondary)
        }
    }

    /// A warm-up or cool-down length: minutes or kilometres, whichever is picked.
    private func lengthField(byDistance: Binding<Bool>, minutes: Binding<String>, km: Binding<String>) -> some View {
        VStack(spacing: 8) {
            Picker("Length by", selection: byDistance) {
                Text("Time").tag(false)
                Text("Distance").tag(true)
            }
            .pickerStyle(.segmented)
            if byDistance.wrappedValue {
                HStack {
                    Text("Length")
                    Spacer()
                    TextField("1.5", text: km)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("km").foregroundStyle(.secondary)
                }
            } else {
                minutesField("Length", text: minutes)
            }
        }
    }

    /// Kilometres typed as "1.5" or "1,5", kept to a sensible range; nil if not a number.
    private static func parsedKm(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).map { min(max($0, 0), 20) }
    }

    private func minutesField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("10", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("min").foregroundStyle(.secondary)
        }
    }

    private func blockEditor(_ block: Binding<BlockDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repeat")
                Spacer()
                TextField("1", text: block.reps)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
                Text("\u{00d7}").foregroundStyle(.secondary)
            }
            Picker("Work by", selection: block.byDistance) {
                Text("Distance").tag(true)
                Text("Time").tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Work")
                Spacer()
                TextField("-", text: block.work)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(block.wrappedValue.byDistance ? "m" : "s").foregroundStyle(.secondary)
            }
            paceField("Work pace", text: block.workPace)
            HStack {
                Text("Recovery")
                Spacer()
                TextField("-", text: block.recoverySeconds)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("s").foregroundStyle(.secondary)
            }
            paceField("Recovery pace", text: block.recoveryPace)
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        let distance = runType == .rest ? nil : Double(distanceText)
        let duration = runType == .rest ? nil : Int(durationText)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRest = runType == .rest
        if runType != .rest, (warmupByDistance && Self.parsedKm(warmupKmText) == nil) || (cooldownByDistance && Self.parsedKm(cooldownKmText) == nil) {
            errorMessage = "Enter the warm-up and cool-down distances in km, or switch them back to time."
            return
        }
        let segments = RunningPlanRepository.Segments(
            warmupMin: isRest || warmupByDistance ? nil : Int(warmupText).map { min(max($0, 0), 60) },
            warmupPaceSec: isRest ? nil : PaceText.parse(warmupPaceText),
            cooldownMin: isRest || cooldownByDistance ? nil : Int(cooldownText).map { min(max($0, 0), 60) },
            cooldownPaceSec: isRest ? nil : PaceText.parse(cooldownPaceText),
            warmupKm: isRest || !warmupByDistance ? nil : Self.parsedKm(warmupKmText),
            cooldownKm: isRest || !cooldownByDistance ? nil : Self.parsedKm(cooldownKmText),
            mainPaceSec: isRest ? nil : PaceText.parse(mainPaceText),
            blocks: isRest ? nil : (blocks.compactMap(\.block).isEmpty ? nil : blocks.compactMap(\.block))
        )
        do {
            if let existing {
                try await repository.updateRun(
                    id: existing.id, date: date, runType: runType,
                    targetDistanceKm: distance, targetDurationMin: duration,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    segments: segments
                )
            } else {
                try await repository.addRun(
                    planId: planId, date: date, runType: runType,
                    targetDistanceKm: distance, targetDurationMin: duration,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    segments: segments
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
