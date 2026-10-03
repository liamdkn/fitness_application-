import Charts
import SwiftUI

/// Caffeine across the day and across your life: today's estimated level in
/// your body with the time to stop for a good night's sleep, then daily
/// totals over the last week, month or three months. Everything is read from
/// drinks logged as food (`LiquidsRepository`), so it's only as complete as
/// what's been logged - and the level is a model (`CaffeineModel`), an
/// estimate with the half-life you set, not a measurement.
struct CaffeineView: View {
    private enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .quarter: "90 days"
            }
        }
    }

    @State private var day = LiquidsDay()
    @State private var preferences: UserPreferences?
    @State private var resolvedBedtime: BedtimeResolver.Resolved?
    @State private var typicalDoseMg: Double = 95
    @State private var history: [String: Double] = [:]
    @State private var range: Range = .month
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let liquidsRepository = LiquidsRepository()
    private let preferencesRepository = UserPreferencesRepository()

    private var settings: UserPreferences? { preferences }
    private var halfLife: Double { settings?.caffeineHalfLifeHours ?? 5 }
    private var limitMg: Double { Double(settings?.caffeineLimitMg ?? 400) }
    private var targetMg: Double { Double(settings?.caffeineBedtimeTargetMg ?? 50) }
    private var now: Date { Date() }

    private var bedtime: Date {
        CaffeineModel.bedtime(onDayOf: now, minutesAfterMidnight: resolvedBedtime?.minutes ?? settings?.bedtimeMinutes ?? 1350)
    }

    private var doses: [CaffeineModel.Dose] { day.caffeineDoses }

    var body: some View {
        List {
            todaySection
            if !doses.isEmpty || !isLoading {
                chartSection
            }
            adviceSection
            historySection

            Section {
                NavigationLink {
                    CaffeineSettingsView(onSaved: { Task { await load() } })
                } label: {
                    Label("Bedtime, half-life and limits", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("The curve assumes a caffeine half-life of \(String(format: "%g", halfLife)) hours. It's the biggest unknown - it ranges from roughly 3 to 9 hours between people - so adjust it if you find caffeine lingers or fades faster than the curve says.")
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
        }
        .appScreen()
        .navigationTitle("Caffeine")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: range) { Task { await loadHistory() } }
    }

    // MARK: - Today

    private var todaySection: some View {
        let total = day.caffeineMg
        let nowLevel = CaffeineModel.level(at: now, doses: doses, halfLifeHours: halfLife)
        let bedLevel = CaffeineModel.level(at: bedtime, doses: doses, halfLifeHours: halfLife)
        return Section("Today") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(total.rounded())) mg")
                        .font(.title.bold())
                    Text("of \(Int(limitMg)) mg")
                        .foregroundStyle(.secondary)
                }
                AppProgressBar(value: min(total / max(limitMg, 1), 1))
                    .tint(total > limitMg ? AppColor.danger : AppColor.caffeine)
            }
            .padding(.vertical, 4)
            LabeledContent("In your system now", value: "~\(Int(nowLevel.rounded())) mg")
            LabeledContent("At bedtime (\(bedtime.formatted(date: .omitted, time: .shortened)))") {
                Text("~\(Int(bedLevel.rounded())) mg")
                    .foregroundStyle(bedLevel > targetMg ? AppColor.warning : AppColor.success)
            }
            if let resolvedBedtime, resolvedBedtime.fromHealth {
                Label("Bedtime from your last \(resolvedBedtime.nights) nights of sleep in Health", systemImage: "bed.double.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartSection: some View {
        let start = Calendar.current.startOfDay(for: now).addingTimeInterval(5 * 3600)
        let end = max(bedtime.addingTimeInterval(2 * 3600), now.addingTimeInterval(3600))
        let curve = CaffeineModel.curve(doses: doses, halfLifeHours: halfLife, from: start, to: end)
        let peak = max(curve.map(\.mg).max() ?? 0, targetMg * 1.5)
        return Section("Through the day") {
            Chart {
                ForEach(curve, id: \.time) { point in
                    AreaMark(x: .value("Time", point.time), yStart: .value("mg", 0), yEnd: .value("mg", point.mg))
                        .foregroundStyle(AppColor.caffeine.opacity(0.25))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.time), y: .value("mg", point.mg))
                        .foregroundStyle(AppColor.caffeine)
                        .interpolationMethod(.linear)
                }
                ForEach(Array(doses.enumerated()), id: \.offset) { _, dose in
                    PointMark(
                        x: .value("Time", dose.time),
                        y: .value("mg", CaffeineModel.level(at: dose.time, doses: doses, halfLifeHours: halfLife))
                    )
                    .foregroundStyle(AppColor.accent)
                    .symbolSize(60)
                }
                RuleMark(y: .value("Bedtime target", targetMg))
                    .foregroundStyle(AppColor.success)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                RuleMark(x: .value("Bedtime", bedtime))
                    .foregroundStyle(AppColor.bedtime)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Bed").font(.caption2).foregroundStyle(AppColor.bedtime)
                    }
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Now").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...(peak * 1.15))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxisLabel("mg", position: .trailing)
            .frame(height: 200)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Advice

    private var adviceSection: some View {
        Section {
            Label {
                Text(advice)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(AppColor.caffeine)
            }
        } header: {
            Text("When to stop")
        } footer: {
            Text("Based on a typical cup of about \(Int(typicalDoseMg.rounded())) mg (your median from the last 30 days) and aiming for under \(Int(targetMg)) mg when you go to bed.")
        }
    }

    /// The one-line recommendation: the latest a typical cup can be had and
    /// still be under the bedtime target, in light of today's doses so far.
    private var advice: String {
        let bedText = bedtime.formatted(date: .omitted, time: .shortened)
        let remaining = Int(max(limitMg - day.caffeineMg, 0).rounded())
        guard let cutoff = CaffeineModel.latestDoseTime(
            doseMg: typicalDoseMg, bedtime: bedtime, targetMg: targetMg, existing: doses, halfLifeHours: halfLife
        ) else {
            let bedLevel = Int(CaffeineModel.level(at: bedtime, doses: doses, halfLifeHours: halfLife).rounded())
            return "What you've already had leaves about \(bedLevel) mg at \(bedText) - over your \(Int(targetMg)) mg target - so no more today if you want to sleep well."
        }
        let cutoffText = cutoff.formatted(date: .omitted, time: .shortened)
        if cutoff > now {
            return "You can still have a ~\(Int(typicalDoseMg.rounded())) mg cup until \(cutoffText) and be under \(Int(targetMg)) mg at \(bedText). \(remaining) mg left of today's limit."
        }
        let withAnother = doses + [CaffeineModel.Dose(time: now, mg: typicalDoseMg)]
        let ifNow = Int(CaffeineModel.level(at: bedtime, doses: withAnother, halfLifeHours: halfLife).rounded())
        return "The cut-off for a ~\(Int(typicalDoseMg.rounded())) mg cup was \(cutoffText). Another one now would leave about \(ifNow) mg at \(bedText)."
    }

    // MARK: - History

    private var historySection: some View {
        let days = (0..<range.rawValue).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: now)) }.reversed()
        let points: [(date: Date, mg: Double)] = days.map { ($0, history[DateFormatting.isoDate($0)] ?? 0) }
        let total = points.reduce(0) { $0 + $1.mg }
        let daysOver = points.filter { $0.mg > limitMg }.count
        let loggedDays = points.filter { $0.mg > 0 }.count
        return Section {
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Chart {
                ForEach(points, id: \.date) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("mg", point.mg))
                        .foregroundStyle(point.mg > limitMg ? AppColor.danger : AppColor.caffeine)
                }
                RuleMark(y: .value("Limit", limitMg))
                    .foregroundStyle(AppColor.danger.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...max(limitMg * 1.25, (points.map(\.mg).max() ?? 0) * 1.1))
            .frame(height: 170)

            LabeledContent("Average per day", value: "\(Int((total / Double(max(range.rawValue, 1))).rounded())) mg")
            LabeledContent("Days over \(Int(limitMg)) mg", value: "\(daysOver)")
            LabeledContent("Days with caffeine", value: "\(loggedDays) of \(range.rawValue)")
        } header: {
            Text("Over time")
        } footer: {
            Text("Only days you logged drinks on are counted - a day with nothing logged shows as zero.")
        }
    }

    // MARK: - Loading

    private func load() async {
        defer { isLoading = false }
        async let prefs = try? preferencesRepository.fetch()
        async let recent = liquidsRepository.fetchRecentDoses(days: 30)
        do {
            day = try await liquidsRepository.fetchDay(date: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
        preferences = await prefs
        resolvedBedtime = await BedtimeResolver.resolve(preferences)
        let doses = (await recent).sorted()
        if !doses.isEmpty { typicalDoseMg = doses[doses.count / 2] }
        await loadHistory()
    }

    private func loadHistory() async {
        let from = Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        do {
            history = try await liquidsRepository.fetchCaffeineByDay(from: from, to: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Bedtime, caffeine half-life and limits, and the sodium ceiling - the
/// numbers the caffeine curve and the sodium bar are measured against.
struct CaffeineSettingsView: View {
    let onSaved: () -> Void

    @State private var bedtime = Date()
    @State private var halfLife = 5.0
    @State private var limitMg = 400
    @State private var targetMg = 50
    @State private var sodiumLimit = 2300
    @State private var bedtimeFromHealth = true
    @State private var remindersEnabled = true
    @State private var detected: BedtimeResolver.Resolved?
    @State private var loaded = false
    private let repository = UserPreferencesRepository()

    var body: some View {
        Form {
            Section {
                Toggle("Use my sleep from Health", isOn: $bedtimeFromHealth)
                if bedtimeFromHealth, let detected, detected.fromHealth {
                    LabeledContent("Your usual bedtime") {
                        Text(Self.timeText(detected.minutes) + " \u{00b7} \(detected.nights) nights")
                            .foregroundStyle(.secondary)
                    }
                }
                DatePicker(bedtimeFromHealth ? "Fallback bedtime" : "Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                Stepper(value: $targetMg, in: 0...150, step: 10) {
                    LabeledContent("Aim for under", value: "\(targetMg) mg at bedtime")
                }
            } header: {
                Text("Sleep")
            } footer: {
                if bedtimeFromHealth && !(detected?.fromHealth ?? false) {
                    Text("Not enough recorded sleep in Health yet (it needs about four nights), so the fallback bedtime is used. Apple doesn't share the Sleep Schedule you set, only the sleep that's recorded. The 'when to stop' advice works backwards from bedtime so that little caffeine is left when you go to bed.")
                } else {
                    Text("The 'when to stop' advice works backwards from bedtime so that little caffeine is left when you go to bed. With Health sleep on, it's the time you usually fall asleep over the last two weeks.")
                }
            }

            Section {
                Toggle("Caffeine & wind-down reminders", isOn: $remindersEnabled)
            } footer: {
                Text("A 'last call' about half an hour before your last good cup, and a wind-down an hour before bed that says how much caffeine will be left. They're based on the drinks you've logged.")
            }

            Section {
                Stepper(value: $halfLife, in: 2...12, step: 0.5) {
                    LabeledContent("Half-life", value: "\(String(format: "%g", halfLife)) hours")
                }
                Stepper(value: $limitMg, in: 100...800, step: 25) {
                    LabeledContent("Daily limit", value: "\(limitMg) mg")
                }
            } header: {
                Text("Caffeine")
            } footer: {
                Text("About 400 mg a day is the commonly cited ceiling for healthy adults, and 5 hours a typical half-life - but both vary a lot, and this isn't medical advice.")
            }

            Section("Sodium") {
                Stepper(value: $sodiumLimit, in: 1000...4000, step: 100) {
                    LabeledContent("Daily limit", value: "\(sodiumLimit) mg")
                }
            }
        }
        .appScreen()
        .navigationTitle("Caffeine & Sodium")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: bedtime) { save() }
        .onChange(of: halfLife) { save() }
        .onChange(of: limitMg) { save() }
        .onChange(of: targetMg) { save() }
        .onChange(of: sodiumLimit) { save() }
        .onChange(of: bedtimeFromHealth) { save() }
        .onChange(of: remindersEnabled) { save() }
    }

    private static func timeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func load() async {
        guard let prefs = try? await repository.fetch() else { loaded = true; return }
        bedtime = Calendar.current.date(bySettingHour: prefs.bedtimeMinutes / 60, minute: prefs.bedtimeMinutes % 60, second: 0, of: Date()) ?? Date()
        halfLife = prefs.caffeineHalfLifeHours
        limitMg = prefs.caffeineLimitMg
        targetMg = prefs.caffeineBedtimeTargetMg
        sodiumLimit = prefs.sodiumLimitMg
        bedtimeFromHealth = prefs.bedtimeFromHealth
        remindersEnabled = prefs.caffeineRemindersEnabled
        detected = await BedtimeResolver.resolve(prefs)
        // Let the programmatic assignments above settle before onChange
        // handlers start treating changes as the user's own.
        try? await Task.sleep(nanoseconds: 300_000_000)
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        let minutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
        Task {
            _ = try? await repository.setLiquidsSettings(
                sodiumLimitMg: sodiumLimit, caffeineLimitMg: limitMg, bedtimeMinutes: minutes,
                halfLifeHours: halfLife, bedtimeTargetMg: targetMg,
                bedtimeFromHealth: bedtimeFromHealth, remindersEnabled: remindersEnabled
            )
            BedtimeResolver.invalidate()
            await CaffeineReminderService.shared.refresh()
            onSaved()
        }
    }
}
