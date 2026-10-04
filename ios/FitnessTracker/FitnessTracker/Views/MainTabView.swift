import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var leftAt: Date?

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            StartWorkoutView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            MealLogHomeView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .top) { OfflineBanner() }
        .task {
            AppIntro.shared.play()
            await WaterRepository().importWidgetWater()
            await OfflineOutbox.shared.flush()
            await MilkAllowanceService.applyIfNeeded()
            await HealthSyncService.shared.requestAuthorizationAndSync()
            await DailyCheckinReminderService.shared.requestAuthorization()
            await DailyCheckinReminderService.shared.refresh()
            await CaffeineReminderService.shared.refresh()
            await StepReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.task` only fires once, on this view's first appearance - it
            // won't re-run just from switching back to an already-running
            // app. Re-syncing on every return to foreground means steps and
            // sleep recorded while we were in the background show up without
            // needing a force-quit; for the check-in reminder it's what
            // re-schedules tomorrow's 9am notification once a new day has
            // actually started.
            if newPhase == .background { leftAt = Date() }
            if newPhase == .active, let leftAt, Date().timeIntervalSince(leftAt) > AppIntro.awayThreshold {
                AppIntro.shared.play()
                self.leftAt = nil
            }
            guard newPhase == .active else { return }
            Task {
                await WaterRepository().importWidgetWater()
                await OfflineOutbox.shared.flush()
                await MilkAllowanceService.applyIfNeeded()
                await HealthSyncService.shared.requestAuthorizationAndSync()
                await DailyCheckinReminderService.shared.refresh()
                await CaffeineReminderService.shared.refresh()
                await StepReminderService.shared.refresh()
                await WidgetSnapshotService.shared.refresh()
            }
        }
    }
}

#Preview {
    MainTabView()
}
