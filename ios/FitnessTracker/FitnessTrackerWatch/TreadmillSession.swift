import Foundation
import HealthKit
import Observation

/// An incline-treadmill session on the Watch: records a real indoor-walking
/// workout, and the steps counted before and after, then hands the result to
/// the phone.
@Observable
@MainActor
final class TreadmillSession: NSObject {
    enum State { case idle, starting, running, finishing, failed(String) }

    var state: State = .idle
    var startedAt: Date?
    var heartRate: Int?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var stepsBefore = 0

    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { state = .failed("Health isn't available"); return }
        state = .starting
        do {
            let share: Set = [HKObjectType.workoutType()]
            let read: Set = [stepType, HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try await store.requestAuthorization(toShare: share, read: read)

            stepsBefore = await todaysSteps()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .walking
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startedAt = now
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func finish() async {
        guard let session, let builder, let startedAt else { return }
        state = .finishing
        let end = Date()
        session.end()
        do {
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            let stepsAfter = await todaysSteps(until: end)
            let hr = workout?.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute()))
            let kcal = workout?.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie())
            PhoneConnection.shared.send(WatchMessage.Treadmill(
                workoutId: workout?.uuid ?? UUID(), start: startedAt, end: end,
                stepsBefore: stepsBefore, stepsAfter: max(stepsAfter, stepsBefore),
                avgHeartRate: hr.map { Int($0.rounded()) }, activeCalories: kcal
            ).userInfo)
            reset()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        startedAt = nil
        heartRate = nil
        state = .idle
    }

    /// Steps counted today up to now (or `until`).
    private func todaysSteps(until end: Date = Date()) async -> Int {
        let start = Calendar.current.startOfDay(for: end)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate), options: .cumulativeSum
        )
        let result = try? await descriptor.result(for: store)
        return Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
    }
}

extension TreadmillSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
    }
}

extension TreadmillSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        let bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        Task { @MainActor in self.heartRate = bpm.map { Int($0.rounded()) } }
    }
}
