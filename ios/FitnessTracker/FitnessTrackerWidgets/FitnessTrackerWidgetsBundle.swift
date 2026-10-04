import SwiftUI
import WidgetKit

@main
struct FitnessTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        SupplementLiveActivity()
        TodaySummaryWidget()
        WaterWidget()
        WorkoutWidget()
        StepsAfterCardioWidget()
    }
}
