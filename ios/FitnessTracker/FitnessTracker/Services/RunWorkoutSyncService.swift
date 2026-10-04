import Foundation
import HealthKit
import WorkoutKit

/// Converts scheduled runs in the iPhone plan into workouts shown in the
/// system Workout app on Apple Watch. The source plan remains the app's
/// existing planned-runs data; no workout or route data is uploaded here.
@MainActor
struct RunWorkoutSyncService {
    private let scheduler = WorkoutScheduler.shared
    private let warmupMinutes = 10
    private let cooldownMinutes = 10

    struct SyncResult {
        let scheduledCount: Int
        let requestedCount: Int
        let limitReached: Bool
    }

    enum SyncError: LocalizedError {
        case watchUnavailable
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .watchUnavailable:
                "Apple Watch workout scheduling isn't available on this device. Make sure your Watch is paired and try again."
            case .permissionDenied:
                "Allow Fitness Tracker to add scheduled workouts, then try again."
            }
        }
    }

    func syncUpcomingRuns(_ runs: [PlannedRun]) async throws -> SyncResult {
        guard WorkoutScheduler.isSupported else { throw SyncError.watchUnavailable }

        if await scheduler.authorizationState != .authorized {
            guard await scheduler.requestAuthorization() == .authorized else {
                throw SyncError.permissionDenied
            }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let planRunIDs = Set(runs.map(\.id))
        let upcomingRuns = runs
            .filter { $0.runType != .rest && calendar.startOfDay(for: $0.day) >= today }
            .sorted { $0.day < $1.day }

        guard !upcomingRuns.isEmpty else {
            return SyncResult(scheduledCount: 0, requestedCount: 0, limitReached: false)
        }

        let existing = await scheduler.scheduledWorkouts
        let appEntries = existing.filter { planRunIDs.contains($0.plan.id) }
        // Clear only workouts whose IDs belong to runs in this plan. Other
        // apps' workouts, and the user's manually-created workouts, are kept.
        for item in appEntries {
            await scheduler.remove(item.plan, at: item.date)
        }

        let otherScheduledCount = existing.count - appEntries.count
        let availableSlots = max(0, WorkoutScheduler.maxAllowedScheduledWorkoutCount - otherScheduledCount)
        let selectedRuns = Array(upcomingRuns.prefix(availableSlots))

        for run in selectedRuns {
            let workoutPlan = makeWorkoutPlan(for: run)
            let date = calendar.dateComponents([.year, .month, .day], from: run.day)
            await scheduler.schedule(workoutPlan, at: date)
        }

        let scheduledIDs = Set((await scheduler.scheduledWorkouts).map { $0.plan.id })
        let scheduledCount = selectedRuns.filter { scheduledIDs.contains($0.id) }.count
        return SyncResult(
            scheduledCount: scheduledCount,
            requestedCount: upcomingRuns.count,
            limitReached: selectedRuns.count < upcomingRuns.count
        )
    }

    private func makeWorkoutPlan(for run: PlannedRun) -> WorkoutPlan {
        let paceSecondsPerKm: Double? = {
            guard let distanceKm = run.targetDistanceKm,
                  distanceKm > 0,
                  let durationMinutes = run.targetDurationMin,
                  durationMinutes > 0
            else { return nil }
            return Double(durationMinutes * 60) / distanceKm
        }()

        let paceAlert: (any WorkoutAlert)? = paceSecondsPerKm.flatMap { pace in
            let centerSpeed = 1000 / pace
            let speedRange = (centerSpeed * 0.95)...(centerSpeed * 1.05)
            let alert = SpeedRangeAlert(
                target: Measurement(value: speedRange.lowerBound, unit: UnitSpeed.metersPerSecond)
                    ... Measurement(value: speedRange.upperBound, unit: UnitSpeed.metersPerSecond),
                metric: .average
            )
            return CustomWorkout.supportsAlert(alert, activity: .running, location: .outdoor) ? alert : nil
        }

        let paceLabel = paceSecondsPerKm.map { RunFormat.pace(seconds: $0, meters: 1000) }
            .flatMap { $0 }
        var stepTitleParts = [run.runType.displayName]
        if let paceLabel { stepTitleParts.append(paceLabel) }
        if let notes = run.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            stepTitleParts.append(notes)
        }

        let workGoal: WorkoutGoal
        if let distanceKm = run.targetDistanceKm, distanceKm > 0 {
            workGoal = .distance(distanceKm * 1000, .meters)
        } else if let durationMinutes = run.targetDurationMin, durationMinutes > 0 {
            workGoal = .time(Double(durationMinutes * 60), .seconds)
        } else {
            workGoal = .open
        }

        let workout = CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "\(run.runType.displayName) Run",
            warmup: WorkoutStep(
                goal: .time(Double(warmupMinutes * 60), .seconds),
                displayName: "Warm Up · \(warmupMinutes) min"
            ),
            blocks: [
                IntervalBlock(steps: [
                    IntervalStep(.work, step: WorkoutStep(
                        goal: workGoal,
                        alert: paceAlert,
                        displayName: stepTitleParts.joined(separator: " · ")
                    ))
                ])
            ],
            cooldown: WorkoutStep(
                goal: .time(Double(cooldownMinutes * 60), .seconds),
                displayName: "Cool Down · \(cooldownMinutes) min"
            )
        )

        return WorkoutPlan(.custom(workout), id: run.id)
    }
}
