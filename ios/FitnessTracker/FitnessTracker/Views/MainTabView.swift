import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            StartWorkoutView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            NutritionTabView()
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

/// Routes the Nutrition tab to whichever screen matches the current
/// `NutritionSource` - `MealLogHomeView` for `.inHouse` (see
/// `docs/nutrition-in-house-revamp-brief.md`), `NutritionEntryView` for
/// `.healthkitManual`. Loaded once per tab-view lifetime, same limitation
/// `NutritionEntryView` already had loading this itself: flipping the
/// Settings toggle mid-session doesn't re-route an already-alive tab until
/// next launch/tab-recreation.
private struct NutritionTabView: View {
    @State private var nutritionSource: NutritionSource = .healthkitManual
    private let preferencesRepository = UserPreferencesRepository()

    var body: some View {
        Group {
            if nutritionSource == .inHouse {
                MealLogHomeView()
            } else {
                NutritionEntryView()
            }
        }
        .task {
            nutritionSource = (try? await preferencesRepository.fetch())?.nutritionSource ?? .healthkitManual
        }
    }
}

#Preview {
    MainTabView()
}
