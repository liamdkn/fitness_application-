import SwiftUI

struct MainTabView: View {
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
    }
}

#Preview {
    MainTabView()
}
