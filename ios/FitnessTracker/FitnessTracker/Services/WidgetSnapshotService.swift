import Foundation
import WidgetKit

/// Gathers today's calories, macros, steps, water and caffeine, saves them
/// where the widgets can read them (`WidgetSnapshot`) and asks WidgetKit to
/// redraw. Like the reminder services it re-reads everything each time rather
/// than patching the last snapshot, and is called wherever those numbers can
/// change: launch, foreground, new steps from Health, drinks and meals logged.
@MainActor
final class WidgetSnapshotService {
    static let shared = WidgetSnapshotService()

    private let preferencesRepository = UserPreferencesRepository()
    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let liquidsRepository = LiquidsRepository()
    private var isRefreshing = false
    private var lastRefresh = Date.distantPast

    private init() {}

    func refresh(force: Bool = false) async {
        guard !isRefreshing, force || Date().timeIntervalSince(lastRefresh) > 20 else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        async let preferencesResult = try? preferencesRepository.fetch()
        async let goalResult = try? goalsRepository.fetchCurrentGoal()
        async let nutritionResult = try? nutritionRepository.fetchDailyTotal(date: now)
        async let liquidsResult = try? liquidsRepository.fetchDay(date: now)
        let preferences = await preferencesResult
        let goal = (await goalResult) ?? nil
        let nutrition = (await nutritionResult) ?? nil
        let liquids = await liquidsResult
        let steps = await StepReminderService.shared.currentSteps(preferences: preferences)

        let snapshot = WidgetSnapshot(
            day: WidgetSnapshot.dayString(now),
            updatedAt: now,
            calories: Int((nutrition?.calories ?? 0).rounded()),
            calorieTarget: goal.map { Int($0.dailyCalorieTarget.rounded()) },
            proteinG: Int((nutrition?.proteinG ?? 0).rounded()),
            proteinTargetG: goal.map { Int($0.proteinGTarget.rounded()) },
            carbsG: Int((nutrition?.carbsG ?? 0).rounded()),
            carbsTargetG: goal?.carbsGTarget.map { Int($0.rounded()) },
            fatG: Int((nutrition?.fatG ?? 0).rounded()),
            fatTargetG: goal?.fatGTarget.map { Int($0.rounded()) },
            steps: steps,
            stepTarget: goal?.stepTarget,
            waterMl: Int((liquids?.hydrationMl ?? 0).rounded()),
            waterTargetMl: preferences?.dailyWaterMlTargetMin ?? 2500,
            caffeineMg: Int((liquids?.caffeineMg ?? 0).rounded()),
            caffeineLimitMg: preferences?.caffeineLimitMg ?? 400
        )
        lastRefresh = now
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
