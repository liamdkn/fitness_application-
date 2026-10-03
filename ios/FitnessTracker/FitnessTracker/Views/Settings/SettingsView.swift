import SwiftUI

private let weekdayNames = [
    1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
    5: "Thursday", 6: "Friday", 7: "Saturday",
]

struct SettingsView: View {
    @ObservedObject private var healthSync = HealthSyncService.shared
    @State private var weeklyCheckinWeekday = 2
    @State private var cardioStepExclusionEnabled = false
    @State private var stepSource: StepSource = .merged
    @State private var stepRemindersEnabled = true
    @State private var stepReminderTime = Date()
    @State private var stepRemindersLoaded = false
    @State private var preferencesError: String?
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        AppNavigationStack {
            Form {
                Section("Goals") {
                    NavigationLink("My Goals") {
                        MyGoalsView()
                    }
                }

                Section("Health") {
                    NavigationLink("Injuries") {
                        InjuriesView()
                    }
                }

                Section("Training") {
                    NavigationLink("Gyms") {
                        GymsSettingsView()
                    }
                }

                Section("Weekly Check-In") {
                    Picker("Check-In Day", selection: $weeklyCheckinWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(weekdayNames[weekday] ?? "").tag(weekday)
                        }
                    }
                    .onChange(of: weeklyCheckinWeekday) { _, newValue in
                        Task { await savePreferences(newValue) }
                    }
                    if let preferencesError {
                        Text(preferencesError).foregroundStyle(AppColor.error)
                    }
                    NavigationLink("Check-In History") {
                        WeeklyCheckinHistoryView()
                    }
                }

                Section("Cardio Step Exclusion") {
                    Toggle("Exclude Machine-Counted Cardio Steps", isOn: $cardioStepExclusionEnabled)
                        .onChange(of: cardioStepExclusionEnabled) { _, newValue in
                            Task { await saveCardioStepExclusion(newValue) }
                        }
                    Text("When on, the Dashboard subtracts steps logged during a cardio session (e.g. treadmill) from today's total, so machine-counted steps don't inflate your real walking count.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Step Source") {
                    Picker("Step Source", selection: $stepSource) {
                        ForEach(StepSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: stepSource) { _, newValue in
                        Task { await saveStepSource(newValue) }
                    }
                    Text("Merged matches the Health app's total. Apple Watch Only counts just Watch-recorded steps, which undercounts on days the Watch isn't worn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Step Reminders") {
                    Toggle("Remind Me To Hit My Step Goal", isOn: $stepRemindersEnabled)
                    if stepRemindersEnabled {
                        DatePicker("Evening Nudge", selection: $stepReminderTime, displayedComponents: .hourAndMinute)
                    }
                    Text("A nudge at the time above if you're still short of your step target, and an earlier one at 2pm if the day is running behind. They use the step count from the last time the app checked Health, which it does in the background through the day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: stepRemindersEnabled) { saveStepReminders() }
                .onChange(of: stepReminderTime) { saveStepReminders() }

                Section("Nutrition") {
                    NavigationLink("Meal Slots") {
                        MealSlotsSettingsView()
                    }
                }

                Section("Apple Health") {
                    healthStatusRow
                    Button("Sync Now") {
                        Task { await healthSync.requestAuthorizationAndSync() }
                    }
                }

                Section("Account") {
                    Button("Sign Out", role: .destructive) {
                        Task { try? await SupabaseService.shared.signOut() }
                    }
                }
            }
            .appScreen()
            .navigationTitle("Settings")
            .task { await loadPreferences() }
        }
    }

    @ViewBuilder
    private var healthStatusRow: some View {
        if healthSync.isSyncing {
            Label("Syncing steps & sleep...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else if let healthError = healthSync.errorMessage {
            Label(healthError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(AppColor.danger)
        } else if let lastSynced = healthSync.lastSyncedAt {
            Label("Synced \(lastSynced, style: .relative) ago", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Label("Not synced yet", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func loadPreferences() async {
        do {
            let preferences = try await preferencesRepository.fetch()
            weeklyCheckinWeekday = preferences.weeklyCheckinWeekday
            cardioStepExclusionEnabled = preferences.cardioStepExclusionEnabled
            stepSource = preferences.stepSource
            stepRemindersEnabled = preferences.stepRemindersEnabled
            stepReminderTime = Calendar.current.date(
                bySettingHour: preferences.stepReminderMinutes / 60, minute: preferences.stepReminderMinutes % 60, second: 0, of: Date()
            ) ?? Date()
            // Let the assignments above settle before the onChange handlers
            // start treating changes as the user's own.
            try? await Task.sleep(nanoseconds: 300_000_000)
            stepRemindersLoaded = true
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func savePreferences(_ weekday: Int) async {
        do {
            try await preferencesRepository.setWeeklyCheckinWeekday(weekday)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func saveStepReminders() {
        guard stepRemindersLoaded else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: stepReminderTime)
        let minutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 30)
        let enabled = stepRemindersEnabled
        Task {
            do {
                try await preferencesRepository.setStepReminders(enabled: enabled, minutes: minutes)
                preferencesError = nil
            } catch {
                preferencesError = error.localizedDescription
            }
            await StepReminderService.shared.refresh(force: true)
        }
    }

    private func saveCardioStepExclusion(_ enabled: Bool) async {
        do {
            try await preferencesRepository.setCardioStepExclusionEnabled(enabled)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    private func saveStepSource(_ source: StepSource) async {
        do {
            try await preferencesRepository.setStepSource(source)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
        await healthSync.requestAuthorizationAndSync()
    }
}
