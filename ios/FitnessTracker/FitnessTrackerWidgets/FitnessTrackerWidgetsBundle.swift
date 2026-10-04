import SwiftUI
import WidgetKit

@main
struct FitnessTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        TodaySummaryWidget()
        WaterWidget()
        WorkoutWidget()
        StepsAfterCardioWidget()
    }
}
