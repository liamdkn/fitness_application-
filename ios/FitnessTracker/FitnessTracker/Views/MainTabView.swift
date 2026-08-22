import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            StartWorkoutView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            NutritionEntryView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task {
            await HealthSyncService.shared.requestAuthorizationAndSync()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // `.task` only fires once, on this view's first appearance - it
            // won't re-run just from switching back to an already-running
            // app. Re-syncing on every return to foreground means data
            // another app (e.g. MyFitnessPal) wrote to Health while we were
            // in the background shows up without needing a force-quit.
            guard newPhase == .active else { return }
            Task { await HealthSyncService.shared.requestAuthorizationAndSync() }
        }
    }
}

#Preview {
    MainTabView()
}
