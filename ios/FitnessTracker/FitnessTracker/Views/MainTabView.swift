import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

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
        .task {
            await HealthSyncService.shared.requestAuthorizationAndSync()
            await DailyCheckinReminderService.shared.requestAuthorization()
            await DailyCheckinReminderService.shared.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.task` only fires once, on this view's first appearance - it
            // won't re-run just from switching back to an already-running
            // app. Re-syncing on every return to foreground means data
            // another app (e.g. MyFitnessPal) wrote to Health while we were
            // in the background shows up without needing a force-quit; for
            // the check-in reminder it's what re-schedules tomorrow's 9am
            // notification once a new day has actually started.
            guard newPhase == .active else { return }
            Task {
                await HealthSyncService.shared.requestAuthorizationAndSync()
                await DailyCheckinReminderService.shared.refresh()
            }
        }
    }
}

#Preview {
    MainTabView()
}
